import 'package:flutter/material.dart';
import '../skill/practice_review_screen.dart';
import '../../models/practice_review_models.dart';
import '../../core/constants.dart';
import '../../core/constants.dart' show QuestionType;

class ExamFullSummaryScreen extends StatelessWidget {
  final Map<String, dynamic> summary;
  const ExamFullSummaryScreen({super.key, required this.summary});

  @override
  Widget build(BuildContext context) {
    final sections = List<Map<String, dynamic>>.from(summary['sections'] as List);
    final exam = summary['exam_session'] as Map<String, dynamic>;
    final totalTime = exam['total_time_seconds'];
    final totalQuestions = sections.fold<int>(0, (a, s) => a + (s['total_questions'] as int? ?? 0));
    final correctQuestions = sections.fold<int>(0, (a, s) => a + (s['correct_questions'] as int? ?? 0));
    String _fmtTime(int? seconds) {
      if (seconds == null) return '—';
      if (seconds >= 60) {
        final m = seconds ~/ 60;
        final s = seconds % 60;
        return s == 0 ? '${m}m' : '${m}m ${s}s';
      }
      return '${seconds}s';
    }
    return Scaffold(
      appBar: AppBar(title: const Text('Full Exam Summary')),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            children: [
              _ExamHeroCard(
                totalTime: _fmtTime(totalTime),
                sections: sections.length,
                totalQuestions: totalQuestions,
                correctQuestions: correctQuestions,
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
                    return _SectionCard(
                      slug: slug,
                      section: section,
                      answers: answers,
                      speakingAttempts: speakingAttempts,
                      onReview: () {
                        List<String> _opts(Map<String, dynamic> a) {
                          final raw = (a['options'] as List?)
                                  ?.map((o) => o is Map<String, dynamic> ? (o['text'] ?? '') : o.toString())
                                  .whereType<String>()
                                  .toList() ??
                              <String>[];
                          if (raw.isNotEmpty) return raw;
                          final Set<String> fallback = {};
                          final user = a['user_answer'] ?? a['answer_text'];
                          final correct = a['correct_answer'] ?? a['correct_option_text'];
                          if (user is String && user.isNotEmpty) fallback.add(user);
                          if (correct is String && correct.isNotEmpty) fallback.add(correct);
                          return fallback.toList();
                        }

                        final List<ReviewEntry> entries = [];

                        entries.addAll(answers.map((a) => ReviewEntry(
                              prompt: a['prompt'] ?? '',
                              userAnswer: a['user_answer'] ?? a['answer_text'],
                              correctAnswer: a['correct_answer'] ?? a['correct_option_text'],
                              isCorrect: a['is_correct'] as bool?,
                              writingEval: a['writing_eval'] as Map<String, dynamic>?,
                              options: _opts(a),
                              type: QuestionType.mcq,
                            )));

                        for (final att in speakingAttempts) {
                          final eval = att['evaluation'] as Map<String, dynamic>?;
                          entries.add(
                            ReviewEntry(
                              prompt: att['question_prompt'] ?? att['question_id'] ?? 'Speaking question',
                              userAnswer: eval?['transcript'] ?? 'Audio response',
                              correctAnswer: null,
                              isCorrect: null,
                              speakingEval: eval,
                              type: QuestionType.speaking,
                              options: const [],
                            ),
                          );
                        }

                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => PracticeReviewScreen(entries: entries, title: '${slug.toUpperCase()} review'),
                          ),
                        );
                      },
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

class _Stat extends StatelessWidget {
  final String label;
  final String value;
  const _Stat({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      children: [
        Text(value, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
        const SizedBox(height: 4),
        Text(label, style: theme.textTheme.labelSmall),
      ],
    );
  }
}

class _ExamHeroCard extends StatelessWidget {
  final String totalTime;
  final int sections;
  final int totalQuestions;
  final int correctQuestions;
  const _ExamHeroCard({
    required this.totalTime,
    required this.sections,
    required this.totalQuestions,
    required this.correctQuestions,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      color: kCard,
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  decoration: BoxDecoration(
                    color: theme.colorScheme.primary.withOpacity(0.12),
                    shape: BoxShape.circle,
                  ),
                  padding: const EdgeInsets.all(12),
                  child: const Icon(Icons.verified_rounded, color: Colors.green),
                ),
                const SizedBox(width: 12),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Exam completed', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
                    Text('Time: $totalTime', style: theme.textTheme.bodyMedium),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 14),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                _Stat(label: 'Sections', value: '$sections'),
                _Stat(label: 'Questions', value: '$totalQuestions'),
                _Stat(label: 'Correct', value: '$correctQuestions'),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _SectionCard extends StatelessWidget {
  final String slug;
  final Map<String, dynamic> section;
  final List<Map<String, dynamic>> answers;
  final List<Map<String, dynamic>> speakingAttempts;
  final VoidCallback onReview;

  const _SectionCard({
    required this.slug,
    required this.section,
    required this.answers,
    required this.speakingAttempts,
    required this.onReview,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text(slug.toUpperCase(), style: Theme.of(context).textTheme.titleMedium),
                const Spacer(),
                Text(
                  'Time ${_fmtTime(section['time_taken_seconds'] as int?)} • ${section['total_questions'] ?? 0} Q • ${section['correct_questions'] ?? 0} correct',
                  style: Theme.of(context).textTheme.labelSmall,
                ),
              ],
            ),
            const SizedBox(height: 8),
            if (answers.isEmpty)
              const Text('No answers recorded')
            else ...answers.take(3).map((a) {
              final isCorrect = a['is_correct'] == true;
              final user = a['user_answer'] ?? a['answer_text'] ?? '-';
              final correct = a['correct_answer'] ?? a['correct_option_text'];
              return Container(
                margin: const EdgeInsets.only(top: 8),
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: (isCorrect ? Colors.green : Colors.red).withOpacity(0.08),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(a['prompt'] ?? '', style: Theme.of(context).textTheme.bodyMedium),
                    const SizedBox(height: 4),
                    Text('You: $user', style: Theme.of(context).textTheme.bodySmall),
                    if (correct != null) Text('Correct: $correct', style: const TextStyle(color: Colors.green)),
                  ],
                ),
              );
            }),
            if (speakingAttempts.isNotEmpty) ...[
              const SizedBox(height: 8),
              Text('Speaking attempts: ${speakingAttempts.length}', style: Theme.of(context).textTheme.labelSmall),
            ],
            const SizedBox(height: 8),
            Align(
              alignment: Alignment.centerRight,
              child: TextButton(
                onPressed: answers.isEmpty && speakingAttempts.isEmpty ? null : onReview,
                child: const Text('Review section'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _fmtTime(int? seconds) {
    if (seconds == null) return '—';
    if (seconds >= 60) {
      final m = seconds ~/ 60;
      final s = seconds % 60;
      return s == 0 ? '${m}m' : '${m}m ${s}s';
    }
    return '${seconds}s';
  }
}
