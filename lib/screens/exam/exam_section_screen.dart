import 'dart:async';
import 'package:flutter/material.dart';
import '../../core/constants.dart';
import '../../mock/mock_data.dart';
import '../../models/question.dart';
import '../../widgets/question_widgets.dart';
import '../../widgets/timer_badge.dart';
import '../../widgets/listening_audio_player.dart';
import '../../core/api_client.dart';

class ExamSectionScreen extends StatefulWidget {
  final String examSessionId;
  final String skillId; // slug
  final List<Question> questions; // optional; if empty we fetch from the first practice set
  final int sectionDurationMinutes;
  const ExamSectionScreen({super.key, required this.examSessionId, required this.skillId, required this.questions, required this.sectionDurationMinutes});

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
  bool _submitting = false;
  final Map<String, List<String>> _optionIds = {};

  @override
  Widget build(BuildContext context) {
    final skill = skills.firstWhere((s) => s.id == widget.skillId, orElse: () => skills.first);
    if (_loading) {
      return Scaffold(appBar: AppBar(title: Text('Exam • ${widget.skillId}')), body: const Center(child: CircularProgressIndicator()));
    }
    final q = _qs[index];
    final controller = TextEditingController(text: (answers[q.id] ?? '').toString());
    return Scaffold(
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
              Text('Question ${index + 1} of ${_qs.length}', style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 10),
              if (q.passage != null)
                Card(child: Padding(padding: const EdgeInsets.all(14.0), child: Text(q.passage!))),
              if (q.audioUrl != null)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8.0),
                  child: ListeningAudioPlayer(audioPath: q.audioUrl!),
                ),
              const SizedBox(height: 10),
              Text(q.prompt, style: Theme.of(context).textTheme.titleLarge),
              const SizedBox(height: 10),
              Expanded(child: SingleChildScrollView(child: _body(q, controller))),
              Row(
                children: [
                  OutlinedButton(onPressed: index == 0 ? null : () => setState(() => index--), child: const Text('Previous')),
                  const SizedBox(width: 8),
                  if (!submitted)
                    Expanded(
                      child: ElevatedButton(
                        onPressed: () async {
                          if (q.type == QuestionType.mcq) {
                            // stored via onSelected
                          } else {
                            if (controller.text.trim().isEmpty) {
                              ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Please enter your response.')));
                              return;
                            }
                            answers[q.id] = controller.text;
                          }
                          if (_sectionResultId != null) {
                            if (q.type == QuestionType.mcq) {
                              final selIdx = answers[q.id] as int?;
                              final ids = _optionIds[q.id] ?? const [];
                              final optId = (selIdx != null && selIdx < ids.length) ? ids[selIdx] : null;
                              await _api.submitExamAnswer(
                                examSessionId: widget.examSessionId,
                                sectionResultId: _sectionResultId!,
                                questionId: q.id,
                                optionId: optId,
                              );
                            } else {
                              await _api.submitExamAnswer(
                                examSessionId: widget.examSessionId,
                                sectionResultId: _sectionResultId!,
                                questionId: q.id,
                                answerText: controller.text,
                              );
                            }
                          }
                          if (index == _qs.length - 1) {
                            _finish();
                          } else {
                            setState(() => index++);
                          }
                        },
                        child: Text(index == _qs.length - 1 ? 'Submit section' : 'Next'),
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
    }
  }

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    // Determine questions
    List<Question> qs = widget.questions;
    List<dynamic> rawQs = [];
    if (qs.isEmpty) {
      // fetch first practice set for the skill
      final sets = await _api.getPracticeSetsForSkill(widget.skillId);
      if (sets.isNotEmpty) {
        final psId = sets.first['id'] as String;
        rawQs = await _api.getQuestionsForPracticeSet(psId);
        qs = rawQs.map<Question>((q) => Question(
              id: q['id'],
              skillId: widget.skillId,
              practiceSetId: sets.first['id'],
              type: _typeFromStr(q['type']),
              prompt: q['prompt'] ?? '',
              passage: q['passage'],
              audioUrl: q['listening_track'] != null ? q['listening_track']['audio_path'] : null,
              options: q['options'] != null ? List<String>.from((q['options'] as List).map((o) => o['text'])) : null,
              correctAnswerIndex: null,
            )).toList();
        for (final q in rawQs) {
          if (q['options'] != null) {
            _optionIds[q['id']] = List<String>.from((q['options'] as List).map((o) => o['id'] as String));
          }
        }
      }
    }
    _qs = qs;
    // Start section
    _sectionResultId = await _api.startExamSection(examSessionId: widget.examSessionId, skillSlug: widget.skillId, totalQuestions: _qs.length);
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

  void _finish() async {
    if (submitted) return;
    submitted = true;
    await _api.completeExamSection(_sectionResultId!, timeTakenSeconds: widget.sectionDurationMinutes * 60, totalQuestions: _qs.length);
    if (!mounted) return;
    Navigator.pop(context, true);
  }
}
