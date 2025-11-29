import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
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
import '../../widgets/speaking_recorder.dart';
import '../../core/supabase_client.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show FileOptions;

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
  final Map<String, Map<String, dynamic>> _writingEvalsByQuestion = {};
  final Map<String, Map<String, dynamic>> _speakingEvals = {};
  final Map<String, String> _speakingAttemptIds = {};
  final Map<String, bool> _speakingAnswerSaved = {};

  @override
  void initState() {
    super.initState();
    _init();
  }

void _showLoadingDialog() {
  showDialog(
    context: context,
    barrierDismissible: false,
    builder: (_) => const Center(
      child: CircularProgressIndicator(),
    ),
  );
}

void _hideLoadingDialog() {
  if (Navigator.canPop(context)) Navigator.pop(context);
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
      case 'speaking':
        return QuestionType.speaking;
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

  Future<void> _handleSpeakingRecorded(Question q, SpeakingRecordingResult rec) async {
    if (_sessionId == null) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Session not initialized yet.')),
        );
      }
      return;
    }
    final uid = Supa.currentUserId;
    if (uid == null) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Please sign in to save attempts.')),
        );
      }
      return;
    }
    setState(() => _submitting = true);

    try {
      final bytes = await File(rec.path).readAsBytes();
      final ext = rec.path.contains('.') ? rec.path.split('.').last : 'm4a';
      final key = '$uid/${DateTime.now().millisecondsSinceEpoch}.$ext';
      await Supa.client.storage.from('speaking-attempts').uploadBinary(
            key,
            bytes,
            fileOptions: const FileOptions(upsert: true),
          );

      final attempt = await _api.createSpeakingAttempt(
        questionId: q.id,
        audioPath: key,
        durationSeconds: rec.durationSeconds,
        mode: 'practice',
      );
      final attemptId = attempt['id'] as String;
      _speakingAttemptIds[q.id] = attemptId;

      final paResp = await _api.submitPracticeAnswer(
        _sessionId!,
        questionId: q.id,
        answerText: key,
      );
      _speakingAnswerSaved[q.id] = true;
      _answerSnapshots[q.id] = AnswerSnapshot(
        questionId: q.id,
        practiceAnswerId: paResp['id'] as String?,
        answerText: key,
        isCorrect: paResp['is_correct'] as bool?,
      );
      answers[q.id] = key;

      final eval = await _api.createSpeakingEvaluation(attemptId, targetBand: 7.0);
      _speakingEvals[q.id] = eval;
      if (mounted) setState(() {});
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Speaking upload failed: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  Future<void> _triggerWritingEval(Question q, String practiceAnswerId, String answerText) async {
    try {
      final res = await _api.createWritingEvalForPractice(practiceAnswerId, targetBand: 7.0);
      if (!mounted) return;
      setState(() {
        _writingEvalsByQuestion[q.id] = res;
        final prev = _answerSnapshots[q.id];
        _answerSnapshots[q.id] = AnswerSnapshot(
          questionId: q.id,
          practiceAnswerId: practiceAnswerId,
          optionId: prev?.optionId,
          optionText: prev?.optionText,
          answerText: prev?.answerText ?? answerText,
          isCorrect: prev?.isCorrect,
          writingEval: res,
        );
      });
    } catch (e) {
      debugPrint('Writing eval failed: $e');
    }
  }

void _finish() {
  () async {
    _showLoadingDialog();
    try {
      final res = await _api.completePracticeSession(
        _sessionId!,
        timeTakenSeconds: estMin * 60,
      );

      debugPrint('completePracticeSession res: $res');

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

      // Build writing eval map from backend + local map
      final Map<String, dynamic> writingEvals = {};
      for (final w in (res['writing_evaluations'] as List? ?? [])) {
        if (w is Map<String, dynamic>) {
          final qid = w['question_id'] as String?;
          if (qid != null) writingEvals[qid] = w;
        }
      }
      writingEvals.addAll(_writingEvalsByQuestion);

      debugPrint('writingEvals assembled in _finish: $writingEvals');

      if (!mounted) return;
      _hideLoadingDialog();

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
          writingEvaluations: writingEvals,
        ),
      );
    } catch (e) {
      _hideLoadingDialog();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to finish: $e')),
        );
      }
    }
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
                            } else if (q.type == QuestionType.speaking) {
                              if (!(_speakingAnswerSaved[q.id] ?? false)) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(content: Text('Please record your answer first.')),
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

                            if (_sessionId == null) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(content: Text('Session not initialized. Please go back and try again.')),
                              );
                              return;
                            }

                            _showLoadingDialog();
                            setState(() => _submitting = true);

                            try {
                              // SUBMIT MCQ
                              if (q.type == QuestionType.mcq) {
                                final selIdx = answers[q.id] as int;
                                final ids = _optionIds[q.id] ?? const [];
                                final optId = (selIdx < ids.length) ? ids[selIdx] : null;
                                final optText =
                                    (q.options != null && selIdx < q.options!.length)
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
                                      writingEval: resp['writing_eval'] as Map<String, dynamic>?,
                                    );
                              } else if (q.type == QuestionType.speaking) {
                                // speaking answer already stored via recorder upload
                              }

                              // SUBMIT TEXT/ESSAY
                              else {
                                final resp = await _api.submitPracticeAnswer(
                                  _sessionId!,
                                  questionId: q.id,
                                  answerText: controller.text.trim(),
                                );
                                debugPrint('submitPracticeAnswer resp for ${q.id}: $resp');

                                final practiceAnswerId = resp['id'] as String?;
                                _answerSnapshots[q.id] = AnswerSnapshot(
                                  questionId: q.id,
                                  practiceAnswerId: practiceAnswerId,
                                  answerText: controller.text.trim(),
                                  isCorrect: resp['is_correct'] as bool?,
                                  writingEval: resp['writing_eval'] as Map<String, dynamic>?,

                                );

                                if (q.type == QuestionType.essay && practiceAnswerId != null) {
                                  await _triggerWritingEval(q, practiceAnswerId, controller.text.trim());
                                }
                              }

                              _hideLoadingDialog();

                              // MOVE NEXT
                              if (index == qs.length - 1) {
                                _finish();
                              } else {
                                setState(() => index++);
                              }

                            } catch (e) {
                              _hideLoadingDialog();
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
      case QuestionType.speaking:
        return _buildSpeakingBody(q);
    }
  }

  Widget _buildSpeakingBody(Question q) {
    final eval = _speakingEvals[q.id];
    final audioPath = answers[q.id] as String?;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SpeakingRecorder(
          prompt: 'Tap record to answer aloud.',
          onRecorded: (rec) => _handleSpeakingRecorded(q, rec),
        ),
        if (audioPath != null) ...[
          const SizedBox(height: 8),
          ListeningAudioPlayer(
            audioPath: audioPath,
            bucket: 'speaking-attempts',
            showSpeedControl: true,
          ),
        ],
        if (_speakingAttemptIds[q.id] != null)
          Padding(
            padding: const EdgeInsets.only(top: 8.0),
            child: Text(
              'Attempt saved. You can re-record to replace it.',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ),
        const SizedBox(height: 8),
        if (eval != null) _speakingEvalCard(eval),
      ],
    );
  }

  Widget _speakingEvalCard(Map<String, dynamic> eval) {
    final overall = eval['overall_band'];
    final fluency = eval['fluency_and_coherence'];
    final lexical = eval['lexical_resource'];
    final grammar = eval['grammatical_range_and_accuracy'];
    final pron = eval['pronunciation'];
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('AI Speaking band: ${_fmtBand(overall)}', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 6),
            Text('Fluency ${_fmtBand(fluency)} / Lexical ${_fmtBand(lexical)} / Grammar ${_fmtBand(grammar)} / Pronunciation ${_fmtBand(pron)}'),
            if ((eval['feedback_short'] as String?)?.isNotEmpty ?? false) ...[
              const SizedBox(height: 8),
              Text(eval['feedback_short'] as String),
            ],
            if ((eval['feedback_detailed'] as String?)?.isNotEmpty ?? false) ...[
              const SizedBox(height: 8),
              Text(
                eval['feedback_detailed'] as String,
                style: const TextStyle(color: Colors.black87),
              ),
            ],
            if ((eval['transcript'] as String?)?.isNotEmpty ?? false) ...[
              const SizedBox(height: 8),
              Text('Transcript: ${eval['transcript']}'),
            ],
          ],
        ),
      ),
    );
  }

  String _fmtBand(dynamic v) {
    if (v == null) return '-';
    if (v is num) return v.toStringAsFixed(1);
    return v.toString();
  }
}
