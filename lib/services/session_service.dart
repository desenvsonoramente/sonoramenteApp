import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_functions/cloud_functions.dart';

class SessionService {
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final FirebaseFunctions _functions = FirebaseFunctions.instance;

  /// Registra a sessão no backend e invalida sessões antigas
  Future<void> registerSession({required String deviceId}) async {
    final user = _auth.currentUser;
    if (user == null) {
      throw Exception('Usuário não autenticado');
    }

    final callable = _functions.httpsCallable('registerSession');

    await callable.call({
      'deviceId': deviceId,
    });

    // força refresh do token após revogar tokens antigos
    await user.getIdToken(true);
  }

  /// Valida se a sessão atual é válida (custom claim)
  Future<void> validateSession() async {
    final user = _auth.currentUser;
    if (user == null) {
      throw Exception('Usuário não autenticado');
    }

    final token = await user.getIdTokenResult(true);
    final sessionValid = token.claims?['sessionValid'];

    if (sessionValid != true) {
      throw Exception('Sessão inválida ou expirada');
    }
  }
}