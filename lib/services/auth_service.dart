import 'package:firebase_auth/firebase_auth.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

class AuthService {
  static final FirebaseAuth _auth = FirebaseAuth.instance;
  static final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  // ================= LOGIN EMAIL =================
  static Future<UserCredential> loginEmail({
    required String email,
    required String password,
  }) async {
    return await _auth.signInWithEmailAndPassword(
      email: email,
      password: password,
    );
  }

  // ================= REGISTRO EMAIL =================
  static Future<UserCredential> registerEmail({
    required String email,
    required String password,
  }) async {
    return await _auth.createUserWithEmailAndPassword(
      email: email,
      password: password,
    );
  }

  // ================= GOOGLE LOGIN =================
  static Future<UserCredential> loginGoogle() async {
    final googleSignIn = GoogleSignIn(
      scopes: ['email', 'profile'],
    );

    // Força escolha de conta
    await googleSignIn.signOut();

    final googleUser = await googleSignIn.signIn();
    if (googleUser == null) {
      throw Exception('Usuário cancelou Google login');
    }

    final googleAuth = await googleUser.authentication;

    final credential = GoogleAuthProvider.credential(
      accessToken: googleAuth.accessToken,
      idToken: googleAuth.idToken,
    );

    return await _auth.signInWithCredential(credential);
  }

  // ================= LOGOUT =================
  static Future<void> logout() async {
    await GoogleSignIn().signOut();
    await _auth.signOut();
  }

  // ================= REAUTH PASSWORD =================
  static Future<void> reauthenticateWithPassword({
    required String email,
    required String password,
  }) async {
    final user = _auth.currentUser;
    if (user == null) {
      throw Exception('Usuário não logado');
    }

    final credential = EmailAuthProvider.credential(
      email: email,
      password: password,
    );

    await user.reauthenticateWithCredential(credential);
  }

  // ================= REAUTH GOOGLE =================
  static Future<void> reauthenticateWithGoogle() async {
    final user = _auth.currentUser;
    if (user == null) {
      throw Exception('Usuário não logado');
    }

    final googleSignIn = GoogleSignIn(scopes: ['email', 'profile']);
    await googleSignIn.signOut();

    final googleUser = await googleSignIn.signIn();
    if (googleUser == null) {
      throw Exception('Usuário cancelou Google reauth');
    }

    final googleAuth = await googleUser.authentication;

    final credential = GoogleAuthProvider.credential(
      accessToken: googleAuth.accessToken,
      idToken: googleAuth.idToken,
    );

    await user.reauthenticateWithCredential(credential);
  }

  // ================= DELETE ACCOUNT =================
  static Future<void> deleteAccount() async {
    final user = _auth.currentUser;
    if (user == null) return;

    final uid = user.uid;

    await _firestore.collection('users').doc(uid).delete();
    await user.delete();
  }

  // ================= PROVIDERS =================
  static List<String> getProviders() {
    final user = _auth.currentUser;
    if (user == null) return [];

    return user.providerData.map((p) => p.providerId).toList();
  }
}
