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

  final Set<String> _claimInProgressOrDoneTokens = <String>{};

  String? _cachedPackageName;

  static const String basicProductId = 'pacote_premium';

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
      basicProductId,
      if (includeAddons) ...addonProductIds,
    };

    final response = await _iap.queryProductDetails(ids);

    if (response.error != null) {
      _errorController.add('Erro ao carregar produtos: ${response.error}');
      return [];
    }

    if (!response.productDetails.any((p) => p.id == basicProductId)) {
      _errorController.add(
        'Produto "$basicProductId" não retornou da Play Store. '
        'Verifique instalação pela loja e conta testadora.',
      );
    }

    return response.productDetails;
  }

  // ================= USER =================

  Future<Map<String, dynamic>> loadUserAccess() async {
    final uid = _auth.currentUser?.uid;
    if (uid == null) return {};

    final snap = await _firestore.collection('users').doc(uid).get();
    return snap.data() ?? {};
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

        if (_claimInProgressOrDoneTokens.contains(token)) {
          if (purchase.pendingCompletePurchase) {
            await _iap.completePurchase(purchase);
          }
          continue;
        }

        _claimInProgressOrDoneTokens.add(token);

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
    final uid = _auth.currentUser?.uid;
    if (uid == null) return false;

    try {
      final callable = _functions.httpsCallable('claimPurchase');

      final token = purchase.verificationData.serverVerificationData;

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

      return ok;
    } on FirebaseFunctionsException catch (e) {
      final msg = (e.message == null || e.message!.isEmpty)
          ? 'Falha ao validar a compra.'
          : e.message!;

      _errorController.add(msg);
      return false;
    } catch (_) {
      _errorController.add('Falha ao validar a compra.');
      return false;
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
