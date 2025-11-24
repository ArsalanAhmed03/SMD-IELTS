import 'package:flutter/material.dart';
import '../../core/app_state.dart';
import '../../models/practice_set.dart';
import '../../core/api_client.dart';
import '../../widgets/practice_set_card.dart';
import '../../widgets/async_message.dart';

class PracticeTabScreen extends StatefulWidget {
  const PracticeTabScreen({super.key});

  @override
  State<PracticeTabScreen> createState() => _PracticeTabScreenState();
}

class _PracticeTabScreenState extends State<PracticeTabScreen> {
  final _api = ApiClient();

  String? selectedSkillSlug;
  late Future<List<dynamic>> _skillsFut;

  // cache per skill
  final Map<String, List<dynamic>> _setsCache = {};
  Future<List<dynamic>>? _setsFut;

  @override
  void initState() {
    super.initState();
    _skillsFut = _api.getSkills();

    // Preload first skill’s sets as soon as skills arrive
    _skillsFut.then((skills) {
      if (!mounted || skills.isEmpty) return;
      final firstSlug = skills.first['slug'] as String;
      selectedSkillSlug = firstSlug;
      _setsFut = _fetchSets(firstSlug);
      setState(() {});
    });
  }

  Future<List<dynamic>> _fetchSets(String slug, {bool force = false}) async {
    if (!force && _setsCache.containsKey(slug)) {
      return _setsCache[slug]!;
    }
    final sets = await _api.getPracticeSetsForSkill(slug);
    _setsCache[slug] = sets;
    return sets;
  }

  Future<void> _loadSets(String slug, {bool force = false}) async {
    setState(() {
      selectedSkillSlug = slug;
      // optimistically show cached data if we have it
      _setsFut = _fetchSets(slug, force: force);
    });
  }

  @override
  Widget build(BuildContext context) {
    final app = AppStateScope.of(context);

    return Column(
      children: [
        FutureBuilder<List<dynamic>>(
          future: _skillsFut,
          builder: (context, snap) {
            if (snap.connectionState == ConnectionState.waiting) {
              return const Padding(
                padding: EdgeInsets.all(16),
                child: LinearProgressIndicator(),
              );
            }
            if (snap.hasError) {
              return AsyncMessage(
                title: 'Failed to load skills',
                subtitle: snap.error.toString(),
                icon: Icons.error_outline,
                onRetry: () {
                  setState(() {
                    _skillsFut = _api.getSkills();
                    _setsFut = null;
                    _setsCache.clear();
                    selectedSkillSlug = null;
                  });
                },
              );
            }

            final skills = snap.data ?? [];
            if (skills.isEmpty) {
              return const AsyncMessage(
                title: 'No skills available yet',
                icon: Icons.hourglass_empty,
              );
            }

            // If firstSkill wasn’t set in initState for some reason, fix it here.
            selectedSkillSlug ??= skills.first['slug'] as String;

            return Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              child: Wrap(
                spacing: 8,
                children: [
                  for (final s in skills)
                    ChoiceChip(
                      label: Text(s['name']),
                      selected: selectedSkillSlug == s['slug'],
                      onSelected: (_) {
                        _loadSets(s['slug'] as String, force: false);
                      },
                    ),
                ],
              ),
            );
          },
        ),
        Expanded(
          child: FutureBuilder<List<dynamic>>(
            future: _setsFut,
            builder: (context, snap) {
              final slug = selectedSkillSlug;
              final cached = slug != null ? _setsCache[slug] : null;
              final sets = cached ?? snap.data;

              final isLoading =
                  snap.connectionState == ConnectionState.waiting && sets == null;

              if (isLoading) {
                return const Center(child: CircularProgressIndicator());
              }
              if (snap.hasError) {
                return AsyncMessage(
                  title: 'Could not load practice sets',
                  icon: Icons.error_outline,
                  onRetry: () {
                    final s = selectedSkillSlug;
                    if (s != null) {
                      _loadSets(s, force: true);
                    }
                  },
                );
              }

              if (sets == null || sets.isEmpty) {
                return const AsyncMessage(
                  title: 'No practice sets available',
                  icon: Icons.hourglass_empty,
                );
              }

              return RefreshIndicator(
                onRefresh: () {
                  final s = selectedSkillSlug;
                  if (s == null) return Future.value();
                  _setsCache.remove(s);
                  return _loadSets(s, force: true);
                },
                child: ListView.separated(
                  padding: const EdgeInsets.all(16),
                  itemCount: sets.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 10),
                  itemBuilder: (context, index) {
                    final set = sets[index] as Map<String, dynamic>;

                    // null-safe premium flag
                    final isPremium = set['is_premium'] == true;
                    final locked = isPremium && !app.isPremium;

                    final psModel = PracticeSet(
                      id: set['id'],
                      skillId: selectedSkillSlug ?? 'skill',
                      title: set['title'],
                      levelTag: set['level_tag'] ?? '',
                      questionCount: set['question_count'] ?? 0,
                      estimatedMinutes: set['estimated_minutes'] ?? 0,
                      isPremium: isPremium,
                      shortDescription: set['short_description'] ?? '',
                    );

                    return PracticeSetCard(
                      set: psModel,
                      skillName: selectedSkillSlug ?? 'Skill',
                      locked: locked,
                      onTap: () {
                        if (locked) {
                          Navigator.pushNamed(context, '/premium');
                        } else {
                          Navigator.pushNamed(
                            context,
                            '/practiceSet',
                            arguments: psModel.id,
                          );
                        }
                      },
                    );
                  },
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}
