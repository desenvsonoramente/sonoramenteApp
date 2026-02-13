import 'dart:async';
import 'dart:io' show Platform;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:in_app_purchase/in_app_purchase.dart';

class InAppPurchaseService {
  final InAppPurchase _iap = InAppPurchase.instance;
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;

  /// ⚠️ Ajuste a região para a MESMA onde sua function `claimPurchase` foi deployada
  /// Ex.: 'us-central1' (mais comum)
  final FirebaseFunctions _functions =
      FirebaseFunctions.instanceFor(region: 'us-central1');

  StreamSubscription<List<PurchaseDetails>>? _subscription;
  bool _initialized = false;

  /// PLANO BÁSICO (compra única)
  static const String basicProductId = 'pacote_premium';

  /// ADDONS (futuro) — mantenha apenas se existirem na Play Console
  static const Set<String> addonProductIds = {
    'addon_maternidade',
    'addon_luto',
    'addon_ansiedade',
    'addon_foco',
  };

  final StreamController<String> _successController =
      StreamController<String>.broadcast();
  final StreamController<String> _errorController =
      StreamController<String>.broadcast();

  Stream<String> get onSuccess => _successController.stream;
  Stream<String> get onError => _errorController.stream;

  // ================= INIT =================

  Future<void> initialize() async {
    if (_initialized) return;
    _initialized = true;

    final available = await _iap.isAvailable();
    if (!available) {
      _errorController.add('Compras indisponíveis neste dispositivo.');
      return;
    }

    _subscription = _iap.purchaseStream.listen(
      _onPurchaseUpdate,
      onError: (e) {
        _errorController.add('Erro inesperado ao processar pagamento.');
      },
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

  Future<List<ProductDetails>> loadProducts({bool includeAddons = true}) async {
    final ids = <String>{
      basicProductId,
      if (includeAddons) ...addonProductIds,
    };

    final response = await _iap.queryProductDetails(ids);

    // Logs úteis para diagnosticar produto não encontrado / erro de store
    // ignore: avoid_print
    print('🧾 IAP query error: ${response.error}');
    // ignore: avoid_print
    print('🧾 IAP notFoundIDs: ${response.notFoundIDs}');
    // ignore: avoid_print
    print(
      '🧾 IAP found: ${response.productDetails.map((p) => p.id).toList()}',
    );

    if (response.error != null) {
      _errorController.add('Erro ao carregar produtos: ${response.error}');
      return [];
    }

    // Se nem o básico aparecer, normalmente é:
    // - app não instalado pela Play
    // - conta não é testadora
    // - produto não está ativo / ainda não propagou
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
        // Opcional: você pode disparar UI de "processando"
        continue;
      }

      if (purchase.status == PurchaseStatus.purchased ||
          purchase.status == PurchaseStatus.restored) {
        final claimed = await _claimPurchase(purchase);

        if (purchase.pendingCompletePurchase) {
          await _iap.completePurchase(purchase);
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

      // ✅ Plataforma correta (android/ios) — NÃO use verificationData.source aqui
      final platform = Platform.isAndroid ? 'android' : 'ios';

      final result = await callable.call({
        'productId': purchase.productID,
        'purchaseToken': purchase.verificationData.serverVerificationData,
        'platform': platform,
      });

      final data = result.data;
      return data != null && data is Map && data['success'] == true;
    } catch (e) {
      _errorController.add('Falha ao validar a compra.');
      // ignore: avoid_print
      print('❌ claimPurchase error: $e');
      return false;
    }
  }
}
