import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/foundation.dart';
import '../domain/message_model.dart';
import 'dart:io';
import 'package:firebase_storage/firebase_storage.dart';

final chatRepositoryProvider = Provider<ChatRepository>((ref) {
  return ChatRepository(FirebaseFirestore.instance, FirebaseAuth.instance);
});

// Notice the `.family` modifier! This allows us to pass the channelId into the provider.
// 1. This tracks the current message limit for each specific channel (Defaults to 50)
final messageLimitProvider = StateProvider.family<int, String>(
  (ref, channelId) => 50,
);

// 2. Your updated messages provider
final channelMessagesProvider =
    StreamProvider.family<List<MessageModel>, String>((ref, channelId) {
      // Watch the limit dynamically
      final limit = ref.watch(messageLimitProvider(channelId));

      return FirebaseFirestore.instance
          .collection('channels')
          .doc(channelId)
          .collection('messages')
          .orderBy('createdAt', descending: true)
          .limit(limit) // <--- Inject the dynamic limit here
          .snapshots()
          .map(
            (snapshot) => snapshot.docs
                .map((doc) => MessageModel.fromMap(doc.data(), doc.id))
                .toList(),
          );
    });

// Provider to watch who is currently typing
final typingUsersProvider = StreamProvider.family<List<String>, String>((
  ref,
  channelId,
) {
  return ref.watch(chatRepositoryProvider).watchTypingUsers(channelId);
});

// Provider to watch replies for a specific message
// We use a Dart Record here `({String channelId, String messageId})`
// so Riverpod knows exactly when the IDs actually change.
final threadRepliesProvider =
    StreamProvider.family<
      List<MessageModel>,
      ({String channelId, String messageId})
    >((ref, args) {
      return ref
          .watch(chatRepositoryProvider)
          .watchReplies(args.channelId, args.messageId);
    });

class ChatRepository {
  final FirebaseFirestore _firestore;
  final FirebaseAuth _auth;

  ChatRepository(this._firestore, this._auth);

  // Variable to throttle typing writes
  DateTime? _lastTypingTime;

  // 1. Update the current user's typing status
  Future<void> updateTypingStatus(String channelId) async {
    final user = _auth.currentUser;
    if (user == null) return;

    final now = DateTime.now();
    // Throttle writes to once every 2.5 seconds to save Firebase bandwidth
    if (_lastTypingTime != null &&
        now.difference(_lastTypingTime!).inMilliseconds < 2500) {
      return;
    }
    _lastTypingTime = now;

    await _firestore
        .collection('channels')
        .doc(channelId)
        .collection('typing')
        .doc(user.uid)
        .set({
          'uid': user.uid,
          'displayName': user.displayName ?? 'User',
          'updatedAt': FieldValue.serverTimestamp(),
        });
  }

  // Adds the user's ID to the read list when they open the chat
  Future<void> markChannelAsRead(String channelId, String userId) async {
    try {
      await _firestore.collection('channels').doc(channelId).update({
        // arrayUnion ensures the ID is only added once
        'lastMessageReadBy': FieldValue.arrayUnion([userId]),
      });
    } catch (e) {
      debugPrint("Error marking channel as read: $e");
    }
  }

  // Mark a message as read by the current user
  // Inside ChatRepository:
  Future<void> markMessageAsRead(String channelId, String messageId) async {
    final user = _auth.currentUser;
    if (user == null) return;

    // Use arrayUnion. This is idempotent: if the UID is already there,
    // Firestore does NOTHING, preventing the infinite loop.
    await _firestore
        .collection('channels')
        .doc(channelId)
        .collection('messages')
        .doc(messageId)
        .update({
          'readBy': FieldValue.arrayUnion([user.uid]),
        });
  }

  // 2. Stream the list of users currently typing
  Stream<List<String>> watchTypingUsers(String channelId) {
    final user = _auth.currentUser;
    if (user == null) return Stream.value([]);

    return _firestore
        .collection('channels')
        .doc(channelId)
        .collection('typing')
        .snapshots()
        .map((snapshot) {
          final now = DateTime.now();
          final typingNames = <String>[];

          for (var doc in snapshot.docs) {
            final data = doc.data();
            if (data['uid'] == user.uid)
              continue; // Don't show "You are typing"

            // Only show users who have typed in the last 8 seconds
            final updatedAt = (data['updatedAt'] as Timestamp?)?.toDate();
            if (updatedAt != null && now.difference(updatedAt).inSeconds < 8) {
              typingNames.add(data['displayName'] ?? 'Someone');
            }
          }
          return typingNames;
        });
  }

  Stream<List<MessageModel>> watchMessages(String channelId) {
    return _firestore
        .collection('channels')
        .doc(channelId)
        .collection('messages')
        .orderBy('createdAt', descending: true) // Newest messages at the bottom
        .limit(50)
        .snapshots()
        .map((snapshot) {
          return snapshot.docs
              .map((doc) => MessageModel.fromMap(doc.data(), doc.id))
              .toList();
        });
  }

  // 1. Create a new Poll Message
  Future<void> sendPollMessage(
    String channelId,
    String question,
    List<String> optionTexts,
  ) async {
    final user = _auth.currentUser;
    if (user == null || question.trim().isEmpty || optionTexts.length < 2)
      return;

    // Format the options into our map structure
    final pollOptions = optionTexts
        .map((text) => {'text': text.trim(), 'votes': []})
        .toList();

    await _firestore
        .collection('channels')
        .doc(channelId)
        .collection('messages')
        .add({
          'text': question.trim(),
          'type': 'poll',
          'options': pollOptions,
          'senderId': user.uid,
          'senderName': user.displayName ?? 'RST User',
          'createdAt': FieldValue.serverTimestamp(),
          'readBy': {user.uid: FieldValue.serverTimestamp()},
        });

    await _firestore.collection('channels').doc(channelId).update({
      'lastMessageText': '📊 Poll: $question',
      'lastMessageAt': FieldValue.serverTimestamp(),
    });
  }

  // 2. Cast or remove a vote
  Future<void> voteOnPoll(
    String channelId,
    String messageId,
    int optionIndex,
  ) async {
    final user = _auth.currentUser;
    if (user == null) return;

    final msgRef = _firestore
        .collection('channels')
        .doc(channelId)
        .collection('messages')
        .doc(messageId);

    // We use a transaction to ensure vote counts are perfectly accurate even if multiple people vote at once
    await _firestore.runTransaction((transaction) async {
      final snapshot = await transaction.get(msgRef);
      if (!snapshot.exists) return;

      final data = snapshot.data()!;
      if (data['type'] != 'poll' || data['options'] == null) return;

      List<dynamic> options = List.from(data['options']);

      // Remove the user's vote from ALL options first (allows switching votes)
      for (var opt in options) {
        List<String> votes = List<String>.from(opt['votes'] ?? []);
        votes.remove(user.uid);
        opt['votes'] = votes;
      }

      // Add the vote to the newly selected option
      List<String> selectedVotes = List<String>.from(
        options[optionIndex]['votes'],
      );
      selectedVotes.add(user.uid);
      options[optionIndex]['votes'] = selectedVotes;

      transaction.update(msgRef, {'options': options});
    });
  }

  // 1. Stream the replies for a specific thread
  Stream<List<MessageModel>> watchReplies(String channelId, String messageId) {
    return _firestore
        .collection('channels')
        .doc(channelId)
        .collection('messages')
        .doc(messageId)
        .collection('replies')
        .orderBy('createdAt', descending: false) // Oldest first for threads
        .snapshots()
        .map((snapshot) {
          return snapshot.docs
              .map((doc) => MessageModel.fromMap(doc.data(), doc.id))
              .toList();
        });
  }

  // 2. Send a reply and update the parent message's count
  Future<void> sendThreadReply(
    String channelId,
    String messageId,
    String text,
  ) async {
    final user = _auth.currentUser;
    if (user == null || text.trim().isEmpty) return;

    final batch = _firestore.batch();

    // Add the reply to the subcollection
    final replyRef = _firestore
        .collection('channels')
        .doc(channelId)
        .collection('messages')
        .doc(messageId)
        .collection('replies')
        .doc();

    batch.set(replyRef, {
      'text': text.trim(),
      'type': 'text',
      'senderId': user.uid,
      'senderName': user.displayName ?? 'RST User',
      'createdAt': FieldValue.serverTimestamp(),
    });

    // Increment the reply count on the parent message
    final parentMessageRef = _firestore
        .collection('channels')
        .doc(channelId)
        .collection('messages')
        .doc(messageId);

    batch.update(parentMessageRef, {'replyCount': FieldValue.increment(1)});

    await batch.commit();
  }

  Future<void> endCall(String channelId, String messageId) async {
    try {
      await FirebaseFirestore.instance
          .collection('channels')
          .doc(channelId)
          .collection('messages')
          .doc(messageId)
          .update({
            'isCallActive': false,
            'callEndedAt':
                FieldValue.serverTimestamp(), // Optional: if you want to track exact end times
          });
    } catch (e) {
      debugPrint("Failed to end call: $e");
    }
  }

  Future<void> sendMessage(String channelId, String text) async {
    final currentUser = _auth.currentUser;
    if (currentUser == null) return;

    // Generate the document reference first
    final msgRef = _firestore
        .collection('channels')
        .doc(channelId)
        .collection('messages')
        .doc();

    // 1. Create the Message Document (Matching app.js exactly)
    await msgRef.set({
      'text': text,
      'type': 'text',
      'senderId': currentUser.uid,
      'senderName':
          currentUser.displayName ??
          'RST User', // Critical for notification titles!
      'senderPhotoURL': currentUser.photoURL ?? '',
      'createdAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
      'replyCount': 0,
      'attachment': null,
      'readBy': [currentUser.uid],
    });

    // 2. Update the Channel Document for the Home Screen UI
    await _firestore.collection('channels').doc(channelId).update({
      'lastMessageText': text,
      'lastMessageAt': FieldValue.serverTimestamp(),
      'lastMessageSenderId': currentUser.uid,
      'lastMessageReadBy': [currentUser.uid],
    });
  }

  Future<void> sendImageMessage(String channelId, File imageFile) async {
    final user = _auth.currentUser;
    if (user == null) return;

    // 1. Generate a unique ID for the new message
    final messageId = _firestore
        .collection('channels')
        .doc(channelId)
        .collection('messages')
        .doc()
        .id;

    // 2. Create a reference to Firebase Storage
    final ext = imageFile.path.split('.').last;
    final storageRef = FirebaseStorage.instance.ref().child(
      'channels/$channelId/uploads/$messageId/image.$ext',
    );

    try {
      // 3. Upload the file
      await storageRef.putFile(imageFile);
      final downloadUrl = await storageRef.getDownloadURL();

      // 4. Save the message to Firestore using the web app's data structure
      await _firestore
          .collection('channels')
          .doc(channelId)
          .collection('messages')
          .doc(messageId)
          .set({
            'text': '',
            'type': 'image',
            'senderId': user.uid,
            'senderName': user.displayName ?? 'RST User',
            'createdAt': FieldValue.serverTimestamp(),
            'attachment': {
              'downloadURL': downloadUrl,
              'contentType': 'image/$ext',
              'fileName': 'image.$ext',
            },
            'readBy': {user.uid: FieldValue.serverTimestamp()},
          });

      // 5. Update the channel preview
      await _firestore.collection('channels').doc(channelId).update({
        'lastMessageText': '📷 Image',
        'lastMessageAt': FieldValue.serverTimestamp(),
      });
    } catch (e) {
      throw Exception('Failed to upload image: $e');
    }
  }
}
