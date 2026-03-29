import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../data/channel_repository.dart';
import '../domain/channel_model.dart';
import '../../auth/domain/app_user.dart';

class MemberManagementScreen extends ConsumerWidget {
  final ChannelModel channel;
  const MemberManagementScreen({super.key, required this.channel});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final allUsersAsync = ref.watch(allUsersProvider);

    return Scaffold(
      appBar: AppBar(title: Text('Add to ${channel.name}')),
      body: allUsersAsync.when(
        data: (users) {
          // Filter: only show users who are NOT already in the channel
          final availableUsers = users
              .where((u) => !channel.memberIds.contains(u.uid))
              .toList();

          if (availableUsers.isEmpty) {
            return const Center(
              child: Padding(
                padding: EdgeInsets.all(24.0),
                child: Text(
                  'Everyone in the workspace is already a member of this group.',
                  textAlign: TextAlign.center,
                ),
              ),
            );
          }

          return ListView.builder(
            itemCount: availableUsers.length,
            itemBuilder: (context, index) {
              final user = availableUsers[index];
              return ListTile(
                leading: CircleAvatar(
                  backgroundImage: user.photoURL != null
                      ? NetworkImage(user.photoURL!)
                      : null,
                  child: user.photoURL == null
                      ? const Icon(Icons.person)
                      : null,
                ),
                title: Text(
                  user.displayName,
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
                subtitle: Text(user.email),
                trailing: ElevatedButton(
                  onPressed: () async {
                    try {
                      await ref
                          .read(channelRepositoryProvider)
                          .addMemberToGroup(channel.id, user.uid);
                      if (context.mounted) {
                        Navigator.pop(context);
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text(
                              '${user.displayName} is now a member!',
                            ),
                          ),
                        );
                      }
                    } catch (e) {
                      if (context.mounted) {
                        ScaffoldMessenger.of(
                          context,
                        ).showSnackBar(SnackBar(content: Text('Error: $e')));
                      }
                    }
                  },
                  child: const Text('Add'),
                ),
              );
            },
          );
        },
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Error: $e')),
      ),
    );
  }
}
