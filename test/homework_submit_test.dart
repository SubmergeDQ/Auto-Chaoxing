import 'package:auto_chaoxing/core/homework_submit.dart';
import 'package:auto_chaoxing/core/models.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const Course course = Course(
    courseId: 'c1',
    classId: 'cl1',
    cpi: 'p1',
    name: '测试课程',
  );

  const HomeworkPaper paper = HomeworkPaper(
    sourceUrl: 'https://mooc1.chaoxing.com/mooc-ans/work/doHomeWorkNew?x=1',
    fields: <String, String>{
      'workAnswerId': '99',
      'answerId': '98',
      'enc_work': 'enc',
      'totalQuestionNum': 'hash',
      'fullScore': '100.0',
      'classId': 'cl1',
      'courseId': 'c1',
      'cpi': 'p1',
      'userId': 'u1',
      'oldWorkId': 'lib1',
    },
    questions: <HomeworkQuestion>[
      HomeworkQuestion(
        id: '1',
        type: HomeworkQuestionType.single,
        text: '单选',
        options: <HomeworkOption>[
          HomeworkOption(key: 'A', text: '甲'),
          HomeworkOption(key: 'B', text: '乙'),
        ],
      ),
      HomeworkQuestion(
        id: '2',
        type: HomeworkQuestionType.multiple,
        text: '多选',
        options: <HomeworkOption>[
          HomeworkOption(key: 'A', text: '甲'),
          HomeworkOption(key: 'B', text: '乙'),
        ],
      ),
      HomeworkQuestion(
        id: '3',
        type: HomeworkQuestionType.judge,
        text: '判断',
        options: <HomeworkOption>[
          HomeworkOption(key: 'A', text: '对', value: 'true'),
          HomeworkOption(key: 'B', text: '错', value: 'false'),
        ],
      ),
      HomeworkQuestion(
        id: '4',
        type: HomeworkQuestionType.fill,
        text: '填空',
        blanks: <String>['answer41', 'answer42'],
      ),
    ],
  );

  test('按题型生成提交字段', () {
    final Result<HomeworkSubmitForm> built = buildHomeworkSubmitForm(
      course: course,
      paper: paper,
      answers: <String, String>{
        '1': 'A',
        '2': 'AB',
        '3': 'true',
        '4': '甲#!#乙',
      },
      userId: 'u1',
    );
    expect(built, isA<Ok<HomeworkSubmitForm>>());
    final HomeworkSubmitForm form = (built as Ok<HomeworkSubmitForm>).value;

    expect(form.fields['pyFlag'], '');
    expect(form.fields['answer1'], 'A');
    expect(form.fields['answertype1'], '0');
    expect(form.fields['answer2'], 'AB');
    expect(form.fields['answertype2'], '1');
    expect(form.fields['answer3'], 'true');
    expect(form.fields['answertype3'], '3');
    expect(form.fields['answer41'], '甲');
    expect(form.fields['answer42'], '乙');
    expect(form.fields['tiankongsize4'], '2');
    expect(form.fields['answertype4'], '2');
    expect(form.fields['answerwqbid'], '1,2,3,4,');
    expect(form.query['token'], 'enc');
    expect(form.query['totalQuestionNum'], 'hash');
    expect(form.query['courseid'], 'c1');
  });

  test('缺少提交票据时拒绝提交', () {
    const HomeworkPaper broken = HomeworkPaper(
      sourceUrl: 'x',
      fields: <String, String>{'workAnswerId': '99'},
      questions: <HomeworkQuestion>[],
    );
    final Result<HomeworkSubmitForm> built = buildHomeworkSubmitForm(
      course: course,
      paper: broken,
      answers: const <String, String>{},
      userId: 'u1',
    );
    expect(built, isA<Err<HomeworkSubmitForm>>());
    expect((built as Err<HomeworkSubmitForm>).code, 'parse');
  });
}
