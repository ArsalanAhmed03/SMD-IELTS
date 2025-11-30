import 'package:flutter/material.dart';
import '../../core/app_state.dart';
import '../../core/constants.dart';
import '../../core/api_client.dart';
import 'exam_section_screen.dart';
import 'exam_full_summary_screen.dart';

class ExamIntroScreen extends StatelessWidget {
  const ExamIntroScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final app = AppStateScope.of(context);
    final api = ApiClient();
    return Scaffold(
      appBar: AppBar(title: const Text('Exam Simulator')),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Full IELTS-style simulation', style: Theme.of(context).textTheme.titleLarge),
              const SizedBox(height: 6),
              const Text('Listening 30m • Reading 60m • Writing 60m • Speaking prompts'),
              const SizedBox(height: 16),
              if (!app.isPremium) ...[
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(14.0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('Full IELTS exam simulations are Premium only.'),
                        const SizedBox(height: 8),
                        const ListTile(
                          leading: Icon(Icons.assignment_turned_in),
                          title: Text('Full exam simulations'),
                        ),
                        const ListTile(
                          leading: Icon(Icons.lock_open),
                          title: Text('Extra practice sets'),
                        ),
                        const ListTile(
                          leading: Icon(Icons.analytics_outlined),
                          title: Text('More detailed statistics'),
                        ),
                        const SizedBox(height: 12),
                        ElevatedButton(
                          onPressed: () => Navigator.pushNamed(context, '/premium'),
                          child: const Text('Go Premium (mock)'),
                        ),
                      ],
                    ),
                  ),
                ),
                const Spacer(),
              ] else ...[
                const Spacer(),
                ElevatedButton.icon(
                  icon: const Icon(Icons.play_arrow_rounded),
                  label: const Text('Start full exam'),
                  onPressed: () async {
                    await _startFullExamFlow(context, api);
                  },
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

Future<void> _startFullExamFlow(BuildContext context, ApiClient api) async {
  // Instead of running sections directly from the intro screen,
  // push a dedicated "runner" screen so we never jump back to intro
  // between sections or before summary.
  await Navigator.push(
    context,
    MaterialPageRoute(
      builder: (_) => _ExamFlowScreen(api: api),
    ),
  );
}

/// Internal exam flow runner:
/// - creates exam session
/// - runs all 4 sections in sequence
/// - after last section, directly shows full summary (no flicker back to intro)
class _ExamFlowScreen extends StatefulWidget {
  final ApiClient api;
  const _ExamFlowScreen({required this.api});

  @override
  State<_ExamFlowScreen> createState() => _ExamFlowScreenState();
}

class _ExamFlowScreenState extends State<_ExamFlowScreen> {
  String? _examId;
  bool _starting = true;
  DateTime? _flowStartedAt;

  final List<Map<String, dynamic>> _sections = const [
    {'slug': 'listening', 'dur': kListeningMinutes},
    {'slug': 'reading', 'dur': kReadingMinutes},
    {'slug': 'writing', 'dur': kWritingMinutes},
    {'slug': 'speaking', 'dur': kSpeakingMinutes},
  ];

  @override
  void initState() {
    super.initState();
    _runFlow();
  }

  Future<void> _runFlow() async {
    try {
      _flowStartedAt = DateTime.now();
      // 1) Create exam session
      final examId = await widget.api.createExamSession();
      if (!mounted) return;
      setState(() {
        _examId = examId;
        _starting = false;
      });

      // 2) Run each section in sequence
      for (final s in _sections) {
        final ok = await Navigator.push<bool>(
          context,
          MaterialPageRoute(
            builder: (_) => ExamSectionScreen(
              examSessionId: examId,
              skillId: s['slug'] as String,
              questions: const [],
              sectionDurationMinutes: s['dur'] as int,
            ),
          ),
        );

        // User backed out of a section → abort whole exam flow
        if (ok != true) {
          if (mounted) Navigator.pop(context);
          return;
        }
      }

      // 3) All sections done → complete exam and show summary directly
      final totalSecs = _flowStartedAt == null ? null : DateTime.now().difference(_flowStartedAt!).inSeconds;
      final summary = await widget.api.completeExamSession(examId, totalTimeSeconds: totalSecs);
      if (!mounted) return;

      Navigator.pushReplacement(
        context,
        MaterialPageRoute(
          builder: (_) => ExamFullSummaryScreen(summary: summary),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to start exam: $e')),
      );
      Navigator.pop(context);
    }
  }

  @override
  Widget build(BuildContext context) {
    // This screen is mostly invisible to the user because ExamSectionScreen
    // sits on top, but it gives us a place to show a safe loading state
    // before the first section opens.
    return Scaffold(
      appBar: AppBar(title: const Text('Exam in progress')),
      body: Center(
        child: _starting
            ? const CircularProgressIndicator()
            : const Text('Compiling results...'),
      ),
    );
  }
}
