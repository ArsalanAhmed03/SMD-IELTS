import 'package:flutter/material.dart';
import '../../core/app_state.dart';
import '../../core/constants.dart';
import '../../core/api_client.dart';
import '../../models/skill.dart';
import '../../models/practice_set.dart';
import '../../widgets/primary_button.dart';
import '../../widgets/practice_set_card.dart';
import '../../widgets/section_header.dart';
import '../../widgets/skill_card.dart';
import '../../widgets/async_message.dart';
import '../exam/exam_intro_screen.dart';
import '../skill/skill_overview_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final _api = ApiClient();
  late Future<List<dynamic>> _skillsFut;
  Future<List<dynamic>>? _quickFut;
  @override
  void initState() {
    super.initState();
    _skillsFut = _api.getSkills();
    _quickFut = _loadQuick();
  }

  Future<List<dynamic>> _loadQuick() async {
    final skills = await _api.getSkills();
    final setsPer = await Future.wait(
        skills.map((s) => _api.getPracticeSetsForSkill(s['slug'])));
    return setsPer.expand((e) => e).take(8).toList();
  }

  @override
  Widget build(BuildContext context) {
    final app = AppStateScope.of(context);

    debugPrint(
        'app: ${app.displayName}, premium: ${app.isPremium}, results: ${app.results.length}');
    return CustomScrollView(
      slivers: [
        SliverAppBar(
          pinned: true,
          title:
              Text('IELTS Prep', style: Theme.of(context).textTheme.titleLarge),
          actions: const [SizedBox(width: 8)],
        ),
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: kPageHPad),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SizedBox(height: 12),
                Text('Welcome back, ${app.displayName ?? 'Learner'}',
                    style: Theme.of(context).textTheme.displayLarge),
                const SizedBox(height: 6),
                Text('Continue your IELTS journey',
                    style: Theme.of(context).textTheme.bodyMedium),
                const SizedBox(height: kSectionSpacing),

                // Skills Grid/List
                const SectionHeader(title: 'Your Skills', icon: Icons.apps),
                FutureBuilder<List<dynamic>>(
                  future: _skillsFut,
                  builder: (context, snap) {
                    if (snap.hasError) {
                      return AsyncMessage(
                        title: 'Failed to load skills',
                        icon: Icons.error_outline,
                        onRetry: () =>
                            setState(() => _skillsFut = _api.getSkills()),
                      );
                    }
                    if (!snap.hasData)
                      return const Padding(
                          padding: EdgeInsets.all(8),
                          child: LinearProgressIndicator());
                    final data = snap.data!;
                    return ListView.separated(
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      itemCount: data.length,
                      separatorBuilder: (_, __) => const SizedBox(height: 10),
                      itemBuilder: (context, index) {
                        final s = data[index];
                        final skillModel = Skill(
                          id: s['slug'],
                          name: s['name'],
                          description: s['description'] ?? '',
                          icon: Icons.school,
                          color: Colors.teal,
                        );
                        return SkillCard(
                          skill: skillModel,
                          subtitle: 'Practice sets',
                          onTap: () => Navigator.push(
                            context,
                            MaterialPageRoute(
                                builder: (_) =>
                                    SkillOverviewScreen(skill: skillModel)),
                          ),
                        );
                      },
                    );
                  },
                ),

                const SizedBox(height: kSectionSpacing),
                const SectionHeader(
                    title: 'Quick Practice', icon: Icons.flash_on),
                SizedBox(
                  height: 140,
                  child: FutureBuilder<List<dynamic>>(
                    future: _quickFut,
                    builder: (context, snap) {
                      if (snap.hasError) {
                        return AsyncMessage(
                          title: 'Failed to load quick practice',
                          icon: Icons.error_outline,
                          onRetry: () =>
                              setState(() => _quickFut = _loadQuick()),
                        );
                      }
                      if (!snap.hasData)
                        return const Center(child: CircularProgressIndicator());
                      final items = snap.data!;
                      if (items.isEmpty) {
                        return const AsyncMessage(
                            title: 'No quick practice sets yet',
                            icon: Icons.hourglass_empty);
                      }
                      return ListView.separated(
                        scrollDirection: Axis.horizontal,
                        itemCount: items.length,
                        separatorBuilder: (_, __) => const SizedBox(width: 12),
                        itemBuilder: (context, index) {
                          final set = items[index];

                          // Be tolerant to null / missing field
                          final isPremium = set['is_premium'] == true;
                          final locked = isPremium && !app.isPremium;

                          final model = PracticeSet(
                            id: set['id'],
                            skillId: 'skill',
                            title: set['title'],
                            levelTag: set['level_tag'] ?? '',
                            questionCount: set['question_count'] ?? 0,
                            estimatedMinutes: set['estimated_minutes'] ?? 0,
                            isPremium: isPremium, // keep consistent
                            shortDescription: set['short_description'] ?? '',
                          );
                          return SizedBox(
                            width: MediaQuery.of(context).size.width * 0.8,
                            child: PracticeSetCard(
                              set: model,
                              skillName: 'Skill',
                              locked: locked,
                              onTap: () {
                                if (locked) {
                                  Navigator.pushNamed(context, '/premium');
                                } else {
                                  Navigator.pushNamed(context, '/practiceSet',
                                      arguments: model.id);
                                }
                              },
                            ),
                          );
                        },
                      );
                    },
                  ),
                ),

                const SizedBox(height: kSectionSpacing),
                const SectionHeader(
                    title: 'Recent Results', icon: Icons.assessment_outlined),
                SizedBox(
                  height: 120,
                  child: app.results.isEmpty
                      ? const AsyncMessage(
                          title: 'No recent results yet',
                          icon: Icons.hourglass_empty)
                      : ListView.separated(
                          scrollDirection: Axis.horizontal,
                          itemCount: app.results.length,
                          separatorBuilder: (_, __) =>
                              const SizedBox(width: 12),
                          itemBuilder: (context, index) {
                            final r = app.results[index];
                            return Card(
                              child: Container(
                                width: 220,
                                padding: const EdgeInsets.all(14),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(r.skillId.toString(),
                                        style: Theme.of(context)
                                            .textTheme
                                            .titleMedium),
                                    const SizedBox(height: 6),
                                    Text(
                                        '${(r.accuracy * 100).round()}% • ${(r.timeTakenSeconds / 60).round()} min'),
                                    const Spacer(),
                                    Text(
                                        '${r.date.toLocal().toString().split(' ').first}',
                                        style: Theme.of(context)
                                            .textTheme
                                            .labelSmall),
                                  ],
                                ),
                              ),
                            );
                          },
                        ),
                ),
                const SizedBox(height: kSectionSpacing),
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16.0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Try full exam simulation',
                            style: Theme.of(context).textTheme.titleMedium),
                        const SizedBox(height: 8),
                        Text(
                            'Timed sections for Listening, Reading, Writing and Speaking.'),
                        const SizedBox(height: 12),
                        PrimaryButton(
                          label: 'Open Exam Simulator',
                          icon: Icons.play_arrow_rounded,
                          onPressed: () => Navigator.push(
                            context,
                            MaterialPageRoute(
                                builder: (_) => const ExamIntroScreen()),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),

                const SizedBox(height: 24),
                const SectionHeader(
                    title: 'What our learners say',
                    icon: Icons.chat_bubble_outline),
                SizedBox(
                  height: 130,
                  child: FutureBuilder<List<dynamic>>(
                    future: _api.getTestimonials(),
                    builder: (context, snap) {
                      if (!snap.hasData)
                        return const Center(child: CircularProgressIndicator());
                      final items = snap.data!;
                      return ListView.separated(
                        scrollDirection: Axis.horizontal,
                        itemCount: items.length,
                        separatorBuilder: (_, __) => const SizedBox(width: 12),
                        itemBuilder: (context, i) {
                          final t = items[i];
                          return Card(
                            child: Container(
                              width: 260,
                              padding: const EdgeInsets.all(14),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text('"${t['quote']}"',
                                      maxLines: 3,
                                      overflow: TextOverflow.ellipsis),
                                  const Spacer(),
                                  Text('- ${t['name']} • ${t['role_or_band']}',
                                      style: Theme.of(context)
                                          .textTheme
                                          .labelSmall),
                                ],
                              ),
                            ),
                          );
                        },
                      );
                    },
                  ),
                ),
                const SizedBox(height: 16),
              ],
            ),
          ),
        ),
      ],
    );
  }
}
