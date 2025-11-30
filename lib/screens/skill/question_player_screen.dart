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
  DateTime? _startedAt;
  bool _isReading = false;
  bool _isListening = false;
  List<_ReadingGroup> _readingGroups = [];
  List<_ListeningGroup> _listeningGroups = [];
  int _groupIndex = 0;
  final Map<String, TextEditingController> _controllers = {};

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
    _startedAt = DateTime.now();
    _isReading = detail['skill']['slug'] == 'reading';
    _isListening = detail['skill']['slug'] == 'listening';
    if (_isReading) {
      _readingGroups = _buildReadingGroups(qs);
      _listeningGroups = [];
    } else if (_isListening) {
      _listeningGroups = _buildListeningGroups(qs);
      _readingGroups = [];
    }
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
  void _prevGroup() {
    if (_groupIndex > 0) setState(() => _groupIndex--);
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
    _showLoadingDialog();
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
      _hideLoadingDialog();
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
      final timeTaken = _startedAt == null
          ? estMin * 60
          : DateTime.now().difference(_startedAt!).inSeconds;
      final res = await _api.completePracticeSession(
        _sessionId!,
        timeTakenSeconds: timeTaken,
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
        timeTakenSeconds: stats['time_taken_seconds'] ?? timeTaken,
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
          speakingEvaluations: _speakingEvals,
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
    if (_isReading) {
      return _buildReadingScaffold(context);
    }
    if (_isListening) {
      return _buildListeningScaffold(context);
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
                            await _submitSingleQuestion(q, controller);
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

  Future<void> _submitSingleQuestion(Question q, TextEditingController controller, {bool advance = true, bool showLoader = true}) async {
    // Validation
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

    if (showLoader) {
      _showLoadingDialog();
      setState(() => _submitting = true);
    }

    try {
      if (q.type == QuestionType.mcq) {
        final selIdx = answers[q.id] as int;
        final ids = _optionIds[q.id] ?? const [];
        final optId = (selIdx < ids.length) ? ids[selIdx] : null;
        final optText = (q.options != null && selIdx < q.options!.length) ? q.options![selIdx] : null;

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
        // already handled
      } else {
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

      if (showLoader) _hideLoadingDialog();

      if (advance) {
        if (index == qs.length - 1) {
          _finish();
        } else {
          setState(() => index++);
        }
      }
    } catch (e) {
      if (showLoader) _hideLoadingDialog();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to submit answer: $e')),
      );
    } finally {
      if (mounted && showLoader) {
        setState(() => _submitting = false);
      }
    }
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
        Text(
          'Feedback will appear on the summary screen.',
          style: Theme.of(context).textTheme.labelSmall,
        ),
      ],
    );
  }

  // ---------- Listening flow (grouped by audio track) ----------
  Widget _buildListeningScaffold(BuildContext context) {
    if (_listeningGroups.isEmpty) {
      return const Scaffold(body: Center(child: Text('No questions available.')));
    }
    final group = _listeningGroups[_groupIndex];
    final isLastGroup = _groupIndex == _listeningGroups.length - 1;
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
              Text('Audio ${_groupIndex + 1} of ${_listeningGroups.length}', style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 10),
              if (group.audioPath != null) ...[
                ListeningAudioPlayer(audioPath: group.audioPath!, enforcePlayLimit: true),
                const SizedBox(height: 12),
              ],
              Expanded(
                child: SingleChildScrollView(
                  child: Column(
                    children: [
                      for (var i = 0; i < group.questions.length; i++) ...[
                        Align(
                          alignment: Alignment.centerLeft,
                          child: Text(
                            'Question ${group.startIndex + i + 1} of ${qs.length}',
                            style: Theme.of(context).textTheme.labelSmall,
                          ),
                        ),
                        const SizedBox(height: 6),
                        Text(group.questions[i].prompt, style: Theme.of(context).textTheme.titleLarge),
                        const SizedBox(height: 10),
                        _buildQuestionBody(group.questions[i], _controllerFor(group.questions[i].id)),
                        const SizedBox(height: 16),
                      ],
                    ],
                  ),
                ),
              ),
              Row(
                children: [
                  OutlinedButton(
                    onPressed: _groupIndex == 0 || _submitting ? null : _prevGroup,
                    child: const Text('Previous'),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: ElevatedButton(
                      onPressed: _submitting ? null : () => _submitListeningGroup(group, isLastGroup),
                      child: Text(isLastGroup ? 'Finish' : 'Next'),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _submitListeningGroup(_ListeningGroup group, bool isLast) async {
    // Validate all questions answered
    for (final q in group.questions) {
      if (q.type == QuestionType.mcq) {
        if (answers[q.id] == null) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Please answer all questions for this audio.')),
          );
          return;
        }
      } else if (q.type == QuestionType.speaking) {
        if (!(_speakingAnswerSaved[q.id] ?? false)) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Please record all speaking responses.')),
          );
          return;
        }
      } else {
        final ctrl = _controllerFor(q.id);
        if (ctrl.text.trim().isEmpty) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Please answer all questions for this audio.')),
          );
          return;
        }
        answers[q.id] = ctrl.text.trim();
      }
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
      for (final q in group.questions) {
        final ctrl = _controllerFor(q.id);
        await _submitSingleQuestion(q, ctrl, advance: false, showLoader: false);
      }
      _hideLoadingDialog();
      if (isLast) {
        _finish();
      } else {
        setState(() => _groupIndex++);
      }
    } catch (e) {
      _hideLoadingDialog();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to submit answers: $e')),
      );
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  String _fmtBand(dynamic v) {
    if (v == null) return '-';
    if (v is num) return v.toStringAsFixed(1);
    return v.toString();
  }

  // -------- Reading grouped UI --------

  Widget _buildReadingScaffold(BuildContext context) {
    if (_readingGroups.isEmpty) {
      return const Scaffold(body: Center(child: Text('No questions available.')));
    }
    final group = _readingGroups[_groupIndex];
    final isLastGroup = _groupIndex == _readingGroups.length - 1;
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
              Text('Passage ${_groupIndex + 1} of ${_readingGroups.length}', style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 10),
              if (group.passage != null)
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(14.0),
                    child: Text(group.passage!),
                  ),
                ),
              const SizedBox(height: 12),
              Expanded(
                child: SingleChildScrollView(
                  child: Column(
                    children: [
                      for (var i = 0; i < group.questions.length; i++) ...[
                        Align(
                          alignment: Alignment.centerLeft,
                          child: Text(
                            'Question ${group.startIndex + i + 1} of ${qs.length}',
                            style: Theme.of(context).textTheme.titleSmall,
                          ),
                        ),
                        const SizedBox(height: 6),
                        Text(group.questions[i].prompt, style: Theme.of(context).textTheme.titleLarge),
                        const SizedBox(height: 10),
                        _buildQuestionBody(group.questions[i], _controllerFor(group.questions[i].id)),
                        const SizedBox(height: 16),
                      ],
                    ],
                  ),
                ),
              ),
              Row(
                children: [
                  OutlinedButton(
                    onPressed: _groupIndex == 0 || _submitting ? null : _prevGroup,
                    child: const Text('Previous'),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: ElevatedButton(
                      onPressed: _submitting ? null : () => _submitReadingGroup(group, isLastGroup),
                      child: Text(isLastGroup ? 'Finish' : 'Next'),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  TextEditingController _controllerFor(String qid) {
    return _controllers.putIfAbsent(qid, () {
      final initial = (answers[qid] ?? '').toString();
      return TextEditingController(text: initial == 'null' ? '' : initial);
    });
  }

  List<_ReadingGroup> _buildReadingGroups(List<Question> questions) {
    final List<_ReadingGroup> groups = [];
    final Map<String, List<Question>> byPassage = {};
    final List<String> orderedKeys = [];
    for (final q in questions) {
      final key = q.passage ?? '__no_passage_${q.id}';
      if (!byPassage.containsKey(key)) {
        orderedKeys.add(key);
        byPassage[key] = [];
      }
      byPassage[key]!.add(q);
    }
    var runningIndex = 0;
    for (final key in orderedKeys) {
      final list = byPassage[key]!;
      groups.add(_ReadingGroup(
        passage: key.startsWith('__no_passage_') ? null : list.first.passage,
        questions: list,
        startIndex: runningIndex,
      ));
      runningIndex += list.length;
    }
    return groups;
  }

  List<_ListeningGroup> _buildListeningGroups(List<Question> questions) {
    final Map<String, List<Question>> byAudio = {};
    final List<String> orderedKeys = [];
    for (final q in questions) {
      final key = q.audioUrl ?? '__no_audio_${q.id}';
      if (!byAudio.containsKey(key)) {
        orderedKeys.add(key);
        byAudio[key] = [];
      }
      byAudio[key]!.add(q);
    }
    var runningIndex = 0;
    final List<_ListeningGroup> groups = [];
    for (final key in orderedKeys) {
      final list = byAudio[key]!;
      groups.add(_ListeningGroup(
        audioPath: key.startsWith('__no_audio_') ? null : key,
        questions: list,
        startIndex: runningIndex,
      ));
      runningIndex += list.length;
    }
    return groups;
  }

  Future<void> _submitReadingGroup(_ReadingGroup group, bool isLast) async {
    // Validate all questions in the group
    for (final q in group.questions) {
      if (q.type == QuestionType.mcq) {
        if (answers[q.id] == null) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Please answer all questions in this passage before continuing.')),
          );
          return;
        }
      } else if (q.type == QuestionType.speaking) {
        if (!(_speakingAnswerSaved[q.id] ?? false)) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Please record all speaking responses before continuing.')),
          );
          return;
        }
      } else {
        final ctrl = _controllerFor(q.id);
        if (ctrl.text.trim().isEmpty) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Please answer all questions in this passage before continuing.')),
          );
          return;
        }
        answers[q.id] = ctrl.text.trim();
      }
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
      for (final q in group.questions) {
        final ctrl = _controllerFor(q.id);
        await _submitSingleQuestion(q, ctrl, advance: false, showLoader: false);
      }
      _hideLoadingDialog();
      if (isLast) {
        _finish();
      } else {
        setState(() => _groupIndex++);
      }
    } catch (e) {
      _hideLoadingDialog();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to submit answers: $e')),
      );
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }
}

class _ReadingGroup {
  final String? passage;
  final List<Question> questions;
  final int startIndex;
  _ReadingGroup({required this.passage, required this.questions, required this.startIndex});
}

class _ListeningGroup {
  final String? audioPath;
  final List<Question> questions;
  final int startIndex;
  _ListeningGroup({required this.audioPath, required this.questions, required this.startIndex});
}
