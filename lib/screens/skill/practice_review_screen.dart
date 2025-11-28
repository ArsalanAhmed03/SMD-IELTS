import 'package:flutter/material.dart';
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

  _ReviewItem({
    required this.prompt,
    this.userAnswer,
    this.isCorrect,
    this.correctAnswer,
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

  // Safely cast to string
  String? _asStr(dynamic v) =>
      v == null ? null : v is String ? v : v.toString();

  // Try multiple fallback keys
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
              ))
          .toList();
    }

    // Case 2: Build from summary args
    final args = widget.summaryArgs!;
    final snapshots = args.answers; // Map<String, AnswerSnapshot>

    final remoteList =
        args.completionData?['answers'] as List<dynamic>? ?? [];

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

      // 1) USER ANSWER (priority: snapshot → remote)
      final userAnswer =
          snap?.optionText ??
              snap?.answerText ??
              _firstNonEmpty(remote, [
                'user_answer',
                'user_answer_text',
                'user_option_text',
                'answer_text',
              ]);

      // 2) CORRECT / INCORRECT
      final isCorrect = snap?.isCorrect ?? (remote?['is_correct'] as bool?);

      // 3) CORRECT ANSWER (priority: remote → null)
      final correctAnswer =
          _firstNonEmpty(remote, [
            'correct_answer',
            'correct_option_text',
            'correct_answer_text',
          ]);

      items.add(
        _ReviewItem(
          prompt: q.prompt,
          userAnswer: userAnswer,
          isCorrect: isCorrect,
          correctAnswer: correctAnswer,
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
                  onSelected: (_) =>
                      setState(() => _filter = _ReviewFilter.all),
                ),
                const SizedBox(width: 8),
                FilterChip(
                  label: const Text('Correct'),
                  selected: _filter == _ReviewFilter.correct,
                  onSelected: (_) =>
                      setState(() => _filter = _ReviewFilter.correct),
                ),
                const SizedBox(width: 8),
                FilterChip(
                  label: const Text('Incorrect'),
                  selected: _filter == _ReviewFilter.incorrect,
                  onSelected: (_) =>
                      setState(() => _filter = _ReviewFilter.incorrect),
                ),
              ],
            ),
          ),
          Expanded(
            child: filtered.isEmpty
                ? const Center(child: Text('No answers available'))
                : ListView.separated(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 16, vertical: 8),
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
                                style: Theme.of(context)
                                    .textTheme
                                    .labelSmall,
                              ),
                              const SizedBox(height: 6),

                              // PROMPT
                              Text(
                                item.prompt,
                                style: Theme.of(context)
                                    .textTheme
                                    .titleMedium,
                              ),
                              const SizedBox(height: 10),

                              // USER ANSWER
                              Text('Your answer: ${item.userAnswer ?? '—'}'),

                              // CORRECT ANSWER (ONLY IF WRONG)
                              if (item.isCorrect == false &&
                                  item.correctAnswer != null &&
                                  item.correctAnswer!.isNotEmpty)
                                Padding(
                                  padding:
                                      const EdgeInsets.only(top: 6.0),
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
                                    item.isCorrect == true
                                        ? Icons.check_circle
                                        : Icons.cancel,
                                    color: item.isCorrect == true
                                        ? Colors.green
                                        : Colors.red,
                                  ),
                                  const SizedBox(width: 8),
                                  Text(
                                    item.isCorrect == true
                                        ? 'Correct'
                                        : 'Incorrect',
                                  ),
                                ],
                              )
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
}
