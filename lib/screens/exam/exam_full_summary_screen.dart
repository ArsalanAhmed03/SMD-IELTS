import 'package:flutter/material.dart';
import '../skill/practice_review_screen.dart';
import '../../models/practice_review_models.dart';

class ExamFullSummaryScreen extends StatelessWidget {
  final Map<String, dynamic> summary;
  const ExamFullSummaryScreen({super.key, required this.summary});

  @override
  Widget build(BuildContext context) {
    final sections = List<Map<String, dynamic>>.from(summary['sections'] as List);
    final exam = summary['exam_session'] as Map<String, dynamic>;
    final totalTime = exam['total_time_seconds'];
    return Scaffold(
      appBar: AppBar(title: const Text('Full Exam Summary')),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Card(
                child: ListTile(
                  leading: const Icon(Icons.verified_rounded, color: Colors.green),
                  title: const Text('Exam completed'),
                  subtitle: Text('Total time: ${((totalTime ?? 0) / 60).round()} min'),
                ),
              ),
              const SizedBox(height: 12),
              Expanded(
                child: ListView.separated(
                  itemCount: sections.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 10),
                  itemBuilder: (context, i) {
                    final section = sections[i];
                    final slug = (section['skill_slug'] as String?) ?? 'section';
                    final answers = List<Map<String, dynamic>>.from(section['answers'] ?? const []);
                    return Card(
                      child: Padding(
                        padding: const EdgeInsets.only(bottom: 8.0),
                        child: ExpansionTile(
                          title: Text(slug.toUpperCase()),
                          subtitle: Text('Time ${(section['time_taken_seconds'] ?? 0) / 60 ~/ 1} min · ${section['total_questions'] ?? 0} Q · ${(section['correct_questions'] ?? 0)} correct'),
                          children: [
                            if (answers.isEmpty)
                              const Padding(
                                padding: EdgeInsets.all(12.0),
                                child: Text('No answers recorded'),
                              )
                            else
                              ...answers.map((a) {
                                final isCorrect = a['is_correct'] == true;
                                return Container(
                                  margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                                  padding: const EdgeInsets.all(12),
                                  decoration: BoxDecoration(
                                    color: (isCorrect ? Colors.green : Colors.red).withOpacity(0.08),
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(a['prompt'] ?? '', style: Theme.of(context).textTheme.titleSmall),
                                      const SizedBox(height: 4),
                                      Text('Your answer: ${a['user_answer'] ?? a['answer_text'] ?? '-'}'),
                                      if ((a['correct_answer'] ?? a['correct_option_text']) != null)
                                        Text('Correct: ${a['correct_answer'] ?? a['correct_option_text']}', style: const TextStyle(color: Colors.green)),
                                    ],
                                  ),
                                );
                              }),
                            Align(
                              alignment: Alignment.centerRight,
                              child: TextButton(
                                onPressed: answers.isEmpty
                                    ? null
                                    : () {
                                        final entries = answers
                                            .map((a) => ReviewEntry(
                                                  prompt: a['prompt'] ?? '',
                                                  userAnswer: a['user_answer'] ?? a['answer_text'],
                                                  correctAnswer: a['correct_answer'] ?? a['correct_option_text'],
                                                  isCorrect: a['is_correct'] as bool?,
                                                ))
                                            .toList();
                                        Navigator.push(
                                          context,
                                          MaterialPageRoute(
                                            builder: (_) => PracticeReviewScreen(entries: entries, title: '${slug.toUpperCase()} review'),
                                          ),
                                        );
                                      },
                                child: const Text('Review section'),
                              ),
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
              ),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: () => Navigator.popUntil(context, (r) => r.isFirst),
                  child: const Text('Back to Home'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
