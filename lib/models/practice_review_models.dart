import 'question.dart';
import 'test_result.dart';

class AnswerSnapshot {
  final String questionId;
  final String? optionId;
  final String? optionText;
  final String? answerText;
  final bool? isCorrect;

  const AnswerSnapshot({
    required this.questionId,
    this.optionId,
    this.optionText,
    this.answerText,
    this.isCorrect,
  });
}

class PracticeSummaryArgs {
  final TestResult result;
  final String practiceSetId;
  final Map<String, AnswerSnapshot> answers;
  final Map<String, dynamic>? completionData;
  final List<Question> questions;
  final String? title;

  const PracticeSummaryArgs({
    required this.result,
    required this.practiceSetId,
    required this.answers,
    required this.completionData,
    required this.questions,
    this.title,
  });
}

class ReviewEntry {
  final String prompt;
  final String? userAnswer;
  final String? correctAnswer;
  final bool? isCorrect;

  const ReviewEntry({
    required this.prompt,
    this.userAnswer,
    this.correctAnswer,
    this.isCorrect,
  });
}
