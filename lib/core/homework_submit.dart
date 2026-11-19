// 作业提交表单的纯规则。
//
// 字段集合来自平台作答页与公开移动端实现；这里不碰网络，方便单测覆盖
// 「哪个题型写哪个字段」这类最容易出错的细节。
import 'models.dart';

class HomeworkSubmitForm {
  const HomeworkSubmitForm({
    required this.path,
    required this.query,
    required this.fields,
  });

  final String path;
  final Map<String, String> query;
  final Map<String, String> fields;
}

Result<HomeworkSubmitForm> buildHomeworkSubmitForm({
  required Course course,
  required HomeworkPaper paper,
  required Map<String, String> answers,
  required String userId,
  bool submit = true,
}) {
  final String workAnswerId = paper.field('workAnswerId');
  final String encWork = paper.field('enc_work');
  if (workAnswerId.isEmpty || encWork.isEmpty) {
    return const Err<HomeworkSubmitForm>('parse', '作业页缺少提交票据，请重新打开作业页再试');
  }

  final String courseId =
      paper.field('courseId').isEmpty ? course.courseId : paper.field('courseId');
  final String classId =
      paper.field('classId').isEmpty ? course.classId : paper.field('classId');
  final String cpi = paper.field('cpi').isEmpty ? course.cpi : paper.field('cpi');
  final String answerId =
      paper.field('answerId').isEmpty ? workAnswerId : paper.field('answerId');

  final Map<String, String> fields = <String, String>{
    'pyFlag': submit ? '' : '1',
    'courseId': courseId,
    'classId': classId,
    'api': paper.field('api'),
    'workAnswerId': workAnswerId,
    'answerId': answerId,
    'totalQuestionNum': paper.field('totalQuestionNum'),
    'fullScore': paper.field('fullScore'),
    'knowledgeid': paper.field('knowledgeid'),
    'oldSchoolId': paper.field('oldSchoolId'),
    'oldWorkId': paper.field('oldWorkId'),
    'jobid': paper.field('jobid'),
    'workRelationId': paper.field('workRelationId'),
    'enc': '',
    'enc_work': encWork,
    'userId': paper.field('userId').isEmpty ? userId : paper.field('userId'),
    'cpi': cpi,
    'workTimesEnc': paper.field('workTimesEnc'),
    'randomOptions': paper.field('randomOptions').isEmpty ? 'false' : paper.field('randomOptions'),
    'isAccessibleCustomFid': '0',
  };

  final StringBuffer qids = StringBuffer();
  for (final HomeworkQuestion q in paper.questions) {
    if (q.id.isNotEmpty) qids.write('${q.id},');
    final String answer = (answers[q.id] ?? '').trim();
    if (answer.isEmpty) continue;
    if (q.type == HomeworkQuestionType.fill) {
      final List<String> parts = answer.split('#!#');
      if (parts.length != q.blanks.length || q.blanks.isEmpty) continue;
      for (int i = 0; i < q.blanks.length; i++) {
        fields[q.blanks[i]] = parts[i].trim();
      }
      fields['tiankongsize${q.id}'] = '${q.blanks.length}';
    } else {
      fields['answer${q.id}'] = answer;
    }
    fields['answertype${q.id}'] = '${q.type.code}';
  }
  fields['answerwqbid'] = qids.toString();

  return Ok<HomeworkSubmitForm>(
    HomeworkSubmitForm(
      path: 'https://mooc1.chaoxing.com/mooc-ans/work/addStudentWorkNew',
      query: <String, String>{
        '_classId': classId,
        'courseid': courseId,
        'token': encWork,
        'totalQuestionNum': paper.field('totalQuestionNum'),
        'ua': 'pc',
        'formType': 'post',
        'saveStatus': '1',
        'version': '1',
        'tempsave': '1',
      },
      fields: fields,
    ),
  );
}
