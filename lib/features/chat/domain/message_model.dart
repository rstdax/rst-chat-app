import 'package:cloud_firestore/cloud_firestore.dart';

// Helper class for your Poll features
class PollOption {
  final String text;
  final List<String> votes;

  PollOption({required this.text, required this.votes});

  factory PollOption.fromMap(Map<String, dynamic> map) {
    return PollOption(
      text: map['text'] ?? '',
      votes: List<String>.from(map['votes'] ?? []),
    );
  }
}

class MessageModel {
  final String id;
  final String senderId;
  final String senderName;
  final String text;
  final DateTime? createdAt;
  final String type;
  final String? attachmentUrl;
  final int replyCount;
  final List<PollOption>? options;

  // ---> NEW: readBy is strictly a List now <---
  final List<String> readBy;
  final String? meetUrl;
  final String? roomName;
  final bool? isCallActive;

  MessageModel({
    required this.id,
    required this.senderId,
    required this.senderName,
    required this.text,
    this.createdAt,
    required this.type,
    this.attachmentUrl,
    required this.replyCount,
    this.options,
    required this.readBy,
    this.meetUrl,
    this.roomName,
    this.isCallActive,
  });

  factory MessageModel.fromMap(Map<String, dynamic> map, String id) {
    // ==========================================
    // BULLETPROOF READ-BY PARSER
    // ==========================================
    List<String> parsedReadBy = [];
    if (map['readBy'] != null) {
      if (map['readBy'] is List) {
        parsedReadBy = List<String>.from(map['readBy']);
      } else if (map['readBy'] is Map) {
        parsedReadBy = List<String>.from((map['readBy'] as Map).keys);
      }
    }

    // ==========================================
    // POLL OPTIONS PARSER
    // ==========================================
    List<PollOption>? parsedOptions;
    if (map['options'] != null && map['options'] is List) {
      parsedOptions = (map['options'] as List)
          .map((o) => PollOption.fromMap(o as Map<String, dynamic>))
          .toList();
    }

    // ==========================================
    // ⭐️ THE FIX: SMART IMAGE URL PARSER ⭐️
    // ==========================================
    String? finalImageUrl;

    if (map['attachment'] != null) {
      if (map['attachment'] is Map) {
        // If it's a map (like in your screenshot), grab the downloadURL inside it!
        finalImageUrl = map['attachment']['downloadURL'];
      } else if (map['attachment'] is String) {
        // If it's just a direct string
        finalImageUrl = map['attachment'];
      }
    } else {
      // Fallbacks for your old HTML website
      finalImageUrl =
          map['attachmentUrl'] ??
          map['imageUrl'] ??
          map['image'] ??
          map['photoUrl'];
    }

    return MessageModel(
      id: id,
      senderId: map['senderId'] ?? '',
      senderName: map['senderName'] ?? 'Unknown',
      text: map['text'] ?? '',
      createdAt: (map['createdAt'] as Timestamp?)?.toDate(),
      type: map['type'] ?? 'text',
      attachmentUrl: finalImageUrl, // Pass the safely extracted URL here!
      replyCount: map['replyCount'] ?? 0,
      options: parsedOptions,
      readBy: parsedReadBy,
      meetUrl: map['meetUrl'] as String?,
      roomName: map['roomName'] as String?,
      isCallActive: map['isCallActive'] as bool?,
    );
  }
}
