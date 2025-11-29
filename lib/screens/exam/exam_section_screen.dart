import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import '../../core/constants.dart';
import '../../mock/mock_data.dart';
import '../../models/question.dart';
import '../../widgets/question_widgets.dart';
import '../../widgets/timer_badge.dart';
import '../../widgets/listening_audio_player.dart';
import '../../core/api_client.dart';
import '../../widgets/speaking_recorder.dart';
import '../../core/supabase_client.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show FileOptions;

class ExamSectionScreen extends StatefulWidget {
  final String examSessionId;
  final String skillId; // slug
  final List<Question> questions; // optional; if empty we fetch from the first practice set
  final int sectionDurationMinutes;

  const ExamSectionScreen({
    super.key,
    required this.examSessionId,
    required this.skillId,
    required this.questions,
    required this.sectionDurationMinutes,
  });

  @override
  State<ExamSectionScreen> createState() => _ExamSectionScreenState();
}

class _ExamSectionScreenState extends State<ExamSectionScreen> {
  int index = 0;
  final Map<String, dynamic> answers = {};
  bool submitted = false;
  final _api = ApiClient();
  String? _sectionResultId;
  List<Question> _qs = [];
  bool _loading = true;
  bool _submitting = false; // loading while sending answers / finishing
  final Map<String, List<String>> _optionIds = {};
  final Map<String, String> _examAnswerIds = {};
  final Map<String, String> _speakingAttemptIds = {};
  final Map<String, Map<String, dynamic>> _speakingEvals = {};
  final Map<String, bool> _speakingAnswerSaved = {};

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    try {
      // Determine questions
      List<Question> qs = widget.questions;
      List<dynamic> rawQs = [];

      if (qs.isEmpty) {
        // fetch first practice set for the skill
        final sets = await _api.getPracticeSetsForSkill(widget.skillId);
        if (sets.isNotEmpty) {
          final psId = sets.first['id'] as String;
          rawQs = await _api.getQuestionsForPracticeSet(psId);

          qs = rawQs
              .map<Question>(
                (q) => Question(
                  id: q['id'],
                  skillId: widget.skillId,
                  practiceSetId: sets.first['id'],
                  type: _typeFromStr(q['type']),
                  prompt: q['prompt'] ?? '',
                  passage: q['passage'],
                  audioUrl: q['listening_track'] != null
                      ? q['listening_track']['audio_path']
                      : null,
                  options: q['options'] != null
                      ? List<String>.from(
                          (q['options'] as List).map((o) => o['text']),
                        )
                      : null,
                  correctAnswerIndex: null,
                ),
              )
              .toList();

          for (final q in rawQs) {
            if (q['options'] != null) {
              _optionIds[q['id']] = List<String>.from(
                (q['options'] as List).map((o) => o['id'] as String),
              );
            }
          }
        }
      }

      _qs = qs;

      // Start section in backend
      _sectionResultId = await _api.startExamSection(
        examSessionId: widget.examSessionId,
        skillSlug: widget.skillId,
        totalQuestions: _qs.length,
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to start section: $e')),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _loading = false);
      }
    }
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

  void _showLoadingDialog() {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => const Center(child: CircularProgressIndicator()),
    );
  }

  void _hideLoadingDialog() {
    if (Navigator.canPop(context)) {
      Navigator.pop(context);
    }
  }

  Future<void> _finish() async {
    if (submitted || _sectionResultId == null) return;
    submitted = true;
    _showLoadingDialog();
    try {
      await _api.completeExamSection(
        _sectionResultId!,
        timeTakenSeconds: widget.sectionDurationMinutes * 60,
        totalQuestions: _qs.length,
      );
      if (!mounted) return;
      _hideLoadingDialog();
      Navigator.pop(context, true);
    } catch (e) {
      _hideLoadingDialog();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to complete section: $e')),
        );
      }
    }
  }

  // Ask user before leaving the section via back navigation
  Future<bool> _confirmExit() async {
    // If already submitted/finished, just allow pop with no dialog
    if (submitted) return true;

    final shouldLeave = await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text('Leave this section?'),
            content: const Text(
              'If you leave now, your answers in this section may not be fully submitted and your exam attempt could be incomplete.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(ctx).pop(false),
                child: const Text('Stay'),
              ),
              TextButton(
                onPressed: () => Navigator.of(ctx).pop(true),
                child: const Text('Leave'),
              ),
            ],
          ),
        ) ??
        false;

    return shouldLeave;
  }

  Future<void> _handleSpeakingRecorded(Question q, SpeakingRecordingResult rec) async {
    if (_sectionResultId == null) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Section not ready yet.')),
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
        mode: 'exam',
        examSessionId: widget.examSessionId,
        examSectionResultId: _sectionResultId,
      );
      final attemptId = attempt['id'] as String;
      _speakingAttemptIds[q.id] = attemptId;

      final ans = await _api.submitExamAnswer(
        examSessionId: widget.examSessionId,
        sectionResultId: _sectionResultId!,
        questionId: q.id,
        answerText: key,
      );
      _examAnswerIds[q.id] = ans['id'] as String;
      _speakingAnswerSaved[q.id] = true;
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

  @override
  Widget build(BuildContext context) {
    final skill = skills.firstWhere(
      (s) => s.id == widget.skillId,
      orElse: () => skills.first,
    );

    if (_loading) {
      return Scaffold(
        appBar: AppBar(title: Text('Exam • ${widget.skillId}')),
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    final q = _qs[index];
    final controller =
        TextEditingController(text: (answers[q.id] ?? '').toString());

    return WillPopScope(
      onWillPop: _confirmExit,
      child: Scaffold(
        appBar: AppBar(
          title: Text('Exam • ${skill.name}'),
          actions: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8.0),
              child: Center(
                child: TimerBadge(
                  duration: Duration(minutes: widget.sectionDurationMinutes),
                  onFinished: _finish,
                ),
              ),
            ),
          ],
        ),
        body: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Question ${index + 1} of ${_qs.length}',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
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
                    ListeningAudioPlayer(
                      audioPath: q.audioUrl!,
                      bucket: 'listening-audio',     // same as before
                      showSpeedControl: true,        // allow speed change
                      enforcePlayLimit: false,       // no limit in practice
                    ),
                  ],
                const SizedBox(height: 10),
                Text(
                  q.prompt,
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                const SizedBox(height: 10),

                // small visual indicator while submitting answers
                if (_submitting)
                  const Padding(
                    padding: EdgeInsets.only(bottom: 8.0),
                    child: LinearProgressIndicator(),
                  ),

                Expanded(
                  child: SingleChildScrollView(
                    child: _body(q, controller),
                  ),
                ),
                Row(
                  children: [
                    OutlinedButton(
                      onPressed: index == 0 || _submitting
                          ? null
                          : () => setState(() => index--),
                      child: const Text('Previous'),
                    ),
                    const SizedBox(width: 8),
                    if (!submitted)
                      Expanded(
                        child: ElevatedButton(
                          onPressed: _submitting
                              ? null
                              : () async {
                                  // validation
                                  if (q.type == QuestionType.mcq) {
                                    final selIdx = answers[q.id] as int?;
                                    if (selIdx == null) {
                                      ScaffoldMessenger.of(context).showSnackBar(
                                        const SnackBar(
                                          content: Text('Please select an option.'),
                                        ),
                                      );
                                      return;
                                    }
                                  } else if (q.type == QuestionType.speaking) {
                                    if (!(_speakingAnswerSaved[q.id] ?? false)) {
                                      ScaffoldMessenger.of(context).showSnackBar(
                                        const SnackBar(
                                          content: Text('Please record your speaking answer first.'),
                                        ),
                                      );
                                      return;
                                    }
                                  } else {
                                    if (controller.text.trim().isEmpty) {
                                      ScaffoldMessenger.of(context).showSnackBar(
                                        const SnackBar(
                                          content: Text('Please enter your response.'),
                                        ),
                                      );
                                      return;
                                    }
                                    answers[q.id] = controller.text;
                                  }

                                  if (_sectionResultId == null) {
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      const SnackBar(
                                        content: Text('Section not initialized. Please go back and try again.'),
                                      ),
                                    );
                                    return;
                                  }

                                  setState(() => _submitting = true);
                                  try {
                                    if (q.type == QuestionType.mcq) {
                                      final selIdx = answers[q.id] as int?;
                                      final ids = _optionIds[q.id] ?? const <String>[];
                                      final optId = (selIdx != null && selIdx < ids.length) ? ids[selIdx] : null;

                                      await _api.submitExamAnswer(
                                        examSessionId: widget.examSessionId,
                                        sectionResultId: _sectionResultId!,
                                        questionId: q.id,
                                        optionId: optId,
                                      );
                                    } else if (q.type == QuestionType.speaking) {
                                      // already saved via recorder
                                    } else {
                                      final resp = await _api.submitExamAnswer(
                                        examSessionId: widget.examSessionId,
                                        sectionResultId: _sectionResultId!,
                                        questionId: q.id,
                                        answerText: controller.text,
                                      );
                                      final examAnswerId = resp['id'] as String?;
                                      if (q.type == QuestionType.essay && examAnswerId != null) {
                                        _examAnswerIds[q.id] = examAnswerId;
                                        unawaited(_api.createWritingEvalForExam(examAnswerId, targetBand: 7.0));
                                      }
                                    }

                                    if (index == _qs.length - 1) {
                                      // last question -> finish section
                                      await _finish();
                                    } else {
                                      if (mounted) {
                                        setState(() => index++);
                                      }
                                    }
                                  } catch (e) {
                                    if (mounted) {
                                      ScaffoldMessenger.of(context).showSnackBar(
                                        SnackBar(
                                          content: Text('Failed to submit answer: $e'),
                                        ),
                                      );
                                    }
                                  } finally {
                                    if (mounted) {
                                      setState(() => _submitting = false);
                                    }
                                  }
                                },
                          child: Text(
                            index == _qs.length - 1
                                ? 'Submit section'
                                : 'Next',
                          ),
                        ),
                      ),
                  ],
                )
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _body(Question q, TextEditingController controller) {
    switch (q.type) {
      case QuestionType.mcq:
        return McqOptions(
          options: q.options ?? const [],
          selectedIndex: answers[q.id] as int?,
          onSelected: (v) => setState(() => answers[q.id] = v),
        );
      case QuestionType.gapFill:
      case QuestionType.shortText:
        return ShortTextInput(controller: controller);
      case QuestionType.essay:
        return EssayInput(controller: controller);
      case QuestionType.speaking:
        return _speakingBody(q);
    }
  }

  Widget _speakingBody(Question q) {
    final eval = _speakingEvals[q.id];
    final audioPath = answers[q.id] as String?;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SpeakingRecorder(
          prompt: 'Record your speaking response for this question.',
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
        if (eval != null) ...[
          const SizedBox(height: 8),
          _speakingEvalCard(eval),
        ],
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
            const SizedBox(height: 4),
            Text(
              'Fluency ${_fmtBand(fluency)} / Lexical ${_fmtBand(lexical)} / Grammar ${_fmtBand(grammar)} / Pronunciation ${_fmtBand(pron)}',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            if ((eval['feedback_short'] as String?)?.isNotEmpty ?? false) ...[
              const SizedBox(height: 8),
              Text(eval['feedback_short'] as String),
            ],
            if ((eval['feedback_detailed'] as String?)?.isNotEmpty ?? false) ...[
              const SizedBox(height: 8),
              Text(eval['feedback_detailed'] as String),
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
