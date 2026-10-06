import 'package:firebase_auth/firebase_auth.dart';

class PlayerIdentityService {
  final FirebaseAuth _auth;

  PlayerIdentityService({FirebaseAuth? auth})
      : _auth = auth ?? FirebaseAuth.instance;

  /// Returns the current user, signing in anonymously if needed.
  Future<User> signInIfNeeded() async {
    if (_auth.currentUser != null) return _auth.currentUser!;
    final cred = await _auth.signInAnonymously();
    return cred.user!;
  }

  String? get currentUserId => _auth.currentUser?.uid;

  String get displayName {
    final uid = currentUserId;
    if (uid == null) return 'Operador';
    // Default: last 4 chars of uid, uppercased
    return 'OP-${uid.substring(uid.length - 4).toUpperCase()}';
  }

  /// Call before showing the lobby to guarantee a signed-in user.
  Future<void> ensureSignedIn() => signInIfNeeded();
}
