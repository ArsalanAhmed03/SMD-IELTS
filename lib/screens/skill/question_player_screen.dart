import 'dart:async';
import 'package:flutter/material.dart';
import '../../core/app_state.dart';
import '../../core/constants.dart';
import '../../models/question.dart';
import '../../widgets/question_widgets.dart';
import '../../widgets/timer_badge.dart';
import '../../models/test_result.dart';
import '../../core/api_client.dart';
import '../../widgets/listening_audio_player.dart';
import '../../models/practice_review_models.dart';

class QuestionPlayerScreen extends StatefulWidget {
  final String practiceSetId;
  const QuestionPlayerScreen({super.key, required this.practiceSetId});

  @override
  State<QuestionPlayerScreen> createState() => _QuestionPlayerScreenState();
}

class _QuestionPlayerScreenState extends State<QuestionPlayerScreen> {
  late final List<Question> qs;
  int index = 0;
  final Map<String, dynamic> answers = {};
  late final int estMin;
  final _api = ApiClient();
  String? _sessionId;
  bool _submitting = false;
  bool _loading = true;
  final Map<String, List<String>> _optionIds = {};
  final Map<String, AnswerSnapshot> _answerSnapshots = {};

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    // Fetch set details and questions, create practice session
    final detail = await _api.getPracticeSet(widget.practiceSetId);
    final qjson = await _api.getQuestionsForPracticeSet(widget.practiceSetId);
    estMin = (detail['practice_set']['estimated_minutes'] as int?) ?? 10;
    qs = qjson.map<Question>((q) => Question(
          id: q['id'],
          skillId: detail['skill']['slug'],
          practiceSetId: widget.practiceSetId,
          type: _typeFromStr(q['type']),
          prompt: q['prompt'] ?? '',
          passage: q['passage'],
          audioUrl: q['listening_track'] != null ? q['listening_track']['audio_path'] : null,
          options: q['options'] != null ? List<String>.from((q['options'] as List).map((o) => o['text'])) : null,
          correctAnswerIndex: null,
        )).toList();
    for (final q in qjson) {
      if (q['options'] != null) {
        _optionIds[q['id']] = List<String>.from((q['options'] as List).map((o) => o['id'] as String));
      }
    }
    final sess = await _api.createPracticeSession(widget.practiceSetId);
    _sessionId = sess['id'] as String;
    setState(() => _loading = false);
  }

  QuestionType _typeFromStr(String s) {
    switch (s) {
      case 'mcq':
        return QuestionType.mcq;
      case 'gap_fill':
      case 'short_text':
        return QuestionType.shortText;
      case 'essay':
        return QuestionType.essay;
      default:
        return QuestionType.mcq;
    }
  }

  void _next() {
    if (index < qs.length - 1) setState(() => index++);
  }

  void _prev() {
    if (index > 0) setState(() => index--);
  }

  void _finish() {
    () async {
      final res = await _api.completePracticeSession(_sessionId!, timeTakenSeconds: estMin * 60);
      final app = AppStateScope.of(context);
      final stats = (res['stats'] ?? const {}) as Map<String, dynamic>;
      final practice = res['practice_set'] as Map<String, dynamic>;
      final testResult = TestResult(
        id: _sessionId!,
        skillId: practice['skill_slug'],
        practiceSetId: practice['id'],
        totalQuestions: stats['total_questions'] ?? qs.length,
        correctQuestions: stats['correct_questions'] ?? 0,
        timeTakenSeconds: stats['time_taken_seconds'] ?? (estMin * 60),
        date: DateTime.now(),
      );
      app.addResult(testResult);
      if (!mounted) return;
      Navigator.pushReplacementNamed(
        context,
        '/practiceSummary',
        arguments: PracticeSummaryArgs(
          result: testResult,
          practiceSetId: practice['id'],
          answers: _answerSnapshots,
          completionData: res,
          questions: qs,
          title: practice['title'],
        ),
      );
    }();
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    final q = qs[index];
    final controller = TextEditingController(text: (answers[q.id] ?? '').toString());

    return Scaffold(
      appBar: AppBar(
        title: const Text('Practice'),
        actions: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8.0),
            child: Center(child: TimerBadge(duration: Duration(minutes: estMin))),
          )
        ],
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Question ${index + 1} of ${qs.length}', style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 10),
              if (q.passage != null)
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(14.0),
                    child: Text(q.passage!),
                  ),
                ),
              if (q.audioUrl != null) ...[
                const SizedBox(height: 8),
                ListeningAudioPlayer(audioPath: q.audioUrl!),
              ],
              const SizedBox(height: 12),
              Text(q.prompt, style: Theme.of(context).textTheme.titleLarge),
              const SizedBox(height: 12),
              Expanded(
                child: SingleChildScrollView(
                  child: _buildQuestionBody(q, controller),
                ),
              ),
              Row(
                children: [
                OutlinedButton(
                  onPressed: index == 0 ? null : _prev,
                  child: const Text('Previous'),
                ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: ElevatedButton(
                      onPressed: _submitting
                          ? null
                          : () async {
                              // 1) Validation
                              if (q.type == QuestionType.mcq) {
                                final selIdx = answers[q.id] as int?;
                                if (selIdx == null) {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    const SnackBar(content: Text('Please select an option before continuing.')),
                                  );
                                  return;
                                }
                              } else {
                                if (controller.text.trim().isEmpty) {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    const SnackBar(content: Text('Please enter your response.')),
                                  );
                                  return;
                                }
                                answers[q.id] = controller.text.trim();
                              }

                              // 2) Submit to backend
                              if (_sessionId == null) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(content: Text('Session not initialized. Please go back and try again.')),
                                );
                                return;
                              }

                              setState(() => _submitting = true);
                              try {
                                if (q.type == QuestionType.mcq) {
                                  final selIdx = answers[q.id] as int;
                                  final ids = _optionIds[q.id] ?? const [];
                                  final optId = (selIdx < ids.length) ? ids[selIdx] : null;
                                  final optText = (q.options != null && selIdx < q.options!.length)
                                      ? q.options![selIdx]
                                      : null;

                                  final resp = await _api.submitPracticeAnswer(
                                    _sessionId!,
                                    questionId: q.id,
                                    optionId: optId,
                                  );

                                  _answerSnapshots[q.id] = AnswerSnapshot(
                                    questionId: q.id,
                                    optionId: optId,
                                    optionText: optText,
                                    isCorrect: resp['is_correct'] as bool?,
                                  );
                                } else {
                                  final resp = await _api.submitPracticeAnswer(
                                    _sessionId!,
                                    questionId: q.id,
                                    answerText: controller.text.trim(),
                                  );

                                  _answerSnapshots[q.id] = AnswerSnapshot(
                                    questionId: q.id,
                                    answerText: controller.text.trim(),
                                    isCorrect: resp['is_correct'] as bool?,
                                  );
                                }

                                // 3) Move to next or finish
                                if (index == qs.length - 1) {
                                  _finish();
                                } else {
                                  _next();
                                }
                              } catch (e) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(content: Text('Failed to submit answer: $e')),
                                );
                              } finally {
                                if (mounted) {
                                  setState(() => _submitting = false);
                                }
                              }
                            },
                      child: Text(index == qs.length - 1 ? 'Finish' : 'Next'),
                    ),
                  ),
                ],
              )
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildQuestionBody(Question q, TextEditingController controller) {
    switch (q.type) {
      case QuestionType.mcq:
        final selected = answers[q.id] as int?;
        return McqOptions(
          options: q.options ?? const [],
          selectedIndex: selected,
          onSelected: (v) => setState(() => answers[q.id] = v),
        );
      case QuestionType.gapFill:
      case QuestionType.shortText:
        return ShortTextInput(controller: controller);
      case QuestionType.essay:
        return EssayInput(controller: controller);
    }
  }
}
