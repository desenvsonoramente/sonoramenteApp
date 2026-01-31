import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

class SessionListener {
  static StreamSubscription<DocumentSnapshot>? _sub;

  static void start({
    required String deviceId,
    required void Function() onInvalidSession,
  }) {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    _sub = FirebaseFirestore.instance
        .collection('users')
        .doc(user.uid)
        .snapshots()
        .listen((doc) {
      if (!doc.exists) return;

      final activeDevice = doc.get('deviceIdAtivo');
      if (activeDevice != deviceId) {
        onInvalidSession();
      }
    });
  }

  static void stop() {
    _sub?.cancel();
    _sub = null;
  }
}
