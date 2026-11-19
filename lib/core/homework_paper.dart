// 作业作答页解析：把平台返回的 HTML 变成「隐藏票据 + 题目」。
//
// 只解析页面已经给出的内容，不猜接口字段。作业页有新旧两套 DOM：
// 旧移动页是 div.Py-mian1，桌面旧版是 div.TiMu；两套都按同一套模型归一。
import 'package:html/dom.dart';
import 'package:html/parser.dart' as html_parser;

import 'models.dart';

/// 解析失败返回 null（例如响应根本不是作答页）。
HomeworkPaper? parseHomeworkPaper(String body, {required String sourceUrl}) {
  if (body.trim().isEmpty) return null;
  final Document doc = html_parser.parse(body);

  final Map<String, String> fields = <String, String>{};
  for (final Element input in doc.querySelectorAll('input[id]')) {
    final String id = input.id;
    if (id.isEmpty) continue;
    fields[id] = input.attributes['value'] ?? '';
  }

  final List<HomeworkQuestion> questions = <HomeworkQuestion>[];
  final Set<String> seen = <String>{};
  for (final Element el in doc.querySelectorAll('div.Py-mian1, div.TiMu')) {
    final HomeworkQuestion? q = _parseQuestion(el);
    if (q != null && seen.add(q.id)) questions.add(q);
  }
  if (questions.isEmpty && fields.isEmpty) return null;
  return HomeworkPaper(
    sourceUrl: sourceUrl,
    fields: fields,
    questions: questions,
  );
}

HomeworkQuestion? _parseQuestion(Element el) {
  final String id = _questionId(el);
  if (id.isEmpty) return null;

  final int code = _questionTypeCode(el, id);
  final HomeworkQuestionType type = HomeworkQuestionType.fromCode(code);
  final String text = _questionText(el);
  if (text.isEmpty && type == HomeworkQuestionType.unknown) return null;

  final List<HomeworkOption> options =
      (type == HomeworkQuestionType.fill || type == HomeworkQuestionType.short)
          ? const <HomeworkOption>[]
          : _options(el);
  final List<String> blanks = _blankFields(el, id);
  return HomeworkQuestion(
    id: id,
    type: type,
    text: text,
    options: options,
    blanks: blanks,
  );
}

String _questionId(Element el) {
  final String data = (el.attributes['data'] ?? '').trim();
  if (data.isNotEmpty) return data;

  final Element? explicit = el.querySelector('input.questionId, input[name="questionId"]');
  final String value = (explicit?.attributes['value'] ?? '').trim();
  if (value.isNotEmpty) return value;

  final Element? typeInput = el.querySelector('input[name^="answertype"]');
  final String name = typeInput?.attributes['name'] ?? '';
  if (name.startsWith('answertype')) {
    return name.substring('answertype'.length).trim();
  }
  return '';
}

int _questionTypeCode(Element el, String id) {
  final Element? exact = el.querySelector('input[name="answertype$id"]');
  final Element? any = exact ?? el.querySelector('input[name^="answertype"]');
  final int parsed = int.tryParse((any?.attributes['value'] ?? '').trim()) ?? -1;
  if (parsed >= 0) return parsed;

  final String label = el.querySelector('.quesType')?.text ?? '';
  if (label.contains('单选')) return 0;
  if (label.contains('多选')) return 1;
  if (label.contains('填空')) return 2;
  if (label.contains('判断')) return 3;
  if (label.contains('简答') || label.contains('问答')) return 4;
  return -1;
}

String _questionText(Element el) {
  final Element? title = el.querySelector('.Py-m1-title') ??
      el.querySelector('.fontLabel') ??
      el.querySelector('.Zy_TItle') ??
      el.querySelector('.mark_name');
  if (title == null) return '';
  // 克隆后删掉「[单选题]」这类标签，避免把题型混进题库检索文本。
  final Element clone = title.clone(true);
  for (final Element e in clone.querySelectorAll('.quesType')) {
    e.remove();
  }
  return cleanQuestionHtml(clone.innerHtml);
}

List<HomeworkOption> _options(Element el) {
  List<Element> lis = el.querySelectorAll('ul.answerList li').toList();
  if (lis.isEmpty) {
    // 桌面旧版的选项就是带 radio/checkbox 的 li。
    lis = el
        .querySelectorAll('li')
        .where((Element li) => li.querySelector('input') != null)
        .toList();
  }
  final List<HomeworkOption> out = <HomeworkOption>[];
  for (int i = 0; i < lis.length; i++) {
    final Element li = lis[i];
    final Element? em = li.querySelector('em');
    final String fallbackKey = String.fromCharCode('A'.codeUnitAt(0) + i);
    String key = (em?.text ?? '').trim();
    if (key.length > 1) key = key.substring(0, 1);
    if (key.isEmpty) key = fallbackKey;

    final Element? p = li.querySelector('p');
    String text = p?.text ?? li.text;
    text = text.replaceFirst(RegExp(r'^\s*' + RegExp.escape(key) + r'\s*[.、．]?\s*'), '');
    text = text.replaceFirst(RegExp(r'^\s*[A-Z]\s*[.、．]\s*'), '');
    text = _normalizeSpace(text);
    if (text.isEmpty) continue;

    final Element? input = li.querySelector('input');
    out.add(
      HomeworkOption(
        key: key,
        text: text,
        value: (li.attributes['val-param'] ?? input?.attributes['value'] ?? '').trim(),
      ),
    );
  }
  return out;
}

List<String> _blankFields(Element el, String id) {
  final String prefix = 'answer$id';
  final List<String> out = <String>[];
  for (final Element e in el.querySelectorAll('input,textarea')) {
    final String name = (e.attributes['name'] ?? '').trim();
    if (name.startsWith(prefix) && name != prefix && !out.contains(name)) {
      out.add(name);
    }
  }
  out.sort((String a, String b) => _blankIndex(a, prefix).compareTo(_blankIndex(b, prefix)));
  return out;
}

int _blankIndex(String name, String prefix) {
  final String tail = name.substring(prefix.length);
  return int.tryParse(tail) ?? 0;
}

/// 把题目 HTML 洗成适合题库检索的纯文本。
///
/// 图片/音频/附件都保留地址（去掉协议），否则纯图片题会变成空字符串，
/// 题库无法匹配。样式与脚本全部丢弃。
String cleanQuestionHtml(String raw) {
  final DocumentFragment frag = html_parser.parseFragment(raw);
  for (final Element e in frag.querySelectorAll('style,script')) {
    e.remove();
  }
  for (final Element e in frag.querySelectorAll('img,iframe,audio,source')) {
    final String src = (e.attributes['src'] ?? e.attributes['_src'] ?? '').trim();
    if (src.isEmpty) {
      e.remove();
    } else {
      e.replaceWith(Text(src.replaceFirst(RegExp(r'^https?://'), '')));
    }
  }
  return _normalizeSpace(frag.text ?? '')
      .replaceFirst(RegExp(r'^\d+\s*[.、．]\s*'), '')
      .replaceFirst(RegExp(r'^\[[^\]]{1,8}题\]\s*'), '')
      .trim();
}

String _normalizeSpace(String value) => value
    .replaceAll('\u00a0', ' ')
    .replaceAll(RegExp(r'[\x00-\x1F\x7F]+'), ' ')
    .replaceAll(RegExp(r'\s+'), ' ')
    .trim();
