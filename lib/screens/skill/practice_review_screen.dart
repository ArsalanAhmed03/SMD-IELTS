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
  final Map<String, dynamic>? speakingEval;
  final QuestionType? type;
  final List<String>? options;

  _ReviewItem({
    required this.prompt,
    this.userAnswer,
    this.isCorrect,
    this.correctAnswer,
    this.writingEval,
    this.speakingEval,
    this.type,
    this.options,
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
                speakingEval: e.speakingEval,
                type: e.type,
                options: e.options,
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
          speakingEval: writingEvals?[q.id] as Map<String, dynamic>?,
          type: q.type,
          options: q.options,
        ),
      );
    }

    return items;
  }

  @override
  Widget build(BuildContext context) {
    // Always show all entries; filter chips removed for cleaner UI
    final filtered = _items;

    return Scaffold(
      appBar: AppBar(title: Text(widget.title ?? 'Review questions')),
      body: filtered.isEmpty
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
                        Text('Question ${i + 1}', style: Theme.of(context).textTheme.labelSmall),
                        const SizedBox(height: 6),
                        SelectableText(item.prompt, style: Theme.of(context).textTheme.titleMedium),
                        const SizedBox(height: 10),
                        if (item.type == QuestionType.mcq && (item.options?.isNotEmpty ?? false))
                          _mcqReview(item)
                        else if (item.type == QuestionType.speaking && item.speakingEval != null)
                          _speakingReview(item)
                        else ...[
                          Text('Your answer:', style: Theme.of(context).textTheme.bodySmall),
                          const SizedBox(height: 4),
                          SelectableText(item.userAnswer ?? '-', style: Theme.of(context).textTheme.bodyMedium),
                          if (item.isCorrect == false && (item.correctAnswer?.isNotEmpty ?? false))
                            Padding(
                              padding: const EdgeInsets.only(top: 6.0),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const Text('Correct answer:', style: TextStyle(color: Colors.green)),
                                  const SizedBox(height: 2),
                                  SelectableText(
                                    item.correctAnswer!,
                                    style: const TextStyle(color: Colors.green, fontWeight: FontWeight.w600),
                                  ),
                                ],
                              ),
                            ),
                        ],
                        const SizedBox(height: 10),
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

  Widget _mcqReview(_ReviewItem item) {
    var opts = item.options ?? const [];
    final user = item.userAnswer?.trim();
    final correct = item.correctAnswer?.trim();

    // Fallback: if options are missing (e.g., exam summary), build a minimal set from user + correct
    if (opts.isEmpty) {
      final tmp = <String>[];
      if (user != null && user.isNotEmpty) tmp.add(user);
      if (correct != null && correct.isNotEmpty && !tmp.contains(correct)) tmp.add(correct);
      opts = tmp;
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final opt in opts) ...[
          const SizedBox(height: 8),
          _mcqReviewTile(
            text: opt,
            isSelected: user != null && user == opt,
            isCorrect: correct != null && correct == opt,
          ),
        ],
      ],
    );
  }

  Widget _mcqReviewTile({required String text, required bool isSelected, required bool isCorrect}) {
    Color border;
    if (isCorrect) {
      border = Colors.green;
    } else if (isSelected) {
      border = kBrandPrimary;
    } else {
      border = Colors.grey.shade300;
    }
    final fill = isCorrect
        ? Colors.green.withOpacity(0.08)
        : isSelected
            ? kBrandPrimary.withOpacity(0.06)
            : Colors.white;
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: border, width: 1.4),
        color: fill,
      ),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
      child: Text(text, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500)),
    );
  }

  Widget _speakingReview(_ReviewItem item) {
    final eval = item.speakingEval ?? const {};
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if ((eval['transcript'] as String?)?.isNotEmpty ?? false) ...[
          Text('Transcript', style: Theme.of(context).textTheme.labelSmall),
          const SizedBox(height: 4),
          Text(eval['transcript'] as String),
          const SizedBox(height: 10),
        ],
        Card(
          color: Colors.grey.shade50,
          child: Padding(
            padding: const EdgeInsets.all(12.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('AI Speaking band: ${_fmtBand(eval['overall_band'])}', style: Theme.of(context).textTheme.titleSmall),
                const SizedBox(height: 6),
                Text(
                  'Fluency ${_fmtBand(eval['fluency_and_coherence'])} / Lexical ${_fmtBand(eval['lexical_resource'])} / Grammar ${_fmtBand(eval['grammatical_range_and_accuracy'])} / Pronunciation ${_fmtBand(eval['pronunciation'])}',
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
              ],
            ),
          ),
        ),
      ],
    );
  }
}
