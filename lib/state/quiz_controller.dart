// 自动刷题会话：打开作答页 → 题库查答案 → 回填 → 提交。
//
// 所有网络与解析都在这里串行执行，UI 只读状态。提交前不做二次确认，
// 但会把「匹配到几题、平台回执是什么」完整写进日志，避免结果不透明。
import 'dart:async';
import 'dart:math';

import '../core/chaoxing_api.dart';
import '../core/homework_paper.dart';
import '../core/models.dart';
import '../core/question_bank.dart';
import '../core/quiz_rules.dart';

class QuizController {
  QuizController({
    required ChaoxingApi api,
    required void Function() onChanged,
  })  : _api = api,
        _onChanged = onChanged;

  final ChaoxingApi _api;
  final void Function() _onChanged;
  final Random _random = Random();
  bool _disposed = false;

  bool busy = false;
  bool cancelled = false;
  String? error;
  List<String> logs = <String>[];
  int done = 0;
  int total = 0;
  int answered = 0;
  bool submitted = false;
  bool? submitOk;
  String? resultMessage;
  int? left;
  String? title;

  bool get canCancel => busy && !cancelled;

  Future<void> run({
    required Course course,
    required HomeworkItem item,
    required String token,
    required String userId,
    required String courseName,
  }) async {
    if (busy) return;
    busy = true;
    cancelled = false;
    error = null;
    logs = <String>[];
    done = 0;
    total = 0;
    answered = 0;
    submitted = false;
    submitOk = null;
    resultMessage = null;
    left = null;
    title = item.name;
    _notify();

    try {
      if (!WanJuanBank.isValidToken(token)) {
        error = '题库 Token 格式不对（应为 32 位数字/小写字母）';
        return;
      }
      _log('正在打开作业页…');
      final Result<String> page = await _api.fetchHomeworkPage(
        course: course,
        workId: item.workId,
      );
      if (page is Err<String>) {
        error = page.code == 'authExpired' ? '登录已失效，请重新连接账号' : page.message;
        return;
      }
      final String sourceUrl =
          'https://mooc1.chaoxing.com/mooc-ans/work/doHomeWorkNew'
          '?courseId=${course.courseId}&classId=${course.classId}&workId=${item.workId}';
      final HomeworkPaper? paper = parseHomeworkPaper(
        (page as Ok<String>).value,
        sourceUrl: sourceUrl,
      );
      if (paper == null) {
        error = '作业页无法解析，可能平台改了页面结构';
        return;
      }
      if (paper.questions.isEmpty) {
        error = '没有识别到题目，可能这份作业是老版页面或已经截止';
        return;
      }
      if (paper.workId.isEmpty) {
        error = '作业页缺少题库需要的作业 id，请重新打开作业页';
        return;
      }

      final List<HomeworkQuestion> questions =
          paper.questions.where((HomeworkQuestion q) => q.answerable).toList();
      total = questions.length;
      if (total == 0) {
        error = '这份作业没有可自动作答的题型';
        return;
      }
      _log('识别到 $total 道题，正在校验题库 Token…');

      final WanJuanBank bank = WanJuanBank(token: token);
      final Result<int> check = await bank.checkLeft();
      if (check is Err<int>) {
        error = check.message;
        return;
      }
      final int remaining = (check as Ok<int>).value;
      left = remaining;
      if (remaining < 1) {
        error = remaining < 0
            ? '题库 Token 无效或未注册'
            : '题库剩余次数不足，请先到万卷题库充值';
        return;
      }
      _log('题库剩余 $remaining 次');

      final Map<String, String> answers = <String, String>{};
      for (final HomeworkQuestion q in questions) {
        if (cancelled) break;
        done++;
        if (q.type == HomeworkQuestionType.short) {
          _log('第 $done 题：简答题暂不自动作答');
          _notify();
          continue;
        }
        if (q.type == HomeworkQuestionType.fill && q.blanks.isEmpty) {
          _log('第 $done 题：填空题没有识别到空位，跳过', error: true);
          _notify();
          continue;
        }
        if (q.text.isEmpty) {
          _log('第 $done 题：题干为空，跳过', error: true);
          _notify();
          continue;
        }

        final List<String> options = q.type == HomeworkQuestionType.judge
            ? <String>['对', '错']
            : q.type == HomeworkQuestionType.fill
                ? <String>[]
                : q.options.map((HomeworkOption o) => o.text).toList();
        final Result<BankAnswer> result = await bank.query(
          question: q.text,
          type: q.type,
          options: options,
          // 题库只在填空题用 answernum；选择题传选项数会被当成空位数。
          answerNum: q.type == HomeworkQuestionType.fill ? q.blanks.length : 0,
          wid: paper.workId,
          cid: paper.field('courseId').isEmpty ? course.courseId : paper.field('courseId'),
          courseName: courseName,
        );
        if (result is Err<BankAnswer>) {
          _log('第 $done 题：${result.message}', error: true);
        } else {
          final BankAnswer answer = (result as Ok<BankAnswer>).value;
          if (answer.left >= 0) left = answer.left;
          final AnswerMatch? match = matchAnswer(q, answer.text);
          if (match == null) {
            _log('第 $done 题：题库答案无法匹配选项（${_shorten(answer.text)}）', error: true);
          } else {
            answers[q.id] = match.value;
            answered++;
            _log('第 $done 题：${match.display}');
          }
          if (left != null && left! <= 0) {
            _log('题库次数已用完，停止查题');
            _notify();
            break;
          }
        }
        _notify();
        if (!cancelled && done < total) {
          await Future<void>.delayed(
            Duration(milliseconds: 1800 + _random.nextInt(1200)),
          );
        }
      }

      if (cancelled) {
        error = '已停止，未提交';
        return;
      }
      if (answers.isEmpty) {
        error = '题库没有匹配到任何答案，本次未提交';
        return;
      }

      _log('已匹配 $answered/$total 题，正在提交…');
      final Result<HomeworkSubmitResult> submit = await _api.submitHomework(
        course: course,
        paper: paper,
        answers: answers,
        userId: userId,
      );
      if (submit is Err<HomeworkSubmitResult>) {
        error = submit.code == 'authExpired'
            ? '登录已失效，请重新连接账号'
            : submit.message;
        return;
      }
      final HomeworkSubmitResult value = (submit as Ok<HomeworkSubmitResult>).value;
      submitOk = value.ok;
      submitted = value.ok != false;
      resultMessage = value.message;
      _log(value.message, error: value.ok == false);
    } catch (e) {
      error = '自动答题失败：$e';
    } finally {
      busy = false;
      _notify();
    }
  }

  /// 请求停止。当前请求不会被打断，但不会再查下一题、也不会提交。
  void cancel() {
    if (!busy || cancelled) return;
    cancelled = true;
    _log('正在停止…');
    _notify();
  }

  void reset() {
    busy = false;
    cancelled = false;
    error = null;
    logs = <String>[];
    done = 0;
    total = 0;
    answered = 0;
    submitted = false;
    submitOk = null;
    resultMessage = null;
    left = null;
    title = null;
    _notify();
  }

  void _log(String line, {bool error = false}) {
    logs.add(error ? '× $line' : '· $line');
    if (logs.length > 200) logs.removeRange(0, logs.length - 200);
    _notify();
  }

  void _notify() {
    if (!_disposed) _onChanged();
  }

  void dispose() {
    _disposed = true;
  }

  static String _shorten(String value) =>
      value.length <= 24 ? value : '${value.substring(0, 24)}…';
}
