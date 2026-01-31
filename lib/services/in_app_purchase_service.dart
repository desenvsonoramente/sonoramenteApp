import 'dart:async';
import 'package:in_app_purchase/in_app_purchase.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

class InAppPurchaseService {
  final InAppPurchase _iap = InAppPurchase.instance;
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;

  StreamSubscription<List<PurchaseDetails>>? _subscription;
  bool _initialized = false;

  static const String basicId = 'plano_basico';

  static const Map<String, String> addonMap = {
    'addon_maternidade': 'maternidade',
    'addon_luto': 'luto',
    'addon_ansiedade': 'ansiedade',
    'addon_foco': 'foco',
  };

  final StreamController<String> _successController =
      StreamController.broadcast();
  final StreamController<String> _errorController =
      StreamController.broadcast();

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
      basicId,
      ...addonMap.keys,
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
        final delivered = await _deliverPurchase(purchase);

        if (purchase.pendingCompletePurchase) {
          await _iap.completePurchase(purchase);
        }

        if (delivered) {
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

  // ================= DELIVERY =================

  Future<bool> _deliverPurchase(PurchaseDetails purchase) async {
    final uid = _auth.currentUser?.uid;
    if (uid == null) return false;

    final ref = _firestore.collection('users').doc(uid);
    final snap = await ref.get();
    final data = snap.data() ?? {};

    // PLANO BÁSICO (COMPRA ÚNICA)
    if (purchase.productID == basicId) {
      if (data['basePlan'] == 'basico') {
        return false; // já entregue
      }

      await ref.set(
        {'basePlan': 'basico'},
        SetOptions(merge: true),
      );
      return true;
    }

    // ADDONS
    if (addonMap.containsKey(purchase.productID)) {
      final addons = List<String>.from(data['addons'] ?? []);

      if (addons.contains(addonMap[purchase.productID])) {
        return false;
      }

      await ref.set({
        'addons': FieldValue.arrayUnion(
          [addonMap[purchase.productID]],
        ),
      }, SetOptions(merge: true));

      return true;
    }

    return false;
  }
}
