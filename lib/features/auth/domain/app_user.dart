class AppUser {
  final String uid;
  final String displayName;
  final String email;
  final String? photoURL;

  AppUser({
    required this.uid,
    required this.displayName,
    required this.email,
    this.photoURL,
  });

  factory AppUser.fromFirestore(Map<String, dynamic> data, String id) {
    return AppUser(
      uid: id,
      displayName: data['displayName'] ?? 'RST User',
      email: data['email'] ?? '',
      photoURL: data['photoURL'],
    );
  }
}
