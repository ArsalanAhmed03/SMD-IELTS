import 'question.dart';
import 'test_result.dart';
import '../../core/constants.dart';

class AnswerSnapshot {
  final String questionId;
  final String? practiceAnswerId;
  final String? optionId;
  final String? optionText;
  final String? answerText;
  final bool? isCorrect;
  final Map<String, dynamic>? writingEval;

  const AnswerSnapshot({
    required this.questionId,
    this.practiceAnswerId,
    this.optionId,
    this.optionText,
    this.answerText,
    this.isCorrect,
    this.writingEval,
  });
}

class PracticeSummaryArgs {
  final TestResult result;
  final String practiceSetId;
  final Map<String, AnswerSnapshot> answers;
  final Map<String, dynamic>? completionData;
  final List<Question> questions;
  final String? title;
  final Map<String, dynamic>? writingEvaluations;

  const PracticeSummaryArgs({
    required this.result,
    required this.practiceSetId,
    required this.answers,
    required this.completionData,
    required this.questions,
    this.title,
    this.writingEvaluations,
  });
}


class ReviewEntry {
  final String prompt;
  final String? userAnswer;
  final String? correctAnswer;
  final bool? isCorrect;
  final Map<String, dynamic>? writingEval;
  final QuestionType? type;

  const ReviewEntry({
    required this.prompt,
    this.userAnswer,
    this.correctAnswer,
    this.isCorrect,
    this.writingEval,
    this.type,
  });
}
