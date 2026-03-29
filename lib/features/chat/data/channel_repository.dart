import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:rxdart/rxdart.dart'; // Required for combining streams
import '../domain/channel_model.dart';
import '../../auth/domain/app_user.dart';

// Provides our repository to the UI
final channelRepositoryProvider = Provider<ChannelRepository>((ref) {
  return ChannelRepository(FirebaseFirestore.instance, FirebaseAuth.instance);
});

// UPDATED: Provides a real-time stream of channels WITH User Data injected
final userChannelsProvider = StreamProvider<List<ChannelModel>>((ref) {
  return ref.watch(channelRepositoryProvider).watchUserChannelsWithProfiles();
});

// Provides a real-time list of all users in the RST Workspace
final allUsersProvider = StreamProvider<List<AppUser>>((ref) {
  return FirebaseFirestore.instance
      .collection('users')
      .snapshots()
      .map(
        (snapshot) => snapshot.docs
            .map((doc) => AppUser.fromFirestore(doc.data(), doc.id))
            .toList(),
      );
});

class ChannelRepository {
  final FirebaseFirestore _firestore;
  final FirebaseAuth _auth;

  // Inside ChannelRepository class

  Future<List<dynamic>> globalSearch(String query) async {
    if (query.trim().isEmpty) return [];

    // We trim and handle both Title Case and lowercase to be safe
    String searchKey = query.trim();
    String searchKeyLower = searchKey.toLowerCase();

    // 1. Search for Users (Primary search)
    final userQuery = await _firestore
        .collection('users')
        .where('displayName', isGreaterThanOrEqualTo: searchKey)
        .where('displayName', isLessThanOrEqualTo: '$searchKey\uf8ff')
        .get();

    // 2. Search for Groups
    final groupQuery = await _firestore
        .collection('channels')
        .where('type', isEqualTo: 'group')
        .where('name', isGreaterThanOrEqualTo: searchKey)
        .where('name', isLessThanOrEqualTo: '$searchKey\uf8ff')
        .get();

    List<dynamic> results = [];

    for (var doc in userQuery.docs) {
      if (doc.id != _auth.currentUser?.uid) {
        results.add(AppUser.fromFirestore(doc.data(), doc.id));
      }
    }

    for (var doc in groupQuery.docs) {
      results.add(ChannelModel.fromMap(doc.data(), doc.id));
    }

    // --- THE "WEBSITE STYLE" FALLBACK ---
    // If we found nothing, let's try searching by email instead
    if (results.isEmpty) {
      final emailQuery = await _firestore
          .collection('users')
          .where('email', isEqualTo: searchKeyLower)
          .get();

      for (var doc in emailQuery.docs) {
        results.add(AppUser.fromFirestore(doc.data(), doc.id));
      }
    }

    return results;
  }

  Future<ChannelModel> getOrCreateDM(AppUser otherUser) async {
    final currentUser = _auth.currentUser;
    if (currentUser == null) throw Exception("Not logged in");

    // 1. Check if a DM already exists between these two
    final existing = await _firestore
        .collection('channels')
        .where('type', isEqualTo: 'dm')
        .where('memberIds', arrayContains: currentUser.uid)
        .get();

    for (var doc in existing.docs) {
      List ids = doc['memberIds'];
      if (ids.contains(otherUser.uid)) {
        return ChannelModel.fromMap(doc.data(), doc.id);
      }
    }

    // 2. If not, create a new one
    final docRef = _firestore.collection('channels').doc();
    final dmData = {
      'name': '${currentUser.displayName}, ${otherUser.displayName}',
      'type': 'dm',
      'memberIds': [currentUser.uid, otherUser.uid],
      'lastMessageText': 'Start of your conversation',
      'lastMessageAt': FieldValue.serverTimestamp(),
      'isArchived': false,
      'createdAt': FieldValue.serverTimestamp(),
    };

    await docRef.set(dmData);
    return ChannelModel.fromMap(dmData, docRef.id);
  }

  ChannelRepository(this._firestore, this._auth);

  /// WATCH CHANNELS WITH PROFILES
  /// This joins the 'channels' stream with the 'users' stream to get live PFP/Names
  Stream<List<ChannelModel>> watchUserChannelsWithProfiles() {
    final currentUser = _auth.currentUser;
    if (currentUser == null) return Stream.value([]);

    // 1. Listen to the channels the user is in
    return _firestore
        .collection('channels')
        .where('memberIds', arrayContains: currentUser.uid)
        .where('isArchived', isEqualTo: false)
        .snapshots()
        .switchMap((channelSnap) {
          if (channelSnap.docs.isEmpty) return Stream.value([]);

          // 2. Identify all "Other Users" needed for DMs
          final List<String> otherUserIds = [];
          for (var doc in channelSnap.docs) {
            if (doc['type'] == 'dm') {
              final List ids = doc['memberIds'] ?? [];
              final otherId = ids.firstWhere(
                (id) => id != currentUser.uid,
                orElse: () => null,
              );
              if (otherId != null) otherUserIds.add(otherId);
            }
          }

          // If no DMs, just return the standard channel list
          if (otherUserIds.isEmpty) {
            return Stream.value(_mapToChannels(channelSnap.docs));
          }

          // 3. Listen to the Profile Data of those "Other Users"
          return _firestore
              .collection('users')
              .where(FieldPath.documentId, whereIn: otherUserIds)
              .snapshots()
              .map((userSnap) {
                // Create a map of UID -> UserData
                final userProfileMap = {
                  for (var doc in userSnap.docs) doc.id: doc.data(),
                };

                // 4. Merge the User Data into the ChannelModel
                return channelSnap.docs.map((doc) {
                  final channelData = doc.data();

                  if (channelData['type'] == 'dm') {
                    final List ids = channelData['memberIds'] ?? [];
                    final otherId = ids.firstWhere(
                      (id) => id != currentUser.uid,
                      orElse: () => null,
                    );
                    final profile = userProfileMap[otherId];

                    if (profile != null) {
                      // Inject the profile photo and name into the channel data
                      return ChannelModel.fromMap({
                        ...channelData,
                        'name': profile['displayName'] ?? channelData['name'],
                        'photoURL':
                            profile['photoURL'], // Live photo from the 'users' collection
                      }, doc.id);
                    }
                  }

                  return ChannelModel.fromMap(channelData, doc.id);
                }).toList()..sort((a, b) => _compareMessages(a, b));
              });
        });
  }

  // --- Helper Methods ---

  List<ChannelModel> _mapToChannels(
    List<QueryDocumentSnapshot<Map<String, dynamic>>> docs,
  ) {
    return docs.map((d) => ChannelModel.fromMap(d.data(), d.id)).toList()
      ..sort((a, b) => _compareMessages(a, b));
  }

  int _compareMessages(ChannelModel a, ChannelModel b) {
    if (a.lastMessageAt == null && b.lastMessageAt == null) return 0;
    if (a.lastMessageAt == null) return 1;
    if (b.lastMessageAt == null) return -1;
    return b.lastMessageAt!.compareTo(a.lastMessageAt!);
  }

  // --- Mutations ---

  Future<void> createGroup(
    String name,
    String description,
    String emoji,
  ) async {
    final user = _auth.currentUser;
    if (user == null || name.trim().isEmpty) return;

    final docRef = _firestore.collection('channels').doc();
    await docRef.set({
      'name': name.trim(),
      'description': description.trim(),
      'type': 'group',
      'emoji': emoji.trim().isEmpty ? '💬' : emoji.trim(),
      'adminIds': [user.uid],
      'memberIds': [user.uid],
      'createdBy': user.uid,
      'createdAt': FieldValue.serverTimestamp(),
      'lastMessageAt': FieldValue.serverTimestamp(),
      'lastMessageText': 'Group created',
      'isArchived': false,
    });

    await docRef.collection('members').doc(user.uid).set({
      'uid': user.uid,
      'role': 'owner',
      'joinedAt': FieldValue.serverTimestamp(),
    });
  }

  Future<void> addMemberToGroup(String channelId, String userId) async {
    await _firestore.collection('channels').doc(channelId).update({
      'memberIds': FieldValue.arrayUnion([userId]),
    });

    await _firestore
        .collection('channels')
        .doc(channelId)
        .collection('members')
        .doc(userId)
        .set({
          'uid': userId,
          'role': 'member',
          'joinedAt': FieldValue.serverTimestamp(),
        });
  }
}
