import 'package:flutter/material.dart';
import '../../models/practice_review_models.dart';

enum _ReviewFilter { all, correct, incorrect }

class PracticeReviewScreen extends StatefulWidget {
  final PracticeSummaryArgs? summaryArgs;
  final List<ReviewEntry>? entries;
  final String? title;
  const PracticeReviewScreen({super.key, this.summaryArgs, this.entries, this.title})
      : assert(summaryArgs != null || entries != null);

  @override
  State<PracticeReviewScreen> createState() => _PracticeReviewScreenState();
}

class _PracticeReviewScreenState extends State<PracticeReviewScreen> {
  late final List<_ReviewItem> _items;
  _ReviewFilter _filter = _ReviewFilter.all;

  @override
  void initState() {
    super.initState();
    _items = _buildItems();
  }

  List<_ReviewItem> _buildItems() {
    if (widget.entries != null) {
      return widget.entries!
          .map((e) => _ReviewItem(prompt: e.prompt, userAnswer: e.userAnswer, isCorrect: e.isCorrect, correctAnswer: e.correctAnswer))
          .toList();
    }
    final args = widget.summaryArgs!;
    final remoteList = args.completionData?['answers'] as List<dynamic>?;
    final remoteMap = <String, Map<String, dynamic>>{};
    if (remoteList != null) {
      for (final entry in remoteList) {
        remoteMap[entry['question_id'] as String] = entry as Map<String, dynamic>;
      }
    }

    final List<_ReviewItem> items = [];
    for (final q in args.questions) {
      final snap = args.answers[q.id];
      final remote = remoteMap[q.id];
      final userAnswer = snap?.optionText ?? snap?.answerText ?? remote?['user_answer'] ?? remote?['answer_text'];
      final isCorrect = remote?['is_correct'] as bool? ?? snap?.isCorrect;
      final correctAnswer = remote?['correct_answer'] ?? remote?['correct_option'] ?? remote?['correct_option_text'];
      items.add(_ReviewItem(prompt: q.prompt, userAnswer: userAnswer, isCorrect: isCorrect, correctAnswer: correctAnswer));
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
                    itemCount: filtered.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 10),
                    itemBuilder: (context, index) {
                      final item = filtered[index];
                      return Card(
                        child: Padding(
                          padding: const EdgeInsets.all(16.0),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text('Question ${index + 1}', style: Theme.of(context).textTheme.labelSmall),
                              const SizedBox(height: 6),
                              Text(
                                item.prompt,
                                style: Theme.of(context).textTheme.titleMedium,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                              ),
                              const SizedBox(height: 10),
                              Text('Your answer: ${item.userAnswer ?? '—'}'),
                              if (item.correctAnswer != null && item.correctAnswer!.isNotEmpty)
                                Padding(
                                  padding: const EdgeInsets.only(top: 4.0),
                                  child: Text('Correct: ${item.correctAnswer}', style: const TextStyle(color: Colors.green)),
                                ),
                              const SizedBox(height: 8),
                              Row(
                                children: [
                                  Icon(
                                    item.isCorrect == true
                                        ? Icons.check_circle
                                        : item.isCorrect == false
                                            ? Icons.highlight_off
                                            : Icons.help_outline,
                                    color: item.isCorrect == true
                                        ? Colors.green
                                        : item.isCorrect == false
                                            ? Colors.red
                                            : Colors.grey,
                                  ),
                                  const SizedBox(width: 8),
                                  Text(item.isCorrect == true
                                      ? 'Correct'
                                      : item.isCorrect == false
                                          ? 'Incorrect'
                                          : 'Not graded'),
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
