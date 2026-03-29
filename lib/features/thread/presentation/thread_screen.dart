import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../chat/domain/message_model.dart';
import '../../chat/data/chat_repository.dart';
import '../../auth/data/auth_repository.dart';

class ThreadScreen extends ConsumerStatefulWidget {
  final String channelId;
  final MessageModel parentMessage;

  const ThreadScreen({
    super.key,
    required this.channelId,
    required this.parentMessage,
  });

  @override
  ConsumerState<ThreadScreen> createState() => _ThreadScreenState();
}

class _ThreadScreenState extends ConsumerState<ThreadScreen> {
  final TextEditingController _replyController = TextEditingController();

  @override
  void dispose() {
    _replyController.dispose();
    super.dispose();
  }

  void _sendReply() {
    final text = _replyController.text;
    if (text.trim().isEmpty) return;

    ref
        .read(chatRepositoryProvider)
        .sendThreadReply(widget.channelId, widget.parentMessage.id, text);
    _replyController.clear();
  }

  @override
  Widget build(BuildContext context) {
    final currentUserId = ref.watch(authStateProvider).value?.uid;
    // Pass both IDs to the provider using a Map
    // Pass the IDs using the new Record syntax (notice the parentheses inside)
    final repliesAsync = ref.watch(
      threadRepliesProvider((
        channelId: widget.channelId,
        messageId: widget.parentMessage.id,
      )),
    );

    return Scaffold(
      appBar: AppBar(title: const Text('Thread')),
      body: Column(
        children: [
          // Parent Message Header
          Container(
            padding: const EdgeInsets.all(16),
            color: Theme.of(context).colorScheme.surface,
            width: double.infinity,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  widget.parentMessage.senderName,
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 4),
                Text(
                  widget.parentMessage.text,
                  style: const TextStyle(fontSize: 16),
                ),
                const Divider(height: 24),
                Text(
                  '${widget.parentMessage.replyCount} Replies',
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    color: Colors.grey,
                  ),
                ),
              ],
            ),
          ),

          // Replies List
          Expanded(
            child: repliesAsync.when(
              data: (replies) {
                if (replies.isEmpty)
                  return const Center(child: Text('No replies yet.'));

                return ListView.builder(
                  itemCount: replies.length,
                  itemBuilder: (context, index) {
                    final reply = replies[index];
                    final isMe = reply.senderId == currentUserId;

                    return ListTile(
                      title: Row(
                        children: [
                          Text(
                            isMe ? 'You' : reply.senderName,
                            style: const TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 13,
                            ),
                          ),
                        ],
                      ),
                      subtitle: Text(reply.text),
                    );
                  },
                );
              },
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (e, _) => Center(child: Text('Error: $e')),
            ),
          ),

          // Reply Input Box
          Container(
            padding: const EdgeInsets.symmetric(
              horizontal: 8,
              vertical: 12,
            ).copyWith(bottom: 24),
            color: Theme.of(context).colorScheme.surface,
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _replyController,
                    decoration: InputDecoration(
                      hintText: 'Reply in thread...',
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(24),
                        borderSide: BorderSide.none,
                      ),
                      filled: true,
                      fillColor: Theme.of(context).colorScheme.background,
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 10,
                      ),
                    ),
                    onSubmitted: (_) => _sendReply(),
                  ),
                ),
                IconButton(
                  icon: Icon(
                    Icons.send,
                    color: Theme.of(context).colorScheme.primary,
                  ),
                  onPressed: _sendReply,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
