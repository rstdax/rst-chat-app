import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/foundation.dart'; // Added for debugPrint

// ---> 1. TOP-LEVEL BACKGROUND HANDLER <---
// This MUST be a top-level function (outside of any class) to work when the app is terminated.
@pragma('vm:entry-point')
Future<void> _firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  // If you need to initialize Firebase here, do it, but usually, the system handles it.
  debugPrint("Handling a background message: ${message.messageId}");
}

final notificationProvider = Provider<NotificationRepository>((ref) {
  return NotificationRepository(
    FirebaseMessaging.instance,
    FirebaseFirestore.instance,
    FirebaseAuth.instance,
  );
});

class NotificationRepository {
  final FirebaseMessaging _messaging;
  final FirebaseFirestore _firestore;
  final FirebaseAuth _auth;

  NotificationRepository(this._messaging, this._firestore, this._auth);

  Future<void> initialize() async {
    // 1. Request Permission (Required for Android 13+ and iOS)
    NotificationSettings settings = await _messaging.requestPermission(
      alert: true,
      badge: true,
      sound: true,
    );

    if (settings.authorizationStatus != AuthorizationStatus.authorized) {
      debugPrint('User declined push notifications.');
      return;
    }

    // ---> 2. REGISTER BACKGROUND HANDLER <---
    FirebaseMessaging.onBackgroundMessage(_firebaseMessagingBackgroundHandler);

    // ---> 3. LISTEN FOR FOREGROUND MESSAGES <---
    // This catches notifications when the app is open on the screen
    FirebaseMessaging.onMessage.listen((RemoteMessage message) {
      debugPrint('Got a message whilst in the foreground!');
      if (message.notification != null) {
        debugPrint('Notification Title: ${message.notification?.title}');
        debugPrint('Notification Body: ${message.notification?.body}');

        // Note: You can trigger a local Snackbar or dialog here if you want
        // a visual alert while the user is using the app.
      }
    });

    // 4. Grab the unique device token
    String? token = await _messaging.getToken();
    if (token != null) {
      await _saveTokenToDatabase(token);
    }

    // 5. Listen for token refreshes (Firebase rotates these occasionally)
    _messaging.onTokenRefresh.listen(_saveTokenToDatabase);
  }

  Future<void> _saveTokenToDatabase(String token) async {
    final user = _auth.currentUser;
    if (user == null) return;

    // We save the token in your database so your backend knows who to ping
    await _firestore.collection('users').doc(user.uid).set({
      'displayName': user.displayName,
      'email': user.email,
      'fcmToken': token, // The mobile device token!
      'lastActive': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));

    debugPrint("Device token saved securely.");
  }
}
