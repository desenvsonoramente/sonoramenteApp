import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:shared_preferences/shared_preferences.dart';

class AuthService {
  static final FirebaseAuth _auth = FirebaseAuth.instance;
  static final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  static final GoogleSignIn _googleSignIn = GoogleSignIn();

  // ================= USER =================

  static User? get currentUser => _auth.currentUser;

  static bool get isLoggedIn => currentUser != null;

  static bool get isGoogleUser {
    final user = currentUser;
    if (user == null) return false;
    return user.providerData.any(
      (provider) => provider.providerId == 'google.com',
    );
  }

  // ================= LOGOUT =================

  /// onBeforeLogout → usado para parar SessionListener, players, streams etc
  static Future<void> logout({Future<void> Function()? onBeforeLogout}) async {
    final user = currentUser;

    try {
      if (onBeforeLogout != null) {
        await onBeforeLogout();
      }

      // 🔥 remove sessão remota
      if (user != null) {
        await _firestore
            .collection('user_sessions')
            .doc(user.uid)
            .delete()
            .catchError((_) {});
      }

      // 🧹 limpa sessão local
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove('sessionId');

      // 🔐 logout provider
      if (isGoogleUser) {
        await _googleSignIn.signOut();
      }
    } finally {
      await _auth.signOut();
    }
  }

  // ================= PASSWORD =================

  static Future<void> updatePassword(String newPassword) async {
    final user = currentUser;
    if (user == null) {
      throw FirebaseAuthException(
        code: 'no-user',
        message: 'Usuário não autenticado',
      );
    }

    await user.updatePassword(newPassword);
  }

  // ================= REAUTH =================

  static Future<void> reauthenticateWithPassword({
    required String email,
    required String password,
  }) async {
    final user = currentUser;
    if (user == null) {
      throw FirebaseAuthException(
        code: 'no-user',
        message: 'Usuário não autenticado',
      );
    }

    final credential = EmailAuthProvider.credential(
      email: email,
      password: password,
    );

    await user.reauthenticateWithCredential(credential);
  }

  static Future<void> reauthenticateWithGoogle() async {
    final user = currentUser;
    if (user == null) {
      throw FirebaseAuthException(
        code: 'no-user',
        message: 'Usuário não autenticado',
      );
    }

    final googleUser = await _googleSignIn.signIn();
    if (googleUser == null) {
      throw FirebaseAuthException(
        code: 'cancelled',
        message: 'Login cancelado',
      );
    }

    final googleAuth = await googleUser.authentication;

    final credential = GoogleAuthProvider.credential(
      accessToken: googleAuth.accessToken,
      idToken: googleAuth.idToken,
    );

    await user.reauthenticateWithCredential(credential);
  }

  // ================= DELETE ACCOUNT =================

  static Future<void> deleteAccount({
    Future<void> Function()? onBeforeLogout,
  }) async {
    final user = currentUser;
    if (user == null) return;

    // Apaga dados do Firestore
    await _firestore.collection('users').doc(user.uid).delete();

    // Apaga sessão
    await _firestore
        .collection('user_sessions')
        .doc(user.uid)
        .delete()
        .catchError((_) {});

    // Apaga conta do Firebase Auth
    await user.delete();

    // 🔥 limpa tudo
    await logout(onBeforeLogout: onBeforeLogout);
  }
}
