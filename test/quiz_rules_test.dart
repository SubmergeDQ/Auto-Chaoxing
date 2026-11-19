import 'package:auto_chaoxing/core/models.dart';
import 'package:auto_chaoxing/core/quiz_rules.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const HomeworkQuestion single = HomeworkQuestion(
    id: '1',
    type: HomeworkQuestionType.single,
    text: 't',
    options: <HomeworkOption>[
      HomeworkOption(key: 'A', text: '北京'),
      HomeworkOption(key: 'B', text: '上海'),
    ],
  );
  const HomeworkQuestion multiple = HomeworkQuestion(
    id: '2',
    type: HomeworkQuestionType.multiple,
    text: 't',
    options: <HomeworkOption>[
      HomeworkOption(key: 'A', text: '北京'),
      HomeworkOption(key: 'B', text: '上海'),
      HomeworkOption(key: 'C', text: '广州'),
    ],
  );
  const HomeworkQuestion judge = HomeworkQuestion(
    id: '3',
    type: HomeworkQuestionType.judge,
    text: 't',
    options: <HomeworkOption>[
      HomeworkOption(key: 'A', text: '对', value: 'true'),
      HomeworkOption(key: 'B', text: '错', value: 'false'),
    ],
  );
  const HomeworkQuestion fill = HomeworkQuestion(
    id: '4',
    type: HomeworkQuestionType.fill,
    text: 't',
    blanks: <String>['answer41', 'answer42'],
  );

  test('选择题支持选项字母与选项正文', () {
    expect(matchAnswer(single, 'A')!.value, 'A');
    expect(matchAnswer(single, '北京')!.value, 'A');
    expect(matchAnswer(multiple, 'AB')!.value, 'AB');
    expect(matchAnswer(multiple, 'A#!#B')!.value, 'AB');
    expect(matchAnswer(multiple, '北京#!#上海')!.value, 'AB');
    expect(matchAnswer(multiple, '北京、上海')!.value, 'AB');
  });

  test('判断题的多种写法归一为 true/false', () {
    expect(matchAnswer(judge, '正确')!.value, 'true');
    expect(matchAnswer(judge, '对')!.value, 'true');
    expect(matchAnswer(judge, '√')!.value, 'true');
    expect(matchAnswer(judge, '错误')!.value, 'false');
    expect(matchAnswer(judge, '×')!.value, 'false');
    expect(matchAnswer(judge, 'false')!.value, 'false');
  });

  test('填空题按空位拆分，数量不符时不猜答案', () {
    expect(matchAnswer(fill, '甲#!#乙')!.value, '甲#!#乙');
    expect(matchAnswer(fill, '只有一个'), isNull);
  });

  test('匹配不到时不返回答案', () {
    expect(matchAnswer(single, '广州'), isNull);
    expect(matchAnswer(judge, '不知道'), isNull);
  });
}
