import 'package:flutter/material.dart';
import '../../core/constants.dart';
import '../../models/practice_review_models.dart';

enum _ReviewFilter { all, correct, incorrect }

class PracticeReviewScreen extends StatefulWidget {
  final PracticeSummaryArgs? summaryArgs;
  final List<ReviewEntry>? entries;
  final String? title;

  const PracticeReviewScreen({
    super.key,
    this.summaryArgs,
    this.entries,
    this.title,
  }) : assert(summaryArgs != null || entries != null);

  @override
  State<PracticeReviewScreen> createState() => _PracticeReviewScreenState();
}

class _ReviewItem {
  final String prompt;
  final String? userAnswer;
  final bool? isCorrect;
  final String? correctAnswer;
  final Map<String, dynamic>? writingEval;
  final QuestionType? type;

  _ReviewItem({
    required this.prompt,
    this.userAnswer,
    this.isCorrect,
    this.correctAnswer,
    this.writingEval,
    this.type,
  });
}

class _PracticeReviewScreenState extends State<PracticeReviewScreen> {
  late final List<_ReviewItem> _items;
  _ReviewFilter _filter = _ReviewFilter.all;

  @override
  void initState() {
    super.initState();
    _items = _buildItems();
  }

  String? _asStr(dynamic v) => v == null ? null : v is String ? v : v.toString();

  String? _firstNonEmpty(Map<String, dynamic>? m, List<String> keys) {
    if (m == null) return null;
    for (final k in keys) {
      if (m.containsKey(k)) {
        final val = _asStr(m[k]);
        if (val != null && val.trim().isNotEmpty) return val.trim();
      }
    }
    return null;
  }

  List<_ReviewItem> _buildItems() {
    // Case 1: direct entries provided
    if (widget.entries != null) {
      return widget.entries!
          .map((e) => _ReviewItem(
                prompt: e.prompt,
                userAnswer: e.userAnswer,
                isCorrect: e.isCorrect,
                correctAnswer: e.correctAnswer,
                writingEval: e.writingEval,
                type: e.type,
              ))
          .toList();
    }

    // Case 2: Build from summary args
    final args = widget.summaryArgs!;
    final snapshots = args.answers; // Map<String, AnswerSnapshot>
    final writingEvals = args.writingEvaluations;

    final remoteList = args.completionData?['answers'] as List<dynamic>? ?? [];

    // Convert remote array to a map by questionId
    final Map<String, Map<String, dynamic>> remoteByQid = {};
    for (final x in remoteList) {
      if (x is Map<String, dynamic>) {
        final qid = _asStr(x['question_id']);
        if (qid != null) remoteByQid[qid] = x;
      }
    }

    final List<_ReviewItem> items = [];

    for (final q in args.questions) {
      final snap = snapshots[q.id];
      final remote = remoteByQid[q.id];

      // 1) USER ANSWER (priority: snapshot + remote)
      final userAnswer = snap?.optionText ??
          snap?.answerText ??
          _firstNonEmpty(
            remote,
            [
              'user_answer',
              'user_answer_text',
              'user_option_text',
              'answer_text',
            ],
          );

      // 2) CORRECT / INCORRECT
      final isCorrect = snap?.isCorrect ?? (remote?['is_correct'] as bool?);

      // 3) CORRECT ANSWER (priority: remote + null)
      final correctAnswer = _firstNonEmpty(
        remote,
        [
          'correct_answer',
          'correct_option_text',
          'correct_answer_text',
        ],
      );

      Map<String, dynamic>? writingEval = snap?.writingEval;
      if (writingEval == null && remote != null && remote['writing_eval'] is Map<String, dynamic>) {
        writingEval = Map<String, dynamic>.from(remote['writing_eval'] as Map);
      }
      if (writingEval == null && writingEvals != null) {
        final maybeEval = writingEvals[q.id];
        if (maybeEval is Map<String, dynamic>) {
          writingEval = maybeEval;
        }
      }

      items.add(
        _ReviewItem(
          prompt: q.prompt,
          userAnswer: userAnswer,
          isCorrect: isCorrect,
          correctAnswer: correctAnswer,
          writingEval: writingEval,
          type: q.type,
        ),
      );
    }

    return items;
  }

  @override
  Widget build(BuildContext context) {
    final filtered = _items.where((item) {
      switch (_filter) {
        case _ReviewFilter.correct:
          return item.isCorrect == true;
        case _ReviewFilter.incorrect:
          return item.isCorrect == false;
        case _ReviewFilter.all:
          return true;
      }
    }).toList();

    return Scaffold(
      appBar: AppBar(title: Text(widget.title ?? 'Review questions')),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(12.0),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                FilterChip(
                  label: const Text('All'),
                  selected: _filter == _ReviewFilter.all,
                  onSelected: (_) => setState(() => _filter = _ReviewFilter.all),
                ),
                const SizedBox(width: 8),
                FilterChip(
                  label: const Text('Correct'),
                  selected: _filter == _ReviewFilter.correct,
                  onSelected: (_) => setState(() => _filter = _ReviewFilter.correct),
                ),
                const SizedBox(width: 8),
                FilterChip(
                  label: const Text('Incorrect'),
                  selected: _filter == _ReviewFilter.incorrect,
                  onSelected: (_) => setState(() => _filter = _ReviewFilter.incorrect),
                ),
              ],
            ),
          ),
          Expanded(
            child: filtered.isEmpty
                ? const Center(child: Text('No answers available'))
                : ListView.separated(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    separatorBuilder: (_, __) => const SizedBox(height: 10),
                    itemCount: filtered.length,
                    itemBuilder: (ctx, i) {
                      final item = filtered[i];
                      return Card(
                        child: Padding(
                          padding: const EdgeInsets.all(16),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Question ${i + 1}',
                                style: Theme.of(context).textTheme.labelSmall,
                              ),
                              const SizedBox(height: 6),

                              // PROMPT
                              Text(
                                item.prompt,
                                style: Theme.of(context).textTheme.titleMedium,
                              ),
                              const SizedBox(height: 10),

                              // USER ANSWER
                              Text('Your answer: ${item.userAnswer ?? '-'}'),

                              // CORRECT ANSWER (ONLY IF WRONG)
                              if (item.isCorrect == false &&
                                  item.correctAnswer != null &&
                                  item.correctAnswer!.isNotEmpty)
                                Padding(
                                  padding: const EdgeInsets.only(top: 6.0),
                                  child: Text(
                                    'Correct answer: ${item.correctAnswer}',
                                    style: const TextStyle(
                                      color: Colors.green,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ),

                              const SizedBox(height: 10),

                              // CORRECT/INCORRECT ICON + LABEL
                              Row(
                                children: [
                                  Icon(
                                    item.isCorrect == true ? Icons.check_circle : Icons.cancel,
                                    color: item.isCorrect == true ? Colors.green : Colors.red,
                                  ),
                                  const SizedBox(width: 8),
                                  Text(item.isCorrect == true ? 'Correct' : 'Incorrect'),
                                ],
                              ),

                              if (item.writingEval != null) ...[
                                const SizedBox(height: 12),
                                const Divider(),
                                const SizedBox(height: 8),
                                _writingEvalSection(item.writingEval!),
                              ],
                            ],
                          ),
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }

  Widget _writingEvalSection(Map<String, dynamic> eval) {
    final overall = eval['overall_band'];
    final task = eval['band_task_response'] ?? eval['task_response'];
    final coherence = eval['band_coherence'] ?? eval['coherence_and_cohesion'];
    final lexical = eval['band_lexical'] ?? eval['lexical_resource'];
    final grammar = eval['band_grammar'] ?? eval['grammatical_range_and_accuracy'];
    final feedbackShort = eval['feedback_short'] as String?;
    final feedbackDetailed = eval['feedback_detailed'] as String?;
    final modelAnswer = eval['model_answer'] as String?;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('AI Writing band: ${_fmtBand(overall)}', style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 4),
        Text(
          'Task ${_fmtBand(task)}, Coherence ${_fmtBand(coherence)}, Lexical ${_fmtBand(lexical)}, Grammar ${_fmtBand(grammar)}',
          style: Theme.of(context).textTheme.bodySmall,
        ),
        if (feedbackShort != null && feedbackShort.isNotEmpty) ...[
          const SizedBox(height: 8),
          Text(feedbackShort),
        ],
        if (feedbackDetailed != null && feedbackDetailed.isNotEmpty) ...[
          const SizedBox(height: 8),
          Text(
            feedbackDetailed,
            style: const TextStyle(color: Colors.black87),
          ),
        ],
        if (modelAnswer != null && modelAnswer.isNotEmpty) ...[
          const SizedBox(height: 8),
          Text(
            'Suggested answer:',
            style: Theme.of(context).textTheme.titleSmall,
          ),
          const SizedBox(height: 4),
          Text(modelAnswer),
        ],
      ],
    );
  }

  String _fmtBand(dynamic v) {
    if (v == null) return '-';
    if (v is num) return v.toStringAsFixed(1);
    return v.toString();
  }
}
