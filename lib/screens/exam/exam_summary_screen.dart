import 'package:flutter/material.dart';
import '../../core/app_state.dart';
import '../../mock/mock_data.dart';
import '../../models/test_result.dart';
import '../../models/practice_review_models.dart';
import '../../core/constants.dart';

class ExamSummaryScreen extends StatelessWidget {
  final List<TestResult> results;
  final List<ReviewEntry>? reviewEntries;
  const ExamSummaryScreen({super.key, required this.results, this.reviewEntries});

  @override
  Widget build(BuildContext context) {
    final app = AppStateScope.of(context);
    // store into global recent results
    for (final r in results) {
      app.addResult(r);
    }
    final totalSeconds = results.fold<int>(0, (a, b) => a + b.timeTakenSeconds);
    final totalObjective = results.where((r) => r.totalQuestions > 0).toList();
    final correct = totalObjective.fold<int>(0, (a, b) => a + b.correctQuestions);
    final total = totalObjective.fold<int>(0, (a, b) => a + b.totalQuestions);

    return Scaffold(
      appBar: AppBar(title: const Text('Exam Summary')),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Row(
                    children: [
                      const Icon(Icons.verified_rounded, size: 32, color: Colors.green),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('Full exam simulation completed', style: Theme.of(context).textTheme.titleMedium),
                            const SizedBox(height: 6),
                            Text('Time spent: ${(totalSeconds / 60).round()} min • Performance: ${total == 0 ? '—' : '$correct/$total correct'}'),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 12),
              Expanded(
                child: reviewEntries == null || reviewEntries!.isEmpty
                    ? ListView.separated(
                        itemCount: results.length,
                        separatorBuilder: (_, __) => const SizedBox(height: 10),
                        itemBuilder: (context, index) {
                          final r = results[index];
                          final skill = skills.firstWhere((s) => s.id == r.skillId);
                          return Card(
                            child: Padding(
                              padding: const EdgeInsets.all(12.0),
                              child: Row(
                                children: [
                                  CircleAvatar(backgroundColor: skill.color.withOpacity(0.15), child: Icon(skill.icon, color: skill.color)),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text(skill.name, style: Theme.of(context).textTheme.titleMedium),
                                        const SizedBox(height: 4),
                                        Text('Time: ${(r.timeTakenSeconds / 60).round()} min • ${r.totalQuestions == 0 ? 'Completed' : 'Correct ${r.correctQuestions}/${r.totalQuestions}'}'),
                                      ],
                                    ),
                                  ),
                                  const Icon(Icons.chevron_right),
                                ],
                              ),
                            ),
                          );
                        },
                      )
                    : ListView.separated(
                        itemCount: reviewEntries!.length,
                        separatorBuilder: (_, __) => const SizedBox(height: 12),
                        itemBuilder: (context, i) {
                          final entry = reviewEntries![i];
                          final options = entry.options ?? const [];
                          final user = entry.userAnswer?.trim();
                          final correct = entry.correctAnswer?.trim();
                          return Card(
                            child: Padding(
                              padding: const EdgeInsets.all(16.0),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text('Question ${i + 1}', style: Theme.of(context).textTheme.labelSmall),
                                  const SizedBox(height: 6),
                                  Text(entry.prompt, style: Theme.of(context).textTheme.titleMedium),
                                  const SizedBox(height: 10),
                                  if (options.isNotEmpty)
                                    Column(
                                      children: options.map((opt) => _optionTile(opt, user, correct)).toList(),
                                    )
                                  else ...[
                                    Text('Your answer:', style: Theme.of(context).textTheme.bodySmall),
                                    const SizedBox(height: 4),
                                    Text(user ?? '-', style: Theme.of(context).textTheme.bodyMedium),
                                    if (entry.isCorrect == false && (correct?.isNotEmpty ?? false))
                                      Padding(
                                        padding: const EdgeInsets.only(top: 4.0),
                                        child: Text('Correct answer: $correct', style: const TextStyle(color: Colors.green)),
                                      ),
                                  ],
                                  const SizedBox(height: 12),
                                  Row(
                                    children: [
                                      Icon(entry.isCorrect == true ? Icons.check_circle : Icons.cancel,
                                          color: entry.isCorrect == true ? Colors.green : Colors.red),
                                      const SizedBox(width: 8),
                                      Text(entry.isCorrect == true ? 'Correct' : 'Incorrect'),
                                    ],
                                  ),
                                ],
                              ),
                            ),
                          );
                        },
                      ),
              ),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => Navigator.popUntil(context, (r) => r.isFirst),
                      child: const Text('Go to Practice'),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: ElevatedButton(
                      onPressed: () => Navigator.popUntil(context, (r) => r.isFirst),
                      child: const Text('Try another simulation'),
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

  Widget _optionTile(String text, String? user, String? correct) {
    final isCorrect = correct != null && text == correct;
    final isSelected = user != null && text == user;
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
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: border, width: 1.4),
        color: fill,
      ),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
      child: Text(text, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500)),
    );
  }
}
