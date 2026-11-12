#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
学习通核心链路参考实现（纯 HTTP，无宿主、无浏览器、无油猴）
用途：验证协议是否仍然有效，跑通后再照抄成 Kotlin。

依赖：仅标准库 + cryptography（AES-CBC）
  pip install cryptography

用法：
  python3 chaoxing_core.py login  <手机号> <密码>
  python3 chaoxing_core.py courses                    # 列出课程
  python3 chaoxing_core.py chapters <courseId> <classId>
  python3 chaoxing_core.py cards    <courseId> <classId> <chapterId>   # 列任务点
  python3 chaoxing_core.py video    <courseId> <classId> <chapterId>   # 刷本章视频任务点

会话保存在同目录 cookies.txt（可手工复制别人已登录的 cookie）。
"""
import base64
import hashlib
import json
import os
import re
import sys
import time
import urllib.parse
import urllib.request
import http.cookiejar

UA = ("Mozilla/5.0 (Linux; Android 14; Pixel 7) AppleWebKit/537.36 "
      "(KHTML, like Gecko) Chrome/120.0.0.0 Mobile Safari/537.36")
COOKIE_FILE = os.path.join(os.path.dirname(os.path.abspath(__file__)), "cookies.txt")
AES_KEY = b"m2oh6Vu^HWe4_AES"          # 学习通 fanyalogin 的固定 key（同时作 iv）
SIGN_SALT = "d_yHJ!$pdA~5"             # 视频进度 enc 的固定盐
STATE = os.path.join(os.path.dirname(os.path.abspath(__file__)), "state.json")

opener = None


# ---------------------------------------------------------------- HTTP 基础
def build_opener():
    global opener
    jar = http.cookiejar.MozillaCookieJar(COOKIE_FILE)
    if os.path.exists(COOKIE_FILE):
        try:
            jar.load(ignore_discard=True, ignore_expires=True)
        except Exception:
            pass
    opener = urllib.request.build_opener(urllib.request.HTTPCookieProcessor(jar))

    def _save(resp=None):
        try:
            jar.save(ignore_discard=True, ignore_expires=True)
        except Exception:
            pass

    # 每次请求后落盘 cookie
    class Saver(urllib.request.BaseHandler):
        def http_response(self, req, resp):
            _save()
            return resp
        https_response = http_response

    opener.add_handler(Saver())


def request(url, method="GET", data=None, headers=None, referer=None, timeout=25):
    h = {
        "User-Agent": UA,
        "Accept": "*/*",
        "Accept-Language": "zh-CN,zh;q=0.9",
        "X-Requested-With": "com.chaoxing.mobile",
    }
    if referer:
        h["Referer"] = referer
    if headers:
        h.update(headers)
    body = None
    if data is not None:
        body = urllib.parse.urlencode(data).encode() if isinstance(data, dict) else data
        h.setdefault("Content-Type", "application/x-www-form-urlencoded")
    req = urllib.request.Request(url, data=body, headers=h, method=method)
    try:
        with opener.open(req, timeout=timeout) as r:
            return r.read().decode("utf-8", "replace")
    except Exception as e:
        print(f"  ! {method} {url.split('?')[0]} -> {e}")
        return None


# ---------------------------------------------------------------- 加密
def aes_cbc_b64(text: str) -> str:
    """学习通 fanyalogin 的 uname/password 加密：AES-128-CBC，key=iv，PKCS7，base64。"""
    from cryptography.hazmat.primitives.ciphers import Cipher, algorithms, modes
    from cryptography.hazmat.primitives import padding
    padder = padding.PKCS7(128).padder()
    raw = padder.update(text.encode("utf-8")) + padder.finalize()
    enc = Cipher(algorithms.AES(AES_KEY), modes.CBC(AES_KEY)).encryptor()
    return base64.b64encode(enc.update(raw) + enc.finalize()).decode()


def progress_enc(class_id, uid, job_id, object_id, play_time, duration) -> str:
    """视频进度签名：md5([classId][uid][jobid][objectid][ms][盐][duration_ms][0_duration])"""
    play_time, duration = int(play_time), int(duration)
    s = (f"[{class_id}][{uid}][{job_id}][{object_id}][{play_time * 1000}]"
         f"[{SIGN_SALT}][{duration * 1000}][0_{duration}]")
    return hashlib.md5(s.encode()).hexdigest()


# ---------------------------------------------------------------- 业务
def login(username, password):
    url = "https://passport2.chaoxing.com/fanyalogin"
    form = {
        "fid": "-1",
        "refer": "https://i.chaoxing.com",
        "t": "true",
        "forbidotherlogin": "0",
        "validate": "",
        "uname": aes_cbc_b64(username),
        "password": aes_cbc_b64(password),
    }
    raw = request(url, "POST", form)
    if not raw:
        return None
    data = json.loads(raw)
    if data.get("status") is True:
        print("  登录成功")
        return data
    msg = data.get("msg2") or data.get("mes") or data.get("msg") or data
    print(f"  登录失败：{msg}")
    if data.get("needVcode") or data.get("containTwoFactorLogin"):
        print("  需要验证码/二次验证：请用浏览器登录一次，把 cookies.txt 换成浏览器导出的 cookie")
    return None


def profile():
    raw = request("https://sso.chaoxing.com/apis/login/userLogin4Uname.do")
    if not raw:
        return {}
    try:
        return json.loads(raw).get("msg", {})
    except Exception:
        return {}


def courses():
    raw = request("https://mooc1-api.chaoxing.com/mycourse/backclazzdata?view=json&rss=1")
    if not raw:
        return []
    data = json.loads(raw)
    out = []
    for item in data.get("channelList") or data.get("channel") or []:
        content = item.get("content") or {}
        cl = content.get("course", {}).get("data") or []
        course = cl[0] if cl else {}
        cid, klid = str(course.get("id", "")), str(content.get("id", ""))
        if not cid.isdigit() or not klid.isdigit():
            continue
        out.append({
            "courseId": cid,
            "classId": klid,
            "cpi": str(content.get("cpi") or item.get("cpi") or ""),
            "name": course.get("name"),
            "teacher": course.get("teacherfactor"),
        })
        print(f"  {cid}/{klid}  {course.get('name')}  ({course.get('teacherfactor')})")
    return out


def chapters(course_id, class_id, cpi=""):
    """从学生课程页里抠 chapterId。返回 [(chapterId, 标题), ...]"""
    url = (f"https://mooc1.chaoxing.com/mycourse/studentcourse?courseId={course_id}"
           f"&clazzid={class_id}&forcedJoin=1&knowledgeid=0&ut=s&cpi={cpi}")
    html = request(url, referer="https://i.chaoxing.com")
    if not html:
        return []
    found = []
    for m in re.finditer(r"chapterId=(\d+)[^>]*>\s*(?:<[^>]+>\s*)*([^<]{1,60})", html):
        cid, name = m.group(1), m.group(2).strip()
        if (cid, name) not in found:
            found.append((cid, name))
    if not found:
        for cid in dict.fromkeys(re.findall(r"chapterId=(\d+)", html)):
            found.append((cid, ""))
    for cid, name in found:
        print(f"  {cid}  {name}")
    return found


def cards(course_id, class_id, chapter_id, cpi="", page=0):
    """拉章节卡片，返回 (mArg.defaults, attachments)"""
    url = ("https://mooc1.chaoxing.com/knowledge/cards"
           f"?clazzid={class_id}&courseid={course_id}&knowledgeid={chapter_id}"
           f"&num={page}&ut=s&cpi={cpi}&v=20160407-1")
    ref = (f"https://mooc1.chaoxing.com/mycourse/studentstudy?chapterId={chapter_id}"
           f"&courseId={course_id}&clazzid={class_id}&cpi={cpi}"
           f"&enc={hashlib.md5(str(time.time()).encode()).hexdigest()}&mooc2=1")
    html = request(url, referer=ref)
    if not html:
        return None, []
    m = re.search(r"mArg\s*=\s*(\{.+?\});\s*\}\s*catch", html, re.S)
    if not m:
        print("  ! 没有找到 mArg（章节未开放 / 上一章未完成）")
        return None, []
    payload = json.loads(m.group(1))
    defaults = payload.get("defaults", {})
    items = []
    for att in payload.get("attachments", []):
        if not att.get("job"):
            continue
        prop = att.get("property") or {}
        items.append({
            "type": att.get("type"),
            "jobid": att.get("jobid"),
            "objectid": prop.get("objectid"),
            "name": prop.get("name"),
            "otherInfo": att.get("otherInfo"),
            "doublespeed": prop.get("doublespeed"),
            "fastforward": prop.get("fastforward"),
            "rt": prop.get("rt", "0.9"),
            "attDuration": att.get("attDuration", "0"),
            "attDurationEnc": att.get("attDurationEnc", ""),
            "videoFaceCaptureEnc": att.get("videoFaceCaptureEnc", ""),
        })
    return defaults, items


# ---------------------------------------------------------------- 刷视频
def watch_video(defaults, att, class_id, uid, step_seconds=60):
    object_id = att["objectid"]
    fid = defaults.get("fid", "666")
    status_url = (f"https://mooc1.chaoxing.com/ananas/status/{object_id}"
                  f"?k={fid}&flag=normal&_dc={int(time.time() * 1000)}")
    raw = request(status_url,
                  referer=f"https://mooc1.chaoxing.com/ananas/modules/video/index.html?v=2024")
    if not raw:
        return False
    info = json.loads(raw)
    if info.get("status") != "success" or not info.get("duration"):
        print(f"  ! 视频不可用：{att['name']}")
        return False
    duration = int(info["duration"])
    dtoken = info["dtoken"]
    report = defaults.get("reportUrl", "")
    print(f"  ▶ {att['name']}  时长 {duration // 60} 分 {duration % 60} 秒")

    play_time, isdrag = 0, "3"
    while True:
        if play_time >= duration:
            play_time, isdrag = duration, "4"
        enc = progress_enc(class_id, uid, att["jobid"], object_id, play_time, duration)
        q = urllib.parse.urlencode({
            "clazzId": class_id, "playingTime": play_time, "duration": duration,
            "clipTime": f"0_{duration}", "objectId": object_id,
            "otherInfo": att["otherInfo"], "jobid": att["jobid"], "userid": uid,
            "isdrag": isdrag, "view": "pc", "enc": enc, "rt": att["rt"],
            "videoFaceCaptureEnc": att["videoFaceCaptureEnc"], "dtype": "Video",
            "_t": int(time.time() * 1000), "attDuration": att["attDuration"],
            "attDurationEnc": att["attDurationEnc"],
        }, quote_via=urllib.parse.quote)
        raw = request(f"{report}/{dtoken}?{q}",
                      referer=f"https://mooc1.chaoxing.com/ananas/modules/video/index.html?v=2024")
        if raw:
            try:
                res = json.loads(raw)
            except Exception:
                res = {}
            if res.get("isPassed"):
                print(f"  ✓ 完成：{att['name']}")
                return True
            if isdrag == "4":
                print(f"  ! 已到结尾但平台未判定完成：{att['name']}（可能有人脸抽检或倍速限制）")
                return False
        print(f"    {play_time//60} 分 / {duration//60} 分")
        if isdrag == "4":
            break
        play_time += step_seconds
        time.sleep(1.0)


def run_videos(course_id, class_id, chapter_id, cpi=""):
    me = profile()
    uid = str(me.get("puid", "")).strip()
    if not uid:
        print("  ! 会话无效，先 login")
        return
    print(f"  当前账号：{me.get('name')} ({uid})")
    defaults, items = cards(course_id, class_id, chapter_id, cpi)
    if not defaults:
        return
    defaults.setdefault("userid", uid)
    for att in items:
        print(f"  · {att['type']:10s} {att['name']}  job={att['jobid']}")
        if att["type"] == "video" and att.get("objectid"):
            watch_video(defaults, att, class_id, uid)


# ---------------------------------------------------------------- CLI
def main():
    build_opener()
    if len(sys.argv) < 2:
        print(__doc__)
        return
    cmd = sys.argv[1]
    if cmd == "login":
        login(sys.argv[2], sys.argv[3])
    elif cmd == "courses":
        courses()
    elif cmd == "chapters":
        chapters(sys.argv[2], sys.argv[3], sys.argv[4] if len(sys.argv) > 4 else "")
    elif cmd == "cards":
        d, items = cards(sys.argv[2], sys.argv[3], sys.argv[4],
                         sys.argv[5] if len(sys.argv) > 5 else "")
        print(json.dumps(d, ensure_ascii=False, indent=1)[:800])
        for i in items:
            print(f"  {i['type']:10s} {i['name']}")
    elif cmd == "video":
        run_videos(sys.argv[2], sys.argv[3], sys.argv[4],
                   sys.argv[5] if len(sys.argv) > 5 else "")
    else:
        print(__doc__)


if __name__ == "__main__":
    main()
