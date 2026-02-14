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

  // ✅ Evita revalidar o mesmo token várias vezes na mesma sessão
  final Set<String> _claimInProgressOrDoneTokens = <String>{};

  // ✅ Cache do packageName (Android)
  String? _cachedPackageName;

  /// PLANO BÁSICO (compra única)
  static const String basicProductId = 'pacote_premium';

  /// ADDONS (futuro)
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

  // ================= LOGGING =================

  void _log(String message, {Object? data}) {
    final now = DateTime.now().toIso8601String();
    // ignore: avoid_print
    if (data == null) {
      print('[$now] 🛒 IAP | $message');
    } else {
      print('[$now] 🛒 IAP | $message | $data');
    }
  }

  // ================= AVAILABILITY =================

  Future<bool> checkAvailability() async {
    final available = await _iap.isAvailable();
    _availabilityChecked = true;
    _isAvailableCached = available;

    _log('checkAvailability()', data: {
      'available': available,
      'platform': Platform.isAndroid ? 'android' : 'ios',
      'uid': _auth.currentUser?.uid,
    });

    return available;
  }

  bool get isAvailableCached =>
      _availabilityChecked ? _isAvailableCached : false;

  // ================= INIT =================

  Future<void> initialize() async {
    if (_initialized) {
      _log('initialize() chamado, mas já estava inicializado.');
      return;
    }
    _initialized = true;

    _log('initialize() start', data: {
      'platform': Platform.isAndroid ? 'android' : 'ios',
      'uid': _auth.currentUser?.uid,
    });

    if (!_availabilityChecked) {
      await checkAvailability();
    }

    if (!_isAvailableCached) {
      _errorController.add('Compras indisponíveis neste dispositivo.');
      _log('Compras indisponíveis (isAvailable=false).');
      return;
    }

    _subscription = _iap.purchaseStream.listen(
      _onPurchaseUpdate,
      onError: (e, st) {
        _log('purchaseStream onError', data: {'error': e.toString()});
        _errorController.add('Erro inesperado ao processar pagamento.');
      },
      cancelOnError: false,
    );

    _log('purchaseStream listener ativo.');
  }

  void dispose() {
    _log('dispose() start');
    _subscription?.cancel();
    _subscription = null;
    _initialized = false;

    _successController.close();
    _errorController.close();
    _log('dispose() end');
  }

  // ================= PRODUCTS =================

  Future<List<ProductDetails>> loadProducts({
    bool includeAddons = includeAddonsByDefault,
  }) async {
    final ids = <String>{
      basicProductId,
      if (includeAddons) ...addonProductIds,
    };

    _log('loadProducts() queryProductDetails start', data: {
      'ids': ids.toList(),
      'includeAddons': includeAddons,
    });

    final response = await _iap.queryProductDetails(ids);

    _log('queryProductDetails response', data: {
      'error': response.error?.toString(),
      'notFoundIDs': response.notFoundIDs,
      'found': response.productDetails.map((p) => p.id).toList(),
    });

    if (response.error != null) {
      _errorController.add('Erro ao carregar produtos: ${response.error}');
      return [];
    }

    if (!response.productDetails.any((p) => p.id == basicProductId)) {
      _errorController.add(
        'Produto "$basicProductId" não retornou da Play Store. '
        'Verifique instalação pela loja e conta testadora.',
      );
      _log('ATENÇÃO: Produto básico não retornou', data: {
        'basicProductId': basicProductId,
        'found': response.productDetails.map((p) => p.id).toList(),
      });
    }

    return response.productDetails;
  }

  // ================= USER =================

  Future<Map<String, dynamic>> loadUserAccess() async {
    final uid = _auth.currentUser?.uid;
    if (uid == null) {
      _log('loadUserAccess(): usuário null');
      return {};
    }

    _log('loadUserAccess() start', data: {'uid': uid});

    final snap = await _firestore.collection('users').doc(uid).get();
    final data = snap.data() ?? {};
    _log('loadUserAccess() result', data: data);
    return data;
  }

  // ================= PURCHASE =================

  Future<void> buy(ProductDetails product) async {
    if (!_availabilityChecked) {
      await checkAvailability();
    }
    if (!_isAvailableCached) {
      _errorController.add('Compras indisponíveis neste dispositivo.');
      _log('buy() bloqueado: isAvailable=false', data: {'productId': product.id});
      return;
    }

    _log('buy() start', data: {
      'productId': product.id,
      'title': product.title,
      'price': product.price,
      'currency': product.currencyCode,
    });

    final purchaseParam = PurchaseParam(productDetails: product);
    await _iap.buyNonConsumable(purchaseParam: purchaseParam);

    _log('buyNonConsumable() chamado', data: {'productId': product.id});
  }

  Future<void> restorePurchases() async {
    _log('restorePurchases() start');
    await _iap.restorePurchases();
    _log('restorePurchases() chamado');
  }

  // ================= STREAM =================

  Future<void> _onPurchaseUpdate(List<PurchaseDetails> purchases) async {
    _log('purchaseStream update recebido', data: {
      'count': purchases.length,
      'uid': _auth.currentUser?.uid,
    });

    for (final purchase in purchases) {
      _log('PurchaseDetails', data: {
        'productID': purchase.productID,
        'status': purchase.status.toString(),
        'pendingCompletePurchase': purchase.pendingCompletePurchase,
        'purchaseID': purchase.purchaseID,
        'transactionDate': purchase.transactionDate,
        'verificationData.source': purchase.verificationData.source,
        'hasError': purchase.error != null,
      });

      if (purchase.status == PurchaseStatus.pending) {
        _log('status=pending (aguardando)');
        continue;
      }

      if (purchase.status == PurchaseStatus.purchased ||
          purchase.status == PurchaseStatus.restored) {
        final token = purchase.verificationData.serverVerificationData;

        if (_claimInProgressOrDoneTokens.contains(token)) {
          _log('claimPurchase ignorado (token já processado)', data: {
            'productID': purchase.productID,
            'status': purchase.status.toString(),
            'tokenLen': token.length,
          });

          if (purchase.pendingCompletePurchase) {
            _log('completePurchase() start (já processado)',
                data: {'productID': purchase.productID});
            await _iap.completePurchase(purchase);
            _log('completePurchase() done (já processado)',
                data: {'productID': purchase.productID});
          }
          continue;
        }

        _claimInProgressOrDoneTokens.add(token);

        _log('status=purchased/restored -> iniciando claimPurchase', data: {
          'productID': purchase.productID,
          'status': purchase.status.toString(),
        });

        bool claimed = false;
        try {
          claimed = await _claimPurchase(purchase);
        } finally {
          if (purchase.pendingCompletePurchase) {
            _log('completePurchase() start', data: {'productID': purchase.productID});
            await _iap.completePurchase(purchase);
            _log('completePurchase() done', data: {'productID': purchase.productID});
          }
        }

        _log('claimPurchase result', data: {
          'productID': purchase.productID,
          'claimed': claimed,
        });

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
        _log('status=canceled');
        _errorController.add('Pagamento cancelado.');
      } else if (purchase.status == PurchaseStatus.error) {
        _log('status=error (detalhes)', data: {
          'code': purchase.error?.code,
          'message': purchase.error?.message,
          'details': purchase.error?.details?.toString(),
          'source': purchase.error?.source,
          'productID': purchase.productID,
        });

        _errorController.add(
          purchase.error?.message ?? 'Erro ao processar pagamento.',
        );
      } else {
        _log('status=unknown/unhandled', data: {
          'status': purchase.status.toString(),
          'productID': purchase.productID,
        });
      }
    }
  }

  // ================= CLAIM (BACKEND) =================

  Future<bool> _claimPurchase(PurchaseDetails purchase) async {
    final uid = _auth.currentUser?.uid;
    if (uid == null) {
      _log('_claimPurchase(): uid null');
      return false;
    }

    try {
      final callable = _functions.httpsCallable('claimPurchase');

      final token = purchase.verificationData.serverVerificationData;

      final String? packageName =
          Platform.isAndroid ? await _getAndroidPackageName() : null;

      _log('claimPurchase() call start', data: {
        'uid': uid,
        'productId': purchase.productID,
        'platform': Platform.isAndroid ? 'android' : 'ios',
        'packageName': packageName,
        'tokenLen': token.length,
      });

      final payload = <String, dynamic>{
        'productId': purchase.productID,
        'purchaseToken': token,
        if (packageName != null) 'packageName': packageName,
      };

      final result = await callable.call(payload);

      _log('claimPurchase() response', data: result.data);

      final data = result.data;
      final ok = data != null && data is Map && data['success'] == true;

      _log('claimPurchase() parsed', data: {
        'success': ok,
        'productId': purchase.productID,
      });

      return ok;
    } on FirebaseFunctionsException catch (e) {
      // ✅ Diagnóstico real do backend (HttpsError v2)
      _log('❌ claimPurchase FirebaseFunctionsException', data: {
        'code': e.code,
        'message': e.message,
        'details': e.details?.toString(),
      });

      final msg = (e.message == null || e.message!.isEmpty)
          ? 'Falha ao validar a compra.'
          : e.message!;

      _errorController.add(msg);
      return false;
    } catch (e) {
      _errorController.add('Falha ao validar a compra.');
      _log('❌ claimPurchase exception', data: e.toString());
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

    _log('PackageInfo.fromPlatform()', data: {
      'packageName': _cachedPackageName,
      'appName': info.appName,
      'version': info.version,
      'buildNumber': info.buildNumber,
    });

    return _cachedPackageName!;
  }
}
