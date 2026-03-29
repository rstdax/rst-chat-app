import 'package:firebase_auth/firebase_auth.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'dart:io';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

// Provides the AuthRepository to the rest of the app
final authRepositoryProvider = Provider<AuthRepository>((ref) {
  return AuthRepository(FirebaseAuth.instance, GoogleSignIn());
});

// A stream that listens for login/logout changes in real-time
final authStateProvider = StreamProvider<User?>((ref) {
  return ref.watch(authRepositoryProvider).authStateChanges;
});

class AuthRepository {
  final FirebaseAuth _auth;
  final GoogleSignIn _googleSignIn;

  AuthRepository(this._auth, this._googleSignIn);

  Stream<User?> get authStateChanges => _auth.authStateChanges();

  Future<UserCredential?> signInWithGoogle() async {
    try {
      final GoogleSignInAccount? googleUser = await _googleSignIn.signIn();
      if (googleUser == null) return null; // User canceled

      final GoogleSignInAuthentication googleAuth =
          await googleUser.authentication;
      final AuthCredential credential = GoogleAuthProvider.credential(
        accessToken: googleAuth.accessToken,
        idToken: googleAuth.idToken,
      );

      // 1. Sign in to Firebase Auth
      final userCredential = await _auth.signInWithCredential(credential);
      final user = userCredential.user;

      // 2. Ensure Firestore User Profile Exists
      if (user != null) {
        final userDocRef = FirebaseFirestore.instance
            .collection('users')
            .doc(user.uid);
        final userDoc = await userDocRef.get();

        if (!userDoc.exists) {
          // Brand new user! Create their default profile.
          await userDocRef.set({
            'displayName':
                user.displayName ?? user.email?.split('@')[0] ?? 'RST User',
            'email': user.email?.toLowerCase() ?? '',
            'photoURL': user.photoURL ?? '',
            'role': 'member', // Default role
            'status': 'online',
            'manualStatus': 'online',
            'themeMode': 'auto',
            'themeColor': '#0f766e',
            'notificationsEnabled': true,
            'createdAt': FieldValue.serverTimestamp(),
            'lastSeen': FieldValue.serverTimestamp(),
            'updatedAt': FieldValue.serverTimestamp(),
          });
        } else {
          // Returning user. Just update their last seen time.
          await userDocRef.update({'lastSeen': FieldValue.serverTimestamp()});
        }
      }

      return userCredential;
    } catch (e) {
      throw Exception('Failed to sign in: $e');
    }
  }

  // Inside your AuthRepository class:
  Future<void> updateProfilePicture(File imageFile) async {
    final user = _auth.currentUser;
    if (user == null) return;

    // 1. Upload to Firebase Storage
    final storageRef = FirebaseStorage.instance.ref().child(
      'user_profiles/${user.uid}.jpg',
    );

    await storageRef.putFile(imageFile);
    final downloadUrl = await storageRef.getDownloadURL();

    // 2. Update Firebase Auth Profile
    await user.updatePhotoURL(downloadUrl);

    // 3. Update Firestore User Document
    await FirebaseFirestore.instance.collection('users').doc(user.uid).update({
      'photoURL': downloadUrl,
    });
  }

  Future<void> signOut() async {
    await _googleSignIn.signOut();
    await _auth.signOut();
  }
}
