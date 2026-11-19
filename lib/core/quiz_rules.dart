// 题库答案 → 平台提交值的纯规则。
//
// 题库返回的格式不完全统一：选择题可能给选项字母，也可能给选项正文；
// 多选题用 `#!#` 分隔；判断题可能给「正确/错误」「对/错」「true/false」。
// 这里做宽松匹配，但匹配不到就返回 null，绝不猜一个答案填上去。
import 'models.dart';

class AnswerMatch {
  const AnswerMatch({required this.value, required this.display});

  /// 直接写进平台提交字段的值。
  final String value;

  /// 给用户看的答案摘要。
  final String display;
}

AnswerMatch? matchAnswer(HomeworkQuestion question, String raw) {
  final String answer = raw.trim();
  if (answer.isEmpty) return null;
  switch (question.type) {
    case HomeworkQuestionType.single:
    case HomeworkQuestionType.multiple:
      return _matchChoice(question, answer);
    case HomeworkQuestionType.judge:
      return _matchJudge(question, answer);
    case HomeworkQuestionType.fill:
      return _matchFill(question, answer);
    case HomeworkQuestionType.short:
      return AnswerMatch(value: answer, display: _shorten(answer));
    case HomeworkQuestionType.unknown:
      return null;
  }
}

AnswerMatch? _matchChoice(HomeworkQuestion question, String raw) {
  if (question.options.isEmpty) return null;

  final List<String> byLetters = _letters(raw, question.options);
  if (byLetters.isNotEmpty) {
    final List<String> keys = byLetters;
    if (keys.length == 1 || question.type == HomeworkQuestionType.multiple) {
      return AnswerMatch(value: keys.join(), display: keys.join());
    }
  }

  final String normalized = normalizeAnswerText(raw);
  final List<({String key, String text})> options = question.options
      .map((HomeworkOption o) => (key: o.key, text: normalizeAnswerText(o.text)))
      .where((({String key, String text}) o) => o.text.isNotEmpty)
      .toList();

  // 单选先找完全相等，避免「北京」误命中「北京大学」。
  if (question.type == HomeworkQuestionType.single) {
    for (final ({String key, String text}) o in options) {
      if (o.text == normalized) {
        return AnswerMatch(value: o.key, display: o.text);
      }
    }
  }

  final List<String> parts = raw
      .split(RegExp(r'#!#|\|'))
      .map(normalizeAnswerText)
      .where((String s) => s.isNotEmpty)
      .toList();

  final Set<String> keys = <String>{};
  for (final ({String key, String text}) o in options) {
    if (parts.any((String p) => p == o.text)) {
      keys.add(o.key);
    }
  }
  if (keys.isEmpty) {
    // 题库只给了部分文字，或把多个正确选项拼在一起：按包含关系兜底。
    for (final ({String key, String text}) o in options) {
      if (o.text.contains(normalized) || normalized.contains(o.text)) {
        keys.add(o.key);
        if (question.type == HomeworkQuestionType.single) break;
      }
    }
  }
  if (keys.isEmpty) return null;
  final String value = keys.join();
  return AnswerMatch(value: value, display: value);
}

AnswerMatch? _matchJudge(HomeworkQuestion question, String raw) {
  final String text = normalizeAnswerText(raw);
  final bool? right = _judgeValue(text);
  if (right == null) return null;
  // 平台提交判断题用 true/false；页面隐藏字段的 val-param 也是这两个值。
  final String value = right ? 'true' : 'false';
  for (final HomeworkOption o in question.options) {
    final String v = o.value.trim().toLowerCase();
    if (v == value) return AnswerMatch(value: v, display: right ? '正确' : '错误');
  }
  return AnswerMatch(value: value, display: right ? '正确' : '错误');
}

bool? _judgeValue(String text) {
  const List<String> wrong = <String>['不正确', '错误', '错', '否', '×', 'false', 'f', 'b'];
  const List<String> right = <String>['正确', '对', '是', '√', 'true', 't', 'a'];
  for (final String w in wrong) {
    if (text.toLowerCase().contains(w)) return false;
  }
  for (final String r in right) {
    if (text.toLowerCase().contains(r)) return true;
  }
  return null;
}

AnswerMatch? _matchFill(HomeworkQuestion question, String raw) {
  if (question.blanks.isEmpty) return null;
  final List<String> parts = raw.split('#!#');
  if (parts.length != question.blanks.length) return null;
  return AnswerMatch(
    value: parts.map((String s) => s.trim()).join('#!#'),
    display: parts.map((String s) => s.trim()).join(' / '),
  );
}

List<String> _letters(String raw, List<HomeworkOption> options) {
  final Set<String> valid = options.map((HomeworkOption o) => o.key.toUpperCase()).toSet();
  final String compact = normalizeAnswerText(raw).toUpperCase();
  if (compact.isEmpty) return <String>[];
  // 只接受纯字母或「A,B」「A、B」「A B」这类标点分隔的字母串；
  // 其他内容（例如选项正文）交给文本匹配。
  final String lettersOnly =
      compact.replaceAll(RegExp(r'[,\u3001\uff0c;\uff1b/\s#!]+'), '');
  if (lettersOnly.isEmpty || !RegExp(r'^[A-Z]+$').hasMatch(lettersOnly)) {
    return <String>[];
  }
  final List<String> out = <String>[];
  for (final int code in lettersOnly.codeUnits) {
    final String key = String.fromCharCode(code);
    if (!valid.contains(key)) return <String>[];
    if (!out.contains(key)) out.add(key);
  }
  return out;
}

String normalizeAnswerText(String value) =>
    value.replaceAll(RegExp(r'[\s\u00a0\x00-\x1F\x7F]+'), '').trim();

String _shorten(String value) =>
    value.length <= 40 ? value : '${value.substring(0, 40)}…';
