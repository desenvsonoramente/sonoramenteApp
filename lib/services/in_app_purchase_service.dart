import 'dart:async';
import 'dart:io' show Platform;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:in_app_purchase/in_app_purchase.dart';
import 'package:package_info_plus/package_info_plus.dart';

class InAppPurchaseService {
  final InAppPurchase _iap = InAppPurchase.instance;
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;

  final FirebaseFunctions _functions =
      FirebaseFunctions.instanceFor(region: 'us-central1');

  StreamSubscription<List<PurchaseDetails>>? _subscription;
  bool _initialized = false;

  bool _availabilityChecked = false;
  bool _isAvailableCached = false;

  /// ✅ Evita revalidar o mesmo token várias vezes na mesma sessão
  final Set<String> _claimInProgressOrDoneTokens = <String>{};

  /// ✅ Dedup extra (algumas lojas podem trocar serverVerificationData em restore)
  final Set<String> _claimInProgressOrDonePurchaseIds = <String>{};

  /// ✅ Cache do packageName (Android)
  String? _cachedPackageName;

  /// SKU pago principal na loja.
  /// Observação: Mesmo que o ID seja "pacote_premium", o backend pode liberar basePlan="basico"
  /// conforme sua regra de negócio (requiredBase="basico").
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

  // ================= AVAILABILITY =================

  Future<bool> checkAvailability() async {
    final available = await _iap.isAvailable();
    _availabilityChecked = true;
    _isAvailableCached = available;
    return available;
  }

  bool get isAvailableCached =>
      _availabilityChecked ? _isAvailableCached : false;

  // ================= INIT =================

  Future<void> initialize() async {
    if (_initialized) return;
    _initialized = true;

    if (!_availabilityChecked) {
      await checkAvailability();
    }

    if (!_isAvailableCached) {
      _errorController.add('Compras indisponíveis neste dispositivo.');
      return;
    }

    _subscription = _iap.purchaseStream.listen(
      _onPurchaseUpdate,
      onError: (_) {
        _errorController.add('Erro inesperado ao processar pagamento.');
      },
      cancelOnError: false,
    );
  }

  void dispose() {
    _subscription?.cancel();
    _subscription = null;
    _initialized = false;

    _successController.close();
    _errorController.close();
  }

  // ================= PRODUCTS =================

  Future<List<ProductDetails>> loadProducts({
    bool includeAddons = includeAddonsByDefault,
  }) async {
    final ids = <String>{
      paidBaseProductId,
      if (includeAddons) ...addonProductIds,
    };

    final response = await _iap.queryProductDetails(ids);

    if (response.error != null) {
      _errorController.add('Erro ao carregar produtos: ${response.error}');
      return [];
    }

    if (!response.productDetails.any((p) => p.id == paidBaseProductId)) {
      _errorController.add(
        'Produto "$paidBaseProductId" não retornou da loja. '
        'Verifique se o app foi instalado pela App Store/Play Store e se o produto está aprovado.',
      );
    }

    return response.productDetails;
  }

  // ================= USER =================

  Future<Map<String, dynamic>> loadUserAccess() async {
    final uid = _auth.currentUser?.uid;
    if (uid == null) return {};

    try {
      final snap = await _firestore.collection('users').doc(uid).get();
      return snap.data() ?? {};
    } on FirebaseException catch (e) {
      // ✅ Produção: não crasha se App Check / regras bloquearem.
      if (e.code == 'permission-denied') {
        _errorController.add(
          'Não foi possível validar seu acesso. '
          'Atualize o app pela loja oficial e tente novamente.',
        );
        return {};
      }
      rethrow;
    }
  }

  // ================= PURCHASE =================

  Future<void> buy(ProductDetails product) async {
    if (!_availabilityChecked) {
      await checkAvailability();
    }
    if (!_isAvailableCached) {
      _errorController.add('Compras indisponíveis neste dispositivo.');
      return;
    }

    final purchaseParam = PurchaseParam(productDetails: product);
    await _iap.buyNonConsumable(purchaseParam: purchaseParam);
  }

  Future<void> restorePurchases() async {
    await _iap.restorePurchases();
  }

  // ================= STREAM =================

  Future<void> _onPurchaseUpdate(List<PurchaseDetails> purchases) async {
    for (final purchase in purchases) {
      if (purchase.status == PurchaseStatus.pending) {
        continue;
      }

      if (purchase.status == PurchaseStatus.purchased ||
          purchase.status == PurchaseStatus.restored) {
        final token = purchase.verificationData.serverVerificationData;
        final purchaseId = (purchase.purchaseID ?? '').trim();

        // ✅ Dedup por purchaseID quando existir
        if (purchaseId.isNotEmpty &&
            _claimInProgressOrDonePurchaseIds.contains(purchaseId)) {
          if (purchase.pendingCompletePurchase) {
            await _iap.completePurchase(purchase);
          }
          continue;
        }

        // ✅ Dedup por token
        if (token.isNotEmpty && _claimInProgressOrDoneTokens.contains(token)) {
          if (purchase.pendingCompletePurchase) {
            await _iap.completePurchase(purchase);
          }
          continue;
        }

        if (purchaseId.isNotEmpty) {
          _claimInProgressOrDonePurchaseIds.add(purchaseId);
        }
        if (token.isNotEmpty) {
          _claimInProgressOrDoneTokens.add(token);
        }

        bool claimed = false;
        try {
          claimed = await _claimPurchase(purchase);
        } finally {
          if (purchase.pendingCompletePurchase) {
            await _iap.completePurchase(purchase);
          }
        }

        if (claimed) {
          _successController.add(
            purchase.status == PurchaseStatus.restored
                ? 'Compra restaurada com sucesso!'
                : 'Compra realizada com sucesso!',
          );
        } else {
          _errorController.add('Falha ao validar a compra.');
        }
      } else if (purchase.status == PurchaseStatus.canceled) {
        _errorController.add('Pagamento cancelado.');
      } else if (purchase.status == PurchaseStatus.error) {
        _errorController.add(
          purchase.error?.message ?? 'Erro ao processar pagamento.',
        );
      }
    }
  }

  // ================= CLAIM (BACKEND) =================

  Future<bool> _claimPurchase(PurchaseDetails purchase) async {
    final user = _auth.currentUser;
    if (user == null) return false;

    final token = purchase.verificationData.serverVerificationData;
    if (token.isEmpty) {
      _errorController.add('Não foi possível validar a compra (token inválido).');
      return false;
    }

    try {
      final callable = _functions.httpsCallable('claimPurchase');

      final String? packageName =
          Platform.isAndroid ? await _getAndroidPackageName() : null;

      final payload = <String, dynamic>{
        'productId': purchase.productID,
        'purchaseToken': token,
        if (packageName != null) 'packageName': packageName,
      };

      final result = await callable.call(payload);

      final data = result.data;
      final ok = data != null && data is Map && data['success'] == true;

      if (!ok) {
        _errorController.add('Não foi possível validar a compra.');
        return false;
      }

      // ✅ Atualizar token para puxar claims novas (basePlan, sessionValid, addons)
      await _refreshIdTokenClaims();

      return true;
    } on FirebaseFunctionsException catch (e) {
      _errorController.add(_mapFunctionsErrorToUserMessage(e));
      return false;
    } on FirebaseException catch (_) {
      _errorController.add('Falha ao validar a compra. Tente novamente.');
      return false;
    } catch (_) {
      _errorController.add('Falha ao validar a compra. Tente novamente.');
      return false;
    }
  }

  Future<void> _refreshIdTokenClaims() async {
    final user = _auth.currentUser;
    if (user == null) return;

    await user.getIdToken(true);
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

  // ================= ANDROID PACKAGE NAME =================

  Future<String> _getAndroidPackageName() async {
    if (_cachedPackageName != null && _cachedPackageName!.isNotEmpty) {
      return _cachedPackageName!;
    }

    final info = await PackageInfo.fromPlatform();
    _cachedPackageName = info.packageName;
    return _cachedPackageName!;
  }
}