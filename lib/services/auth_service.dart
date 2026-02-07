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
    print("🧠 LOGIN_EMAIL -> Tentando login: $email");

    final cred = await _auth.signInWithEmailAndPassword(
      email: email,
      password: password,
    );

    print("✅ LOGIN_EMAIL -> Sucesso UID: ${cred.user?.uid}");
    return cred;
  }

  // ================= REGISTRO EMAIL =================
  static Future<UserCredential> registerEmail({
    required String email,
    required String password,
  }) async {
    print("🧠 REGISTER_EMAIL -> Criando conta: $email");

    final cred = await _auth.createUserWithEmailAndPassword(
      email: email,
      password: password,
    );

    print("✅ REGISTER_EMAIL -> Criado UID: ${cred.user?.uid}");
    return cred;
  }

  // ================= GOOGLE LOGIN =================
  static Future<UserCredential> loginGoogle() async {
    print("🧠 GOOGLE_LOGIN -> Iniciando Google SignIn");

    final googleSignIn = GoogleSignIn(
      scopes: ['email', 'profile'],
    );

    // 🔥 FORÇA ESCOLHA DE CONTA SEMPRE
    await googleSignIn.signOut();
    print("🧠 GOOGLE_LOGIN -> Cache Google LIMPO");

    final googleUser = await googleSignIn.signIn();
    if (googleUser == null) {
      throw Exception("Usuário cancelou Google login");
    }

    print("🧠 GOOGLE_LOGIN -> Conta escolhida: ${googleUser.email}");

    final googleAuth = await googleUser.authentication;

    final credential = GoogleAuthProvider.credential(
      accessToken: googleAuth.accessToken,
      idToken: googleAuth.idToken,
    );

    final cred = await _auth.signInWithCredential(credential);

    print("✅ GOOGLE_LOGIN -> Firebase UID: ${cred.user?.uid}");
    return cred;
  }

  // ================= LOGOUT =================
  static Future<void> logout() async {
    print("🧠 LOGOUT -> Saindo Google + Firebase");
    await GoogleSignIn().signOut();
    await _auth.signOut();
  }

  // ================= REAUTH PASSWORD =================
  static Future<void> reauthenticateWithPassword({
    required String email,
    required String password,
  }) async {
    print("🧠 REAUTH_PASSWORD -> $email");

    final user = _auth.currentUser;
    if (user == null) throw Exception("Usuário não logado");

    final credential = EmailAuthProvider.credential(
      email: email,
      password: password,
    );

    await user.reauthenticateWithCredential(credential);
    print("✅ REAUTH_PASSWORD -> OK");
  }

  // ================= REAUTH GOOGLE =================
  static Future<void> reauthenticateWithGoogle() async {
    print("🧠 REAUTH_GOOGLE ->");

    final user = _auth.currentUser;
    if (user == null) throw Exception("Usuário não logado");

    final googleSignIn = GoogleSignIn(scopes: ['email', 'profile']);
    await googleSignIn.signOut();

    final googleUser = await googleSignIn.signIn();
    final googleAuth = await googleUser!.authentication;

    final credential = GoogleAuthProvider.credential(
      accessToken: googleAuth.accessToken,
      idToken: googleAuth.idToken,
    );

    await user.reauthenticateWithCredential(credential);
    print("✅ REAUTH_GOOGLE -> OK");
  }

  // ================= DELETE ACCOUNT =================
  static Future<void> deleteAccount() async {
    final user = _auth.currentUser;
    if (user == null) return;

    final uid = user.uid;
    print("🧠 DELETE_ACCOUNT -> UID: $uid");

    try {
      await _firestore.collection('users').doc(uid).delete();
      print("✅ DELETE_ACCOUNT -> Firestore apagado");
    } catch (e) {
      print("❌ DELETE_ACCOUNT -> Firestore erro: $e");
    }

    await user.delete();
    print("✅ DELETE_ACCOUNT -> FirebaseAuth apagado");
  }

  // ================= PROVIDERS =================
  static List<String> getProviders() {
    final user = _auth.currentUser;
    if (user == null) return [];

    final providers = user.providerData.map((p) => p.providerId).toList();
    print("🧠 PROVIDERS -> $providers");
    return providers;
  }
}
