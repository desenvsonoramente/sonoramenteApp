import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import 'package:firebase_app_check/firebase_app_check.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:screen_protector/screen_protector.dart';

import 'components/session_guard.dart';
import 'widgets/auth_gate.dart';

void _bootLog(String msg) {
  // ignore: avoid_print
  print('🚀 [BOOT] $msg');
}

bool _appCheckActivated = false;

Future<void> _logBootContext(
  String where, {
  bool includeAppCheckToken = true,
}) async {
  try {
    final app = Firebase.app();
    final opts = app.options;

    _bootLog(
      '[$where] Firebase.app | name=${app.name} projectId=${opts.projectId} appId=${opts.appId}',
    );

    try {
      final info = await PackageInfo.fromPlatform();
      _bootLog(
        '[$where] PackageInfo | packageName=${info.packageName} version=${info.version}+${info.buildNumber}',
      );
    } catch (e) {
      _bootLog('[$where] PackageInfo error | $e');
    }

    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      _bootLog('[$where] Auth | currentUser=null');
    } else {
      _bootLog(
        '[$where] Auth | uid=${user.uid} isAnonymous=${user.isAnonymous} providers=${user.providerData.map((e) => e.providerId).toList()}',
      );
      try {
        final r = await user.getIdTokenResult(true);
        _bootLog(
          '[$where] Auth | getIdTokenResult ok | signInProvider=${r.signInProvider} claimsKeys=${(r.claims ?? {}).keys.toList()}',
        );
      } catch (e) {
        _bootLog('[$where] Auth | getIdTokenResult error | $e');
      }
    }

    // ✅ Só tenta ler token se AppCheck já foi ativado (senão só polui o log)
    if (includeAppCheckToken && _appCheckActivated) {
      try {
        final t = await FirebaseAppCheck.instance.getToken(true);
        final masked =
            (t == null || t.isEmpty) ? '(null/vazio)' : '***(${t.length})';
        _bootLog('[$where] AppCheck | token=$masked');
      } catch (e) {
        _bootLog('[$where] AppCheck | getToken error | $e');
      }
    } else {
      _bootLog('[$where] AppCheck | skipped (activated=$_appCheckActivated)');
    }
  } catch (e) {
    _bootLog('[$where] context error | $e');
  }
}

Future<void> _initAppCheck() async {
  if (!Platform.isAndroid) {
    _bootLog('_initAppCheck() skip | platform=${Platform.operatingSystem}');
    return;
  }

  _bootLog('_initAppCheck() start | android | release=$kReleaseMode');

  try {
    // ✅ Em RELEASE: Play Integrity
    // ✅ Em DEBUG/PROFILE: Debug Provider
    await FirebaseAppCheck.instance.activate(
      androidProvider:
          kReleaseMode ? AndroidProvider.playIntegrity : AndroidProvider.debug,
    );

    _appCheckActivated = true;

    // ✅ auto refresh
    await FirebaseAppCheck.instance.setTokenAutoRefreshEnabled(true);

    _bootLog(
      '_initAppCheck() ok | provider=${kReleaseMode ? 'playIntegrity' : 'debug'}',
    );

    // ✅ loga token só depois do activate
    await _logBootContext('afterAppCheckActivate', includeAppCheckToken: true);

    if (!kReleaseMode) {
      _bootLog(
        'DEBUG NOTE: se App Check estiver ENFORCED no Console, '
        'você precisa registrar o DEBUG TOKEN do device no Firebase App Check '
        '(senão o backend vai negar).',
      );
    }
  } catch (e) {
    _bootLog('_initAppCheck() FAILED | $e');
    _appCheckActivated = false;
  }
}

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  _bootLog(
    'main() start | release=$kReleaseMode platform=${Platform.operatingSystem}',
  );

  try {
    await Firebase.initializeApp();
    _bootLog('Firebase.initializeApp() ok');
  } catch (e) {
    _bootLog('Firebase.initializeApp() FAILED | $e');
    rethrow;
  }

  // ✅ Contexto SEM AppCheck token ainda (porque ainda não ativou)
  await _logBootContext('afterFirebaseInit', includeAppCheckToken: false);

  // ✅ App Check (Android): debug em dev, playIntegrity em release
  await _initAppCheck();

  runApp(const MyApp());
}

class MyApp extends StatefulWidget {
  const MyApp({super.key});

  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> {
  static const Color appBgColor = Color(0xFFA8C3B0);

  @override
  void initState() {
    super.initState();
    _initScreenProtection();
  }

  Future<void> _initScreenProtection() async {
    try {
      await ScreenProtector.preventScreenshotOn();
      await ScreenProtector.protectDataLeakageOn();
    } catch (e) {
      _bootLog('ScreenProtector ignored/failed | $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: false,
        scaffoldBackgroundColor: appBgColor,
        appBarTheme: const AppBarTheme(
          backgroundColor: appBgColor,
          elevation: 0,
          foregroundColor: Colors.black,
          centerTitle: true,
        ),
        colorScheme: ColorScheme.fromSeed(
          seedColor: appBgColor,
          surface: appBgColor,
        ),
      ),
      builder: (context, child) {
        return SessionGuard(
          child: child ?? const SizedBox.shrink(),
        );
      },
      home: const AuthGate(),
    );
  }
}