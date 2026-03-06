import 'dart:async';
import 'dart:io' show Platform;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_app_check/firebase_app_check.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:in_app_purchase/in_app_purchase.dart';
import 'package:installer_info/installer_info.dart';
import 'package:package_info_plus/package_info_plus.dart';

import 'purchase_guard.dart';

class InAppPurchaseService {
  // ================= CORE =================

  static const String _tag = 'IAP';

  final InAppPurchase _iap = InAppPurchase.instance;
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;

  /// ✅ Região real do deploy do callable.
  /// Obs: não é “config”, é “onde foi deployado”.
  static const String _functionsRegion = 'us-central1';

  /// ✅ NÃO deixar Functions como `final` fixo criado cedo.
  /// Getter lazy evita “capturar” um estado ruim (AppCheck/Auth ainda não prontos).
  FirebaseFunctions get _functions => FirebaseFunctions.instanceFor(
        app: Firebase.app(),
        region: _functionsRegion,
      );

  StreamSubscription<List<PurchaseDetails>>? _subscription;
  bool _initialized = false;

  bool _availabilityChecked = false;
  bool _isAvailableCached = false;

  /// ✅ Dedup / controle de processamento
  final Set<String> _claimInProgressTokens = <String>{};
  final Set<String> _claimDoneTokens = <String>{};

  final Set<String> _claimInProgressPurchaseIds = <String>{};
  final Set<String> _claimDonePurchaseIds = <String>{};

  /// ✅ Cache do packageName (Android)
  String? _cachedPackageName;

  /// ✅ Cache installer info
  InstallerInfo? _cachedInstallerInfo;

  /// ✅ Controla lock/unlock de compra/restore para evitar signOut durante fluxo.
  final PurchaseGuard _guard = PurchaseGuard.instance;

  /// SKU pago principal na loja.
  static const String paidBaseProductId = 'pacote_premium';

  static const Set<String> addonProductIds = {
    'addon_maternidade',
    'addon_luto',
    'addon_ansiedade',
    'addon_foco',
  };

  static const bool includeAddonsByDefault = false;

  final StreamController<String> _successController =
      StreamController<String>.broadcast();
  final StreamController<String> _errorController =
      StreamController<String>.broadcast();

  Stream<String> get onSuccess => _successController.stream;
  Stream<String> get onError => _errorController.stream;

  // ================= LOG HELPERS =================

  void _log(String msg) {
    // ignore: avoid_print
    print('📦 [$_tag] $msg');
  }

  void _warn(String msg) {
    // ignore: avoid_print
    print('⚠️ [$_tag] $msg');
  }

  void _err(String msg) {
    // ignore: avoid_print
    print('❌ [$_tag] $msg');
  }

  String _maskToken(String token) {
    final t = token.trim();
    if (t.isEmpty) return '(vazio)';
    if (t.length <= 10) return '***(${t.length})';
    return '***${t.substring(t.length - 6)}(${t.length})';
  }

  String _maskPurchaseId(String id) {
    final p = id.trim();
    if (p.isEmpty) return '(vazio)';
    if (p.length <= 8) return '***';
    return '${p.substring(0, 4)}…${p.substring(p.length - 3)}';
  }

  String _u() => _auth.currentUser?.uid ?? '(sem uid)';

  String _platform() =>
      Platform.isAndroid ? 'Android' : (Platform.isIOS ? 'iOS' : 'Outro');

  String _purchaseKey(PurchaseDetails p) {
    final pid = (p.purchaseID ?? '').trim();
    if (pid.isNotEmpty) return 'pid:$pid';
    final token = p.verificationData.serverVerificationData.trim();
    if (token.isNotEmpty) return 'tok:$token';
    return 'prod:${p.productID}:${p.transactionDate ?? ''}';
  }

  // ================= 🔥 PRINT ANTES DA COMPRA =================
  // (adição pedida: print do usuário logado imediatamente antes do momento da compra)

  Future<void> _logAuthSnapshotBeforePurchase({
    required String where,
    required String productId,
  }) async {
    final user = _auth.currentUser;

    _log('[$where] PRE-BUY SNAPSHOT | productId=$productId');

    if (user == null) {
      _warn('[$where] PRE-BUY | currentUser=null');
      return;
    }

    _log('[$where] PRE-BUY | uid=${user.uid} isAnonymous=${user.isAnonymous} '
        'email=${user.email ?? '(null)'} '
        'providers=${user.providerData.map((e) => e.providerId).toList()}');

    try {
      // força refresh do token e loga dados úteis
      final r = await user.getIdTokenResult(true);
      final claims = r.claims ?? {};
      _log('[$where] PRE-BUY | getIdTokenResult ok | '
          'signInProvider=${r.signInProvider} '
          'claimsKeys=${claims.keys.toList()} '
          'issuedAt=${r.issuedAtTime} '
          'expiration=${r.expirationTime}');
    } catch (e) {
      _err('[$where] PRE-BUY | getIdTokenResult error | $e');
    }

    try {
      final t = await FirebaseAppCheck.instance.getToken(true);
      _log('[$where] PRE-BUY | AppCheck token=${_maskToken(t ?? '')}');
    } catch (e) {
      _warn('[$where] PRE-BUY | AppCheck getToken failed | $e');
    }
  }

  // ================= DIAGNOSTICS =================

  Future<void> _logFirebaseContext({required String where}) async {
    final app = Firebase.app();
    final opts = app.options;

    _log('[$where] Firebase.app | name=${app.name} '
        'projectId=${opts.projectId} appId=${opts.appId} '
        'apiKey=${opts.apiKey.isNotEmpty ? '(ok)' : '(vazio)'} '
        'storageBucket=${opts.storageBucket}');

    // Region das functions (pra ficar explícito no log)
    _log('[$where] Functions | region=$_functionsRegion');
    _warnIfRegionMismatch(where: where);

    // Package info (ajuda MUITO a detectar build/sabor/variante errada)
    try {
      final pi = await PackageInfo.fromPlatform();
      _log('[$where] PackageInfo | '
          'appName="${pi.appName}" '
          'packageName=${pi.packageName} '
          'version=${pi.version}+${pi.buildNumber}');
    } catch (e) {
      _warn('[$where] PackageInfo | failed | $e');
    }

    // Installer source (Play Store vs sideload)
    await _logInstallerInfo(where: where);

    final user = _auth.currentUser;
    if (user == null) {
      _warn('[$where] Auth | currentUser=null');
      return;
    }

    _log('[$where] Auth | uid=${user.uid} isAnonymous=${user.isAnonymous} '
        'email=${user.email ?? '(null)'} '
        'providers=${user.providerData.map((e) => e.providerId).toList()}');

    try {
      final idTokenResult = await user.getIdTokenResult(true);
      final claims = idTokenResult.claims ?? {};
      _log('[$where] Auth | getIdTokenResult ok | '
          'signInProvider=${idTokenResult.signInProvider} '
          'claimsKeys=${claims.keys.toList()}');
    } catch (e) {
      _err('[$where] Auth | getIdTokenResult error | $e');
    }

    // App Check (se estiver configurado no app)
    try {
      final t = await FirebaseAppCheck.instance.getToken(true);
      _log('[$where] AppCheck | token=${_maskToken(t ?? '')}');
    } catch (e) {
      _warn('[$where] AppCheck | getToken failed | $e');
    }
  }

  void _warnIfRegionMismatch({required String where}) {
    _warn('[$where] RegionCheck | '
        'Se você quer usar outra região (ex: southamerica-east1), '
        'precisa redeployar as functions nessa região e atualizar o app.');
  }

  /// ✅ "À prova de tudo":
  Future<void> _logInstallerInfo({required String where}) async {
    if (!Platform.isAndroid && !Platform.isIOS) {
      _log('[$where] InstallerInfo | n/a (platform=${_platform()})');
      return;
    }

    try {
      _cachedInstallerInfo ??= await getInstallerInfo();

      final info = _cachedInstallerInfo;
      if (info == null) {
        _warn('[$where] InstallerInfo | info=null (plugin returned null)');
        return;
      }

      final installerName = info.installerName;
      final installerEnumName = info.installer?.name ?? '(null)';

      _log('[$where] InstallerInfo | '
          'installerName=$installerName '
          'installer=$installerEnumName');
    } catch (e) {
      _warn('[$where] InstallerInfo | failed | $e');
    }
  }

  // ================= AVAILABILITY =================

  Future<bool> checkAvailability() async {
    _log('checkAvailability() start | platform=${_platform()} uid=${_u()}');

    try {
      final available = await _iap.isAvailable();
      _availabilityChecked = true;
      _isAvailableCached = available;

      _log('checkAvailability() ok | isAvailable=$available');
      return available;
    } catch (e) {
      _availabilityChecked = true;
      _isAvailableCached = false;
      _err('checkAvailability() error | $e');
      return false;
    }
  }

  bool get isAvailableCached => _availabilityChecked ? _isAvailableCached : false;

  // ================= INIT =================

  Future<void> initialize() async {
    if (_initialized) {
      _log('initialize() skip | already initialized');
      return;
    }

    _initialized = true;
    _log('initialize() start | platform=${_platform()} uid=${_u()}');
    await _logFirebaseContext(where: 'initialize');

    if (!_availabilityChecked) {
      await checkAvailability();
    }

    if (!_isAvailableCached) {
      _warn('initialize() blocked | purchases not available');
      _errorController.add('Compras indisponíveis neste dispositivo.');
      return;
    }

    _subscription = _iap.purchaseStream.listen(
      _onPurchaseUpdate,
      onError: (err) {
        _err('purchaseStream onError | $err');
        _errorController.add('Erro inesperado ao processar pagamento.');
        _guard.unlock(reason: 'purchaseStream onError');
      },
      cancelOnError: false,
    );

    _log('initialize() ok | purchaseStream subscribed');
  }

  void dispose() {
    _log('dispose() start');

    _subscription?.cancel();
    _subscription = null;
    _initialized = false;

    _guard.unlock(reason: 'dispose');

    if (!_successController.isClosed) _successController.close();
    if (!_errorController.isClosed) _errorController.close();

    _log('dispose() done');
  }

  // ================= PRODUCTS =================

  Future<List<ProductDetails>> loadProducts({
    bool includeAddons = includeAddonsByDefault,
  }) async {
    if (!_initialized) {
      _warn('loadProducts() called before initialize() | auto-initializing');
      await initialize();
    }

    final ids = <String>{
      paidBaseProductId,
      if (includeAddons) ...addonProductIds,
    };

    _log(
      'loadProducts() start | ids=${ids.toList()} includeAddons=$includeAddons isAvailableCached=$isAvailableCached',
    );

    try {
      final response = await _iap.queryProductDetails(ids);

      if (response.error != null) {
        _err('loadProducts() query error | ${response.error}');
        _errorController.add('Erro ao carregar produtos: ${response.error}');
        return [];
      }

      if (response.productDetails.isEmpty) {
        _warn('loadProducts() empty result | notFound=${response.notFoundIDs}');
      } else {
        _log(
          'loadProducts() ok | returned=${response.productDetails.length} notFound=${response.notFoundIDs}',
        );
        for (final p in response.productDetails) {
          _log(
            'Product | id=${p.id} title="${p.title}" price=${p.price} rawPrice=${p.rawPrice} currency=${p.currencyCode}',
          );
        }
      }

      if (!response.productDetails.any((p) => p.id == paidBaseProductId)) {
        _warn(
          'loadProducts() missing paidBaseProductId="$paidBaseProductId" | notFound=${response.notFoundIDs}',
        );
        _errorController.add(
          'Produto "$paidBaseProductId" não retornou da loja. '
          'Verifique se o app foi instalado pela App Store/Play Store e se o produto está aprovado.',
        );
      }

      return response.productDetails;
    } catch (e) {
      _err('loadProducts() exception | $e');
      _errorController.add('Erro ao carregar produtos. Tente novamente.');
      return [];
    }
  }

  // ✅ Compat: método antigo que ainda pode estar sendo chamado em algum lugar
  Future<List<ProductDetails>> loadProduts({
    bool includeAddons = includeAddonsByDefault,
  }) {
    return loadProducts(includeAddons: includeAddons);
  }

  // ================= USER =================

  Future<Map<String, dynamic>> loadUserAccess() async {
    final uid = _auth.currentUser?.uid;
    _log('loadUserAccess() start | uid=${uid ?? '(null)'}');

    if (uid == null) return {};

    try {
      final snap = await _firestore.collection('users').doc(uid).get();
      final data = snap.data() ?? {};
      _log('loadUserAccess() ok | keys=${data.keys.toList()}');
      return data;
    } on FirebaseException catch (e) {
      _err('loadUserAccess() FirebaseException | code=${e.code} msg=${e.message}');
      if (e.code == 'permission-denied') {
        _errorController.add(
          'Não foi possível validar seu acesso. '
          'Atualize o app pela loja oficial e tente novamente.',
        );
        return {};
      }
      rethrow;
    } catch (e) {
      _err('loadUserAccess() exception | $e');
      rethrow;
    }
  }

  // ================= PURCHASE =================

  Future<void> buy(ProductDetails product) async {
    if (!_initialized) {
      _warn('buy() called before initialize() | auto-initializing');
      await initialize();
    }

    if (!_availabilityChecked) {
      await checkAvailability();
    }

    _log(
      'buy() start | productId=${product.id} platform=${_platform()} uid=${_u()} isAvailableCached=$isAvailableCached',
    );

    if (!_isAvailableCached) {
      _warn('buy() blocked | purchases not available');
      _errorController.add('Compras indisponíveis neste dispositivo.');
      return;
    }

    if (_auth.currentUser == null) {
      _warn('buy() blocked | user null');
      _errorController.add('Faça login para comprar e validar a assinatura.');
      return;
    }

    _guard.lock(reason: 'buy:${product.id}');

    try {
      await _logAuthSnapshotBeforePurchase(
        where: 'buy:beforeStoreCall',
        productId: product.id,
      );

      final purchaseParam = PurchaseParam(productDetails: product);
      await _iap.buyNonConsumable(purchaseParam: purchaseParam);
      _log('buy() call dispatched | waiting purchaseStream...');
    } catch (e) {
      _err('buy() exception | $e');
      _errorController.add('Não foi possível iniciar a compra. Tente novamente.');
      _guard.unlock(reason: 'buy exception');
    }
  }

  Future<void> restorePurchases() async {
    if (!_initialized) {
      _warn('restorePurchases() called before initialize() | auto-initializing');
      await initialize();
    }

    if (_auth.currentUser == null) {
      _warn('restorePurchases() blocked | user null');
      _errorController.add('Faça login para restaurar e validar compras.');
      return;
    }

    _log('restorePurchases() start | uid=${_u()}');
    _guard.lock(reason: 'restorePurchases');

    try {
      await _iap.restorePurchases();
      _log('restorePurchases() call dispatched | waiting purchaseStream...');
    } catch (e) {
      _err('restorePurchases() exception | $e');
      _errorController.add('Não foi possível restaurar compras. Tente novamente.');
      _guard.unlock(reason: 'restorePurchases exception');
    }
  }

  // ================= STREAM =================

  Future<void> _onPurchaseUpdate(List<PurchaseDetails> purchases) async {
    _log('_onPurchaseUpdate() | events=${purchases.length} uid=${_u()}');

    _guard.lock(reason: 'purchaseStream batch');

    try {
      for (final purchase in purchases) {
        final purchaseId = (purchase.purchaseID ?? '').trim();
        final token = purchase.verificationData.serverVerificationData.trim();

        _log(
          'PurchaseEvent | status=${purchase.status} '
          'productId=${purchase.productID} '
          'purchaseId=${_maskPurchaseId(purchaseId)} '
          'token=${_maskToken(token)} '
          'verificationSource=${purchase.verificationData.source} '
          'transactionDate=${purchase.transactionDate ?? '(null)'} '
          'pendingCompletePurchase=${purchase.pendingCompletePurchase} '
          'error=${purchase.error?.code}/${purchase.error?.message}',
        );

        if (purchase.status == PurchaseStatus.pending) {
          _log('Purchase pending | productId=${purchase.productID}');
          continue;
        }

        if (purchase.status == PurchaseStatus.purchased ||
            purchase.status == PurchaseStatus.restored) {
          if (purchaseId.isNotEmpty &&
              _claimDonePurchaseIds.contains(purchaseId)) {
            _warn(
              'Dedup skip DONE (purchaseId) | purchaseId=${_maskPurchaseId(purchaseId)}',
            );
            if (purchase.pendingCompletePurchase) {
              try {
                await _iap.completePurchase(purchase);
                _log('completePurchase() ok | dedup DONE (purchaseId)');
              } catch (e) {
                _err('completePurchase() error | dedup DONE (purchaseId) | $e');
              }
            }
            continue;
          }

          if (token.isNotEmpty && _claimDoneTokens.contains(token)) {
            _warn('Dedup skip DONE (token) | token=${_maskToken(token)}');
            if (purchase.pendingCompletePurchase) {
              try {
                await _iap.completePurchase(purchase);
                _log('completePurchase() ok | dedup DONE (token)');
              } catch (e) {
                _err('completePurchase() error | dedup DONE (token) | $e');
              }
            }
            continue;
          }

          if (purchaseId.isNotEmpty &&
              _claimInProgressPurchaseIds.contains(purchaseId)) {
            _warn(
              'Dedup skip IN-PROGRESS (purchaseId) | purchaseId=${_maskPurchaseId(purchaseId)}',
            );
            continue;
          }

          if (token.isNotEmpty && _claimInProgressTokens.contains(token)) {
            _warn('Dedup skip IN-PROGRESS (token) | token=${_maskToken(token)}');
            continue;
          }

          if (purchaseId.isNotEmpty) _claimInProgressPurchaseIds.add(purchaseId);
          if (token.isNotEmpty) _claimInProgressTokens.add(token);

          bool claimed = false;
          try {
            claimed = await _claimPurchase(purchase);
          } finally {
            if (purchaseId.isNotEmpty) {
              _claimInProgressPurchaseIds.remove(purchaseId);
            }
            if (token.isNotEmpty) _claimInProgressTokens.remove(token);
          }

          if (claimed) {
            if (purchaseId.isNotEmpty) _claimDonePurchaseIds.add(purchaseId);
            if (token.isNotEmpty) _claimDoneTokens.add(token);

            if (purchase.pendingCompletePurchase) {
              try {
                await _iap.completePurchase(purchase);
                _log('completePurchase() ok | after claim');
              } catch (e) {
                _err('completePurchase() error | after claim | $e');
              }
            }

            final msg = purchase.status == PurchaseStatus.restored
                ? 'Compra restaurada com sucesso!'
                : 'Compra realizada com sucesso!';
            _log('Purchase claimed OK | productId=${purchase.productID}');
            _successController.add(msg);
          } else {
            _warn(
              'Purchase claim FAILED (not completing) | productId=${purchase.productID}',
            );
            _errorController.add('Falha ao validar a compra. Tente novamente.');
          }
        } else if (purchase.status == PurchaseStatus.canceled) {
          _warn('Purchase canceled | productId=${purchase.productID}');
          _errorController.add('Pagamento cancelado.');
          if (purchase.pendingCompletePurchase) {
            try {
              await _iap.completePurchase(purchase);
              _log('completePurchase() ok | canceled');
            } catch (e) {
              _err('completePurchase() error | canceled | $e');
            }
          }
        } else if (purchase.status == PurchaseStatus.error) {
          _err(
            'Purchase error | productId=${purchase.productID} '
            'code=${purchase.error?.code} msg=${purchase.error?.message}',
          );
          _errorController.add(
            purchase.error?.message ?? 'Erro ao processar pagamento.',
          );
          if (purchase.pendingCompletePurchase) {
            try {
              await _iap.completePurchase(purchase);
              _log('completePurchase() ok | error');
            } catch (e) {
              _err('completePurchase() error | error | $e');
            }
          }
        } else {
          _warn(
            'Purchase status not handled explicitly | status=${purchase.status}',
          );
        }
      }
    } finally {
      _guard.unlock(reason: 'purchaseStream batch done');
      _guard.unlock(reason: 'safety unlock after batch');
    }
  }

  // ================= CLAIM (BACKEND) =================

  Future<void> _ensureAppCheckToken({required String where}) async {
    try {
      final t = await FirebaseAppCheck.instance.getToken(true);
      _log('[$where] ensureAppCheckToken ok | token=${_maskToken(t ?? '')}');
    } catch (e) {
      _warn('[$where] ensureAppCheckToken failed | $e');
    }
  }

  Future<bool> _claimPurchase(PurchaseDetails purchase) async {
    var user = _auth.currentUser;
    if (user == null) {
      _warn('_claimPurchase() blocked | user null');
      _errorController.add('Você precisa estar logado para validar a compra.');
      return false;
    }

    final rawToken = purchase.verificationData.serverVerificationData;
    final token = rawToken.trim();
    if (token.isEmpty) {
      _warn('_claimPurchase() blocked | empty token');
      _errorController.add('Não foi possível validar a compra (token inválido).');
      return false;
    }

    final key = _purchaseKey(purchase);

    _log(
      '_claimPurchase() start | productId=${purchase.productID} '
      'purchaseId=${_maskPurchaseId(purchase.purchaseID ?? '')} '
      'token=${_maskToken(token)} uid=${_u()} key=$key',
    );

    await _logFirebaseContext(where: '_claimPurchase:before');

    try {
      await user.reload();
      user = _auth.currentUser;
      if (user == null) {
        _warn('_claimPurchase() blocked | user became null after reload');
        _errorController.add('Sessão expirada. Faça login novamente.');
        return false;
      }

      final String? idToken = await user.getIdToken(true);
      await user.getIdTokenResult(true);

      _log(
        '[_claimPurchase:preCall] IDToken snapshot | token=${_maskToken(idToken ?? '')} uid=${user.uid}',
      );

      await _ensureAppCheckToken(where: '_claimPurchase');

      await Future.delayed(const Duration(milliseconds: 350));

      await _logFirebaseContext(where: '_claimPurchase:afterRefresh');

      _log(
        '[_claimPurchase:preCall] Auth snapshot | uid=${user.uid} isAnonymous=${user.isAnonymous} '
        'email=${user.email ?? '(null)'} '
        'providers=${user.providerData.map((e) => e.providerId).toList()}',
      );

      final String? packageName =
          Platform.isAndroid ? await _getAndroidPackageName() : null;

      final payload = <String, dynamic>{
        'productId': purchase.productID,
        'purchaseToken': token,
        if (packageName != null) 'packageName': packageName,
      };

      _log(
        '_claimPurchase() calling function | '
        'region=$_functionsRegion '
        'productId=${purchase.productID} '
        'packageName=${packageName ?? '(n/a)'} '
        'token=${_maskToken(token)} uid=${_u()}',
      );

      _log('_claimPurchase() payload keys=${payload.keys.toList()}');

      final result = await _retryWithBackoff(
        () async {
          final callable = _functions.httpsCallable(
            'claimPurchase',
            options: HttpsCallableOptions(timeout: const Duration(seconds: 60)),
          );
          return callable.call(payload);
        },
        attempts: 3,
        initialDelayMs: 300,
      );

      final data = result.data;
      final ok = data != null && data is Map && data['success'] == true;

      _log(
        '_claimPurchase() function returned | ok=$ok dataType=${data?.runtimeType} '
        'keys=${data is Map ? data.keys.toList() : '(n/a)'}',
      );

      if (!ok) {
        _warn('_claimPurchase() not ok | data=$data');
        _errorController.add('Não foi possível validar a compra.');
        return false;
      }

      await _refreshIdTokenClaims();

      _log('_claimPurchase() ok | claims refreshed');
      return true;
    } on FirebaseFunctionsException catch (e) {
      _err(
        '_claimPurchase() FirebaseFunctionsException | code=${e.code} message=${e.message} details=${e.details}',
      );
      _errorController.add(_mapFunctionsErrorToUserMessage(e));
      return false;
    } on FirebaseException catch (e) {
      _err('_claimPurchase() FirebaseException | code=${e.code} msg=${e.message}');
      _errorController.add('Falha ao validar a compra. Tente novamente.');
      return false;
    } catch (e) {
      _err('_claimPurchase() exception | $e');
      _errorController.add('Falha ao validar a compra. Tente novamente.');
      return false;
    }
  }

  Future<void> _refreshIdTokenClaims() async {
    final user = _auth.currentUser;
    if (user == null) return;

    _log('_refreshIdTokenClaims() start | uid=${_u()}');
    try {
      final r = await user.getIdTokenResult(true);
      final claims = r.claims ?? {};
      _log('_refreshIdTokenClaims() ok | claimsKeys=${claims.keys.toList()}');
    } catch (e) {
      _err('_refreshIdTokenClaims() error | $e');
    }
  }

  String _mapFunctionsErrorToUserMessage(FirebaseFunctionsException e) {
    switch (e.code) {
      case 'failed-precondition':
        return 'Não foi possível validar o app. '
            'Atualize/instale pela loja oficial e tente novamente.';
      case 'permission-denied':
        return 'Ação não permitida. '
            'Atualize/instale pela loja oficial e tente novamente.';
      case 'unauthenticated':
        return 'Sessão expirada. Faça login novamente.';
      case 'resource-exhausted':
        return 'Muitas tentativas. Aguarde alguns minutos e tente novamente.';
      case 'invalid-argument':
        return e.message?.isNotEmpty == true
            ? e.message!
            : 'Dados inválidos. Tente novamente.';
      case 'internal':
      default:
        return e.message?.isNotEmpty == true
            ? e.message!
            : 'Falha ao validar a compra. Tente novamente.';
    }
  }

  // ================= RETRY HELPER =================

  Future<T> _retryWithBackoff<T>(
    Future<T> Function() fn, {
    int attempts = 3,
    int initialDelayMs = 300,
  }) async {
    Object? last;
    var delay = initialDelayMs;

    for (var i = 1; i <= attempts; i++) {
      try {
        return await fn();
      } on FirebaseFunctionsException catch (e) {
        last = e;
        final retryable = e.code == 'unauthenticated' ||
            e.code == 'internal' ||
            e.code == 'unavailable' ||
            e.code == 'deadline-exceeded' ||
            e.code == 'resource-exhausted';

        if (!retryable || i == attempts) rethrow;

        _warn('_retryWithBackoff() retryable functions error | '
            'attempt=$i/$attempts code=${e.code} -> wait ${delay}ms');
      } catch (e) {
        last = e;
        if (i == attempts) rethrow;
        _warn(
          '_retryWithBackoff() exception | attempt=$i/$attempts -> wait ${delay}ms | $e',
        );
      }

      await Future.delayed(Duration(milliseconds: delay));
      delay = (delay * 2).clamp(initialDelayMs, 2000);
    }

    throw last ?? Exception('Retry failed');
  }

  // ================= ANDROID PACKAGE NAME =================

  Future<String> _getAndroidPackageName() async {
    if (_cachedPackageName != null && _cachedPackageName!.isNotEmpty) {
      _log('_getAndroidPackageName() cached | packageName=$_cachedPackageName');
      return _cachedPackageName!;
    }

    _log('_getAndroidPackageName() start');
    final info = await PackageInfo.fromPlatform();
    _cachedPackageName = info.packageName;

    _log('_getAndroidPackageName() ok | packageName=$_cachedPackageName');
    return _cachedPackageName!;
  }
}