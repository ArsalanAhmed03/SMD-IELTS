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

    return Scaffold(
      appBar: AppBar(title: const Text('Practice summary')),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // top avatar + title (fixed)
              Center(
                child: TweenAnimationBuilder<double>(
                  tween: Tween(begin: 0.8, end: 1.0),
                  duration: const Duration(milliseconds: 240),
                  curve: Curves.easeOutBack,
                  builder: (context, value, child) =>
                      Transform.scale(scale: value, child: child),
                  child: CircleAvatar(
                    radius: 34,
                    backgroundColor: kBrandAccent.withOpacity(0.2),
                    child: const Icon(
                      Icons.check_rounded,
                      color: kBrandAccent,
                      size: 30,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              Center(
                child: Text(
                  headerTitle.isNotEmpty ? headerTitle : 'Practice summary',
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.titleLarge,
                ),
              ),
              const SizedBox(height: 16),

              // SCROLLABLE content
              Expanded(
                child: SingleChildScrollView(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Card(
                        child: Padding(
                          padding: const EdgeInsets.all(16.0),
                          child: Row(
                            children: [
                              Expanded(child: _stat('Total', '$total')),
                              Expanded(child: _stat('Correct', '$correct')),
                              Expanded(child: _stat('Time', timeLabel)),
                            ],
                          ),
                        ),
                      ),

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
                        Card(
                          child: Padding(
                            padding: const EdgeInsets.all(16.0),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'Recent answers',
                                  style:
                                      Theme.of(context).textTheme.titleMedium,
                                ),
                                const SizedBox(height: 12),
                                ...((args.completionData?['answers'] as List)
                                    .take(3)
                                    .map((a) {
                                  final isCorrect = a['is_correct'] == true;
                                  return Padding(
                                    padding:
                                        const EdgeInsets.only(bottom: 10),
                                    child: Row(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Icon(
                                          isCorrect
                                              ? Icons.check_circle
                                              : Icons.cancel,
                                          color: isCorrect
                                              ? Colors.green
                                              : Colors.red,
                                          size: 18,
                                        ),
                                        const SizedBox(width: 8),
                                        Expanded(
                                          child: Column(
                                            crossAxisAlignment:
                                                CrossAxisAlignment.start,
                                            children: [
                                              Text(
                                                a['prompt'] ?? '',
                                                maxLines: 2,
                                                overflow:
                                                    TextOverflow.ellipsis,
                                              ),
                                              const SizedBox(height: 4),
                                              Text(
                                                'You: ${a['user_answer'] ?? a['answer_text'] ?? '—'}',
                                              ),
                                            ],
                                          ),
                                        ),
                                      ],
                                    ),
                                  );
                                })),
                              ],
                            ),
                          ),
                        ),

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
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _stat(String label, String value) {
    return Column(
      children: [
        Text(
          value,
          style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800),
        ),
        const SizedBox(height: 4),
        Text(label, style: const TextStyle(color: Colors.black54)),
      ],
    );
  }
}
