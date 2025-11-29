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
                    final speakingAttempts = List<Map<String, dynamic>>.from(section['speaking_attempts'] ?? const []);
                    return Card(
                      child: Padding(
                        padding: const EdgeInsets.only(bottom: 8.0),
                        child: ExpansionTile(
                          title: Text(slug.toUpperCase()),
                          subtitle: Text(
                            'Time ${(section['time_taken_seconds'] ?? 0) / 60 ~/ 1} min / ${section['total_questions'] ?? 0} Q / ${(section['correct_questions'] ?? 0)} correct',
                          ),
                          children: [
                            if (answers.isEmpty)
                              const Padding(
                                padding: EdgeInsets.all(12.0),
                                child: Text('No answers recorded'),
                              )
                            else
                              ...answers.map((a) {
                                final isCorrect = a['is_correct'] == true;
                                final wEval = a['writing_eval'] as Map<String, dynamic>?;
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
                                      if (wEval != null) ...[
                                        const SizedBox(height: 8),
                                        Text('AI Writing band: ${_fmtBand(wEval['overall_band'])}', style: Theme.of(context).textTheme.bodyMedium),
                                        Text(
                                          'Task ${_fmtBand(wEval['band_task_response'] ?? wEval['task_response'])} / Coherence ${_fmtBand(wEval['band_coherence'] ?? wEval['coherence_and_cohesion'])} / Lexical ${_fmtBand(wEval['band_lexical'] ?? wEval['lexical_resource'])} / Grammar ${_fmtBand(wEval['band_grammar'] ?? wEval['grammatical_range_and_accuracy'])}',
                                          style: Theme.of(context).textTheme.bodySmall,
                                        ),
                                        if ((wEval['feedback_short'] as String?)?.isNotEmpty ?? false)
                                          Padding(
                                            padding: const EdgeInsets.only(top: 4.0),
                                            child: Text(wEval['feedback_short'] as String),
                                          ),
                                      ],
                                    ],
                                  ),
                                );
                              }),
                            if (speakingAttempts.isNotEmpty) ...[
                              const Divider(),
                              Padding(
                                padding: const EdgeInsets.symmetric(horizontal: 12.0, vertical: 6),
                                child: Text('Speaking attempts', style: Theme.of(context).textTheme.titleMedium),
                              ),
                              ...speakingAttempts.map((att) {
                                final eval = att['evaluation'] as Map<String, dynamic>?;
                                return Container(
                                  margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                                  padding: const EdgeInsets.all(12),
                                  decoration: BoxDecoration(
                                    color: Colors.blueGrey.withOpacity(0.06),
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(att['question_id'] ?? 'Attempt', style: Theme.of(context).textTheme.labelSmall),
                                      if (eval != null) ...[
                                        Text('AI Speaking band: ${_fmtBand(eval['overall_band'])}', style: Theme.of(context).textTheme.bodyMedium),
                                        Text(
                                          'Fluency ${_fmtBand(eval['band_fluency'] ?? eval['fluency_and_coherence'])} / Lexical ${_fmtBand(eval['band_lexical'] ?? eval['lexical_resource'])} / Grammar ${_fmtBand(eval['band_grammar'] ?? eval['grammatical_range_and_accuracy'])} / Pronunciation ${_fmtBand(eval['band_pronunciation'] ?? eval['pronunciation'])}',
                                          style: Theme.of(context).textTheme.bodySmall,
                                        ),
                                        if ((eval['feedback_short'] as String?)?.isNotEmpty ?? false)
                                          Padding(
                                            padding: const EdgeInsets.only(top: 4.0),
                                            child: Text(eval['feedback_short'] as String),
                                          ),
                                      ] else
                                        const Text('Evaluation pending'),
                                    ],
                                  ),
                                );
                              }),
                            ],
                            Align(
                              alignment: Alignment.centerRight,
                              child: TextButton(
                                onPressed: answers.isEmpty && speakingAttempts.isEmpty
                                    ? null
                                    : () {
                                        final entries = answers
                                            .map((a) => ReviewEntry(
                                                  prompt: a['prompt'] ?? '',
                                                  userAnswer: a['user_answer'] ?? a['answer_text'],
                                                  correctAnswer: a['correct_answer'] ?? a['correct_option_text'],
                                                  isCorrect: a['is_correct'] as bool?,
                                                  writingEval: a['writing_eval'] as Map<String, dynamic>?,
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

  String _fmtBand(dynamic v) {
    if (v == null) return '-';
    if (v is num) return v.toStringAsFixed(1);
    return v.toString();
  }
}
