import 'package:flutter/material.dart';
import 'package:flutter_linkify/flutter_linkify.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:any_link_preview/any_link_preview.dart';
import '../domain/message_model.dart';
import '../data/chat_repository.dart';
import '../../auth/data/auth_repository.dart';
import '../../thread/presentation/thread_screen.dart';
import 'full_screen_image.dart';

class MessageBubble extends ConsumerWidget {
  final MessageModel message;
  final bool isMe;
  final String channelId;

  const MessageBubble({
    super.key,
    required this.message,
    required this.isMe,
    required this.channelId,
  });

  static final RegExp _strictUrlRegExp = RegExp(
    r'(?:(?:https?|ftp):\/\/)?(?:www\.)?[-a-zA-Z0-9@:%._\+~#=]{1,256}\.[a-zA-Z]{2,6}\b(?:[-a-zA-Z0-9()@:%_\+.~#?&//=]*)',
    caseSensitive: false,
  );

  bool _containsUrl(String text) {
    return _strictUrlRegExp.hasMatch(text);
  }

  Future<void> _launchUrl(String text) async {
    final match = _strictUrlRegExp.firstMatch(text);
    if (match != null) {
      String urlStr = match.group(0)!;
      if (!urlStr.startsWith('http')) urlStr = 'https://$urlStr';
      final Uri url = Uri.parse(urlStr);
      await launchUrl(url, mode: LaunchMode.externalApplication);
    }
  }

  String? _getFirstUrl(String text) {
    final match = _strictUrlRegExp.firstMatch(text);
    if (match != null) {
      String urlStr = match.group(0)!;
      if (!urlStr.startsWith('http')) urlStr = 'https://$urlStr';
      return urlStr;
    }
    return null;
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final currentUserId = ref.watch(authStateProvider).value?.uid;
    int readersCount = isMe
        ? (message.readBy?.where((uid) => uid != currentUserId).length ?? 0)
        : 0;
    final String? firstUrl = _getFirstUrl(message.text);
    final double maxBubbleWidth = MediaQuery.of(context).size.width * 0.8;

    // ==========================================
    // ---> NEW: DYNAMIC CONTRAST LOGIC <---
    // ==========================================
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final primaryColor = Theme.of(context).colorScheme.primary;

    // 1. Smart Contrast for YOUR bubbles based on your chosen Theme Color
    final myTextColor = primaryColor.computeLuminance() > 0.4
        ? Colors.black87
        : Colors.white;

    // 2. Smart Contrast for THEIR bubbles based on Dark/Light mode
    final otherTextColor = isDark ? Colors.white : Colors.black87;

    // 3. Their bubble background color
    final otherBubbleColor = isDark
        ? Colors.grey.shade800
        : Theme.of(context).colorScheme.surfaceVariant;

    // 4. Metadata (Time, Seen by, Sender Name)
    final metaDataColor = isDark ? Colors.grey.shade400 : Colors.grey.shade600;

    return Align(
      alignment: isMe ? Alignment.centerRight : Alignment.centerLeft,
      child: Column(
        crossAxisAlignment: isMe
            ? CrossAxisAlignment.end
            : CrossAxisAlignment.start,
        children: [
          Container(
            margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
            padding: const EdgeInsets.all(12),
            constraints: BoxConstraints(maxWidth: maxBubbleWidth),
            decoration: BoxDecoration(
              // ---> MODIFIED: Uses dynamic background colors <---
              color: isMe ? primaryColor : otherBubbleColor,
              borderRadius: BorderRadius.circular(18).copyWith(
                bottomRight: isMe ? const Radius.circular(4) : null,
                bottomLeft: !isMe ? const Radius.circular(4) : null,
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (!isMe)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 4.0),
                    child: Text(
                      message.senderName,
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                        color:
                            primaryColor, // Your accent color highlights their name perfectly
                      ),
                    ),
                  ),

                // --- 1. POLL UI ---
                if (message.type == 'poll' && message.options != null) ...[
                  Text(
                    message.text,
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      // ---> MODIFIED: Dynamic Text Color <---
                      color: isMe ? myTextColor : otherTextColor,
                    ),
                  ),
                  const SizedBox(height: 8),
                  ...List.generate(message.options!.length, (index) {
                    final opt = message.options![index];
                    return GestureDetector(
                      onTap: () => ref
                          .read(chatRepositoryProvider)
                          .voteOnPoll(channelId, message.id, index),
                      child: Container(
                        margin: const EdgeInsets.only(bottom: 4),
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: isDark
                              ? Colors.white12
                              : Colors.black12, // Subtle contrast
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(
                          "${opt.text} (${opt.votes.length})",
                          style: TextStyle(
                            // ---> MODIFIED: Dynamic Text Color <---
                            color: isMe ? myTextColor : otherTextColor,
                          ),
                        ),
                      ),
                    );
                  }),
                ]
                // --- 2. IMAGE UI ---
                else if (message.type == 'image' &&
                    message.attachmentUrl != null)
                  GestureDetector(
                    onTap: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (context) => FullScreenImageViewer(
                            imageUrl: message.attachmentUrl!,
                            heroTag: message.id,
                          ),
                        ),
                      );
                    },
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(12),
                      child: ConstrainedBox(
                        constraints: BoxConstraints(
                          maxHeight: maxBubbleWidth * 1.25,
                          minWidth: maxBubbleWidth * 0.5,
                        ),
                        child: Hero(
                          tag: message.id,
                          child: CachedNetworkImage(
                            imageUrl: message.attachmentUrl!,
                            fit: BoxFit.cover,
                            placeholder: (context, url) => const SizedBox(
                              height: 200,
                              child: Center(child: CircularProgressIndicator()),
                            ),
                            errorWidget: (context, url, error) =>
                                const SizedBox(
                                  height: 100,
                                  child: Center(
                                    child: Icon(
                                      Icons.broken_image,
                                      color: Colors.grey,
                                    ),
                                  ),
                                ),
                          ),
                        ),
                      ),
                    ),
                  )
                // --- 3. TEXT & HYPERLINK UI ---
                else
                  SelectableLinkify(
                    text: message.text,
                    onOpen: (link) => _launchUrl(link.url),
                    options: const LinkifyOptions(looseUrl: false),
                    style: TextStyle(
                      // ---> MODIFIED: Dynamic Text Color <---
                      color: isMe ? myTextColor : otherTextColor,
                      fontSize: 15,
                    ),
                    linkStyle: TextStyle(
                      color: isMe
                          ? (myTextColor == Colors.white
                                ? Colors.yellowAccent
                                : Colors.blue.shade900)
                          : Colors.blue,
                      fontWeight: FontWeight.bold,
                      decoration: TextDecoration.underline,
                    ),
                  ),

                // --- 4. SMART LINK PREVIEW ---
                if (firstUrl != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 8.0),
                    child: AnyLinkPreview(
                      link: firstUrl,
                      displayDirection: UIDirection.uiDirectionVertical,
                      showMultimedia: true,
                      bodyMaxLines: 2,
                      headers: const {
                        "User-Agent":
                            "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/91.0.4472.124 Safari/537.36",
                      },
                      cache: const Duration(days: 7),
                      titleStyle: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.bold,
                        // ---> MODIFIED: Dynamic Text Color <---
                        color: isMe ? myTextColor : otherTextColor,
                      ),
                      errorWidget: const SizedBox.shrink(),
                      borderRadius: 12,
                      onTap: () => _launchUrl(firstUrl),
                    ),
                  ),

                // --- 5. FALLBACK OPEN BUTTON ---
                if (_containsUrl(message.text) && firstUrl == null)
                  TextButton.icon(
                    onPressed: () => _launchUrl(message.text),
                    icon: Icon(
                      Icons.open_in_new,
                      size: 14,
                      color: isMe
                          ? (myTextColor == Colors.white
                                ? Colors.yellowAccent
                                : Colors.blue.shade900)
                          : Colors.blue,
                    ),
                    label: Text(
                      "Open Link",
                      style: TextStyle(
                        color: isMe
                            ? (myTextColor == Colors.white
                                  ? Colors.yellowAccent
                                  : Colors.blue.shade900)
                            : Colors.blue,
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),

                // --- 6. REPLY ACTION ---
                const SizedBox(height: 4),
                GestureDetector(
                  onTap: () => Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => ThreadScreen(
                        channelId: channelId,
                        parentMessage: message,
                      ),
                    ),
                  ),
                  child: Text(
                    message.replyCount > 0
                        ? '${message.replyCount} replies'
                        : 'Reply',
                    style: TextStyle(
                      fontSize: 11,
                      // ---> MODIFIED: Dynamic Metadata Color <---
                      color: isMe
                          ? myTextColor.withOpacity(0.7)
                          : metaDataColor,
                    ),
                  ),
                ),
              ],
            ),
          ),

          // --- 7. READ RECEIPTS ---
          if (readersCount > 0)
            Padding(
              padding: const EdgeInsets.only(right: 16),
              child: Text(
                'Seen by $readersCount',
                style: TextStyle(
                  fontSize: 10,
                  color: metaDataColor,
                ), // Match metadata
              ),
            ),
        ],
      ),
    );
  }
}
