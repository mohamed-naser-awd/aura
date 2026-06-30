import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/providers.dart';
import '../../core/router.dart';
import '../../data/db/app_database.dart';
import '../common/group_avatar.dart';

/// Lists contact groups (feature #2). Tap to configure rules; FAB opens the create wizard.
class GroupsScreen extends ConsumerWidget {
  const GroupsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final groupsAsync = ref.watch(_groupsProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('Groups')),
      floatingActionButton: FloatingActionButton(
        onPressed: () => context.push(Routes.groupCreate),
        child: const Icon(Icons.add),
      ),
      body: groupsAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Error: $e')),
        data: (groups) {
          if (groups.isEmpty) {
            return const Center(child: Text('No groups yet. Tap + to create one.'));
          }
          return ListView.builder(
            itemCount: groups.length,
            itemBuilder: (context, i) {
              final g = groups[i];
              return ListTile(
                leading: GroupAvatar(
                  color: g.color,
                  iconCodePoint: g.iconCodePoint,
                  imagePath: g.imagePath,
                  name: g.name,
                ),
                title: Text(g.name),
                subtitle: Text(_summary(g)),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => context.push('/groups/${g.id}'),
              );
            },
          );
        },
      ),
    );
  }

  String _summary(Group g) {
    final tags = <String>[
      if (g.muteEnabled) 'Muted',
      if (g.ringOverridesSilent) 'Rings when silent',
      if (g.intenseModeEnabled) 'Intense',
      if (g.politeDeclineEnabled) 'Polite decline',
    ];
    return tags.isEmpty ? 'No rules' : tags.join(' · ');
  }
}

final _groupsProvider = StreamProvider<List<Group>>((ref) {
  return ref.watch(groupsRepositoryProvider).watchGroups();
});
