import 'package:cloud_firestore/cloud_firestore.dart';

class ChannelModel {
  final String id;
  final String name;
  final String type;
  final String emoji;
  final String lastMessageText;
  final DateTime? lastMessageAt;
  final List<String> memberIds;
  final String? photoURL;

  final List<String> adminIds;
  final String? createdBy;

  // --- NEW TRACKING FIELDS ---
  final String? lastMessageSenderId;
  final List<String> lastMessageReadBy;

  ChannelModel({
    required this.id,
    required this.name,
    required this.type,
    required this.emoji,
    required this.lastMessageText,
    this.lastMessageAt,
    required this.memberIds,
    this.photoURL,
    required this.adminIds,
    this.createdBy,
    this.lastMessageSenderId,
    required this.lastMessageReadBy,
  });

  factory ChannelModel.fromMap(Map<String, dynamic> map, String id) {
    return ChannelModel(
      id: id,
      name: map['name'] ?? '',
      type: map['type'] ?? 'group',
      emoji: map['emoji'] ?? '💬',
      lastMessageText: map['lastMessageText'] ?? '',
      lastMessageAt: (map['lastMessageAt'] as Timestamp?)?.toDate(),
      memberIds: List<String>.from(map['memberIds'] ?? []),
      photoURL: map['photoURL'],
      adminIds: List<String>.from(map['adminIds'] ?? []),
      createdBy: map['createdBy'],

      // --- MAP THE NEW FIELDS ---
      lastMessageSenderId: map['lastMessageSenderId'],
      // Defaults to an empty list if it doesn't exist yet
      lastMessageReadBy: List<String>.from(map['lastMessageReadBy'] ?? []),
    );
  }

  // Helper method to convert the model back to Firestore data
  Map<String, dynamic> toMap() {
    return {
      'name': name,
      'type': type,
      'emoji': emoji,
      'lastMessageText': lastMessageText,
      'lastMessageAt': lastMessageAt != null
          ? Timestamp.fromDate(lastMessageAt!)
          : null,
      'memberIds': memberIds,
      'photoURL': photoURL,
      'adminIds': adminIds,
      'createdBy': createdBy,
      'lastMessageSenderId': lastMessageSenderId,
      'lastMessageReadBy': lastMessageReadBy,
    };
  }
}
