import 'package:auto_chaoxing/core/homework_paper.dart';
import 'package:auto_chaoxing/core/models.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const String html = '''
<html><body>
<input type="hidden" id="workAnswerId" value="55256455"/>
<input type="hidden" id="answerId" value="55256455"/>
<input type="hidden" id="totalQuestionNum" value="e0fd4ae12458a2365c8d760026d000cf"/>
<input type="hidden" id="fullScore" value="100.0"/>
<input type="hidden" id="enc_work" value="4f0fbbda67ea4db89545251f2ece5e44"/>
<input type="hidden" id="oldWorkId" value="4e2b7b95bb5a4de4bd8010567d0f4e99"/>
<input type="hidden" id="classId" value="117860940"/>
<input type="hidden" id="courseId" value="247600650"/>
<input type="hidden" id="cpi" value="283918535"/>
<input type="hidden" id="userId" value="253568561"/>
<div class="zquestions">
  <div class="Py-mian1 singleQuesId" data="101">
    <div class="Py-m1-title fs16 fontLabel">1.<span class="quesType">[单选题]</span> 中国的首都是？</div>
    <ul class="answerList">
      <li id-param="101" val-param="A"><em>A</em><p>北京</p></li>
      <li id-param="101" val-param="B"><em>B</em><p>上海</p></li>
    </ul>
    <input type="hidden" id="answer101" name="answer101" value=""/>
    <input type="hidden" id="answertype101" name="answertype101" value="0"/>
  </div>
  <div class="Py-mian1" data="102">
    <div class="Py-m1-title fs16 fontLabel">2.<span class="quesType">[多选题]</span> 以下哪些是直辖市？</div>
    <ul class="answerList">
      <li id-param="102" val-param="A"><em>A</em><p>北京</p></li>
      <li id-param="102" val-param="B"><em>B</em><p>上海</p></li>
      <li id-param="102" val-param="C"><em>C</em><p>广州</p></li>
    </ul>
    <input type="hidden" id="answer102" name="answer102" value=""/>
    <input type="hidden" id="answertype102" name="answertype102" value="1"/>
  </div>
  <div class="Py-mian1" data="103">
    <div class="Py-m1-title fs16 fontLabel">3.<span class="quesType">[判断题]</span> 地球是圆的。</div>
    <ul class="answerList panduan">
      <li id-param="103" val-param="true"><em>A</em><p>对</p></li>
      <li id-param="103" val-param="false"><em>B</em><p>错</p></li>
    </ul>
    <input type="hidden" id="answer103" name="answer103" value=""/>
    <input type="hidden" id="answertype103" name="answertype103" value="3"/>
  </div>
  <div class="Py-mian1" data="104">
    <div class="Py-m1-title fs16 fontLabel">4.<span class="quesType">[填空题]</span> 软件工程包括（ ）和（ ）两方面。</div>
    <input type="hidden" name="tiankongsize104" value="2">
    <textarea id="answer1041" name="answer1041"></textarea>
    <textarea id="answer1042" name="answer1042"></textarea>
    <input type="hidden" id="answertype104" name="answertype104" value="2"/>
  </div>
</div>
</body></html>
''';

  test('解析作业页的隐藏字段与四类题目', () {
    final HomeworkPaper? paper = parseHomeworkPaper(html, sourceUrl: 'https://example.test/work');
    expect(paper, isNotNull);
    expect(paper!.field('workAnswerId'), '55256455');
    expect(paper.field('enc_work'), '4f0fbbda67ea4db89545251f2ece5e44');
    expect(paper.field('classId'), '117860940');
    expect(paper.workId, '4e2b7b95bb5a4de4bd8010567d0f4e99');
    expect(paper.questions.length, 4);

    final HomeworkQuestion single = paper.questions[0];
    expect(single.id, '101');
    expect(single.type, HomeworkQuestionType.single);
    expect(single.text, '中国的首都是？');
    expect(single.options.length, 2);
    expect(single.options.first.key, 'A');
    expect(single.options.first.text, '北京');

    final HomeworkQuestion judge = paper.questions[2];
    expect(judge.type, HomeworkQuestionType.judge);
    expect(judge.options[0].value, 'true');
    expect(judge.options[1].value, 'false');

    final HomeworkQuestion fill = paper.questions[3];
    expect(fill.type, HomeworkQuestionType.fill);
    expect(fill.blanks, <String>['answer1041', 'answer1042']);
  });

  test('纯图片题保留图片地址，不留下空题干', () {
    const String imageHtml =
        '<div class="Py-mian1" data="201"><div class="Py-m1-title">1.<span class="quesType">[单选题]</span>'
        '<img src="https://p.ananas.chaoxing.com/star3/origin/a.png"/></div>'
        '<ul class="answerList"><li><em>A</em><p>图一</p></li></ul>'
        '<input type="hidden" name="answer201" value=""/>'
        '<input type="hidden" name="answertype201" value="0"/></div>';
    final HomeworkPaper? paper = parseHomeworkPaper(imageHtml, sourceUrl: 'x');
    expect(paper, isNotNull);
    expect(
      paper!.questions.single.text,
      'p.ananas.chaoxing.com/star3/origin/a.png',
    );
  });
}
