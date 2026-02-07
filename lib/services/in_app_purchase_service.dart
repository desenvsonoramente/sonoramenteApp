import 'dart:async';

import 'package:in_app_purchase/in_app_purchase.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';

class InAppPurchaseService {
  final InAppPurchase _iap = InAppPurchase.instance;
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final FirebaseFunctions _functions = FirebaseFunctions.instance;

  StreamSubscription<List<PurchaseDetails>>? _subscription;
  bool _initialized = false;

  /// PLANO BÁSICO (compra única)
  static const String basicProductId = 'pacote_premium';

  /// ADDONS (futuro)
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
      onError: (_) {
        _errorController.add('Erro inesperado ao processar pagamento.');
      },
    );
  }

  void dispose() {
    _subscription?.cancel();
    _successController.close();
    _errorController.close();
    _initialized = false;
  }

  // ================= PRODUCTS =================

  Future<List<ProductDetails>> loadProducts() async {
    final ids = <String>{
      basicProductId,
      ...addonProductIds,
    };

    final response = await _iap.queryProductDetails(ids);

    if (response.error != null) {
      _errorController.add('Erro ao carregar produtos.');
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
        }
      }

      if (purchase.status == PurchaseStatus.canceled) {
        _errorController.add('Pagamento cancelado.');
      }

      if (purchase.status == PurchaseStatus.error) {
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

      final result = await callable.call({
        'productId': purchase.productID,
        'purchaseToken': purchase.verificationData.serverVerificationData,
        'platform': purchase.verificationData.source, // android / ios
      });

      return result.data != null && result.data['success'] == true;
    } catch (e) {
      _errorController.add('Falha ao validar a compra.');
      return false;
    }
  }
}
