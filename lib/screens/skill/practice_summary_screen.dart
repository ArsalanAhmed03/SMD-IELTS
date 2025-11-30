import 'package:flutter/material.dart';
import '../../core/constants.dart';
import '../../mock/mock_data.dart';
import '../../models/practice_review_models.dart';
import 'practice_review_screen.dart';

class PracticeSummaryScreen extends StatelessWidget {
  const PracticeSummaryScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final args =
        ModalRoute.of(context)!.settings.arguments as PracticeSummaryArgs;
    final result = args.result;
    final practiceMeta =
        args.completionData?['practice_set'] as Map<String, dynamic>?;
    final stats =
        (args.completionData?['stats'] ?? const {}) as Map<String, dynamic>;

    final mockSkill = skills.where((s) => s.id == result.skillId);
    final mockSet = practiceSets.where((p) => p.id == result.practiceSetId);
    final skillName =
        practiceMeta?['skill_name'] ?? (mockSkill.isNotEmpty ? mockSkill.first.name : null);
    final setTitle =
        practiceMeta?['title'] ?? (mockSet.isNotEmpty ? mockSet.first.title : null);
    final headerTitle = args.title ??
        [skillName, setTitle]
            .whereType<String>()
            .where((s) => s.isNotEmpty)
            .join(' · ');
    final subtitleText = skillName != null
        ? 'Nice work! You finished this $skillName practice set.'
        : 'Nice work! You finished this practice set.';

    final total = stats['total_questions'] ?? result.totalQuestions;
    final correct = stats['correct_questions'] ?? result.correctQuestions;
    final seconds = stats['time_taken_seconds'] ?? result.timeTakenSeconds ?? 0;
    final timeLabel =
        seconds >= 60 ? '${(seconds / 60).round()} min' : '${seconds}s';

    // AI writing eval summary
    final writingEvals = args.writingEvaluations ?? const <String, dynamic>{};
    final writingEvalList =
        writingEvals.values.whereType<Map<String, dynamic>>().toList();

    Map<String, dynamic>? _pickBestEval() {
      if (writingEvalList.isEmpty) return null;
      writingEvalList.sort((a, b) {
        final av = (a['overall_band'] as num?) ?? 0;
        final bv = (b['overall_band'] as num?) ?? 0;
        return bv.compareTo(av);
      });
      return writingEvalList.first;
    }

    final bestEval = _pickBestEval();

    String _fmtBand(dynamic v) {
      if (v == null) return '-';
      if (v is num) return v.toStringAsFixed(1);
      return v.toString();
    }
    String _fmtTime(int seconds) {
      if (seconds >= 60) {
        final m = seconds ~/ 60;
        final s = seconds % 60;
        return s == 0 ? '${m}m' : '${m}m ${s}s';
      }
      return '${seconds}s';
    }

    final isSpeaking = result.skillId == 'speaking';

    return Scaffold(
      appBar: AppBar(title: const Text('Practice summary')),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _SummaryHero(
                title: headerTitle.isNotEmpty ? headerTitle : 'Practice summary',
                subtitle: subtitleText,
                stats: [
                  _Stat(label: 'Total', value: '$total'),
                  _Stat(label: 'Correct', value: '$correct'),
                  _Stat(label: 'Time', value: _fmtTime(seconds)),
                ],
              ),

              Expanded(
                child: SingleChildScrollView(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (bestEval != null) ...[
                        const SizedBox(height: 12),
                        Card(
                          child: Padding(
                            padding: const EdgeInsets.all(16.0),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'AI writing feedback',
                                  style:
                                      Theme.of(context).textTheme.titleMedium,
                                ),
                                const SizedBox(height: 6),
                                Text(
                                  'Overall band: ${_fmtBand(bestEval['overall_band'])}',
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  bestEval['feedback_short'] as String? ??
                                      'Tap "Review questions" to see detailed feedback.',
                                ),
                              ],
                            ),
                          ),
                        ),
                      ],

                      const SizedBox(height: 16),
                      Text(subtitleText),
                      const SizedBox(height: 16),

                      if ((args.completionData?['answers'] as List?)?.isNotEmpty ??
                          false)
                        _AnswerList(answers: (args.completionData?['answers'] as List).take(6).toList()),
                      if ((args.speakingEvaluations ?? {}).isNotEmpty) ...[
                        const SizedBox(height: 12),
                        _SpeakingEvalList(evals: args.speakingEvaluations ?? const {}),
                      ],

                      const SizedBox(height: 16),
                    ],
                  ),
                ),
              ),

              // bottom buttons (fixed)
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => Navigator.popUntil(
                        context,
                        ModalRoute.withName('/shell'),
                      ),
                      child: const Text('Back to practice'),
                    ),
                  ),
                  if (!isSpeaking) ...[
                    const SizedBox(width: 8),
                    Expanded(
                      child: ElevatedButton(
                        onPressed: () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => PracticeReviewScreen(
                                summaryArgs: args,
                                title: headerTitle,
                              ),
                            ),
                          );
                        },
                        child: const Text('Review questions'),
                      ),
                    ),
                  ],
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

}

class _SummaryHero extends StatelessWidget {
  final String title;
  final String subtitle;
  final List<_Stat> stats;
  const _SummaryHero({required this.title, required this.subtitle, required this.stats});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      color: kCard,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
        child: Column(
          children: [
            Container(
              width: 64,
              height: 64,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: theme.colorScheme.primary.withOpacity(0.12),
              ),
              child: Icon(Icons.check_rounded, color: theme.colorScheme.primary, size: 30),
            ),
            const SizedBox(height: 10),
            Text(title, style: theme.textTheme.titleLarge, textAlign: TextAlign.center),
            const SizedBox(height: 4),
            Text(subtitle, style: theme.textTheme.bodyMedium?.copyWith(color: kTextSecondary), textAlign: TextAlign.center),
            const SizedBox(height: 14),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: stats
                  .map(
                    (s) => Column(
                      children: [
                        Text(s.value, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
                        const SizedBox(height: 4),
                        Text(s.label, style: theme.textTheme.labelSmall),
                      ],
                    ),
                  )
                  .toList(),
            ),
          ],
        ),
      ),
    );
  }
}

class _AnswerList extends StatelessWidget {
  final List answers;
  const _AnswerList({required this.answers});
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Recent answers', style: theme.textTheme.titleMedium),
            const SizedBox(height: 12),
            ...answers.map((a) {
              final isCorrect = a['is_correct'] == true;
              final prompt = a['prompt'] ?? '';
              final user = a['user_answer'] ?? a['answer_text'] ?? '—';
              return Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(isCorrect ? Icons.check_circle : Icons.cancel, color: isCorrect ? Colors.green : Colors.red),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(prompt, style: theme.textTheme.bodyLarge),
                          const SizedBox(height: 4),
                          Text('You: $user', style: theme.textTheme.bodySmall),
                        ],
                      ),
                    ),
                  ],
                ),
              );
            }),
          ],
        ),
      ),
    );
  }
}

class _Stat {
  final String label;
  final String value;
  const _Stat({required this.label, required this.value});
}

class _SpeakingEvalList extends StatelessWidget {
  final Map<String, dynamic> evals;
  const _SpeakingEvalList({required this.evals});

  String _fmtBand(dynamic v) {
    if (v == null) return '-';
    if (v is num) return v.toStringAsFixed(1);
    return v.toString();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Speaking feedback', style: theme.textTheme.titleMedium),
            const SizedBox(height: 8),
            ...evals.entries.map((entry) {
              final eval = entry.value as Map<String, dynamic>;
              return Padding(
                padding: const EdgeInsets.only(bottom: 12.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Question: ${entry.key}', style: theme.textTheme.labelSmall),
                    const SizedBox(height: 4),
                    Text('Overall band: ${_fmtBand(eval['overall_band'])}', style: theme.textTheme.bodyMedium),
                    Text(
                      'Fluency ${_fmtBand(eval['fluency_and_coherence'])} / Lexical ${_fmtBand(eval['lexical_resource'])} / Grammar ${_fmtBand(eval['grammatical_range_and_accuracy'])} / Pronunciation ${_fmtBand(eval['pronunciation'])}',
                      style: theme.textTheme.bodySmall,
                    ),
                    if ((eval['transcript'] as String?)?.isNotEmpty ?? false) ...[
                      const SizedBox(height: 6),
                      Text('Transcript', style: theme.textTheme.labelSmall),
                      const SizedBox(height: 2),
                      Text(eval['transcript'] as String),
                    ],
                    if ((eval['feedback_short'] as String?)?.isNotEmpty ?? false) ...[
                      const SizedBox(height: 6),
                      Text(eval['feedback_short'] as String),
                    ],
                    if ((eval['feedback_detailed'] as String?)?.isNotEmpty ?? false) ...[
                      const SizedBox(height: 6),
                      Text(eval['feedback_detailed'] as String, style: const TextStyle(color: Colors.black87)),
                    ],
                  ],
                ),
              );
            }),
          ],
        ),
      ),
    );
  }
}
