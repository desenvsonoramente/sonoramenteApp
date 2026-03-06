import 'dart:async';

import 'package:flutter/material.dart';
import 'package:in_app_purchase/in_app_purchase.dart';

import '../services/in_app_purchase_service.dart';

class PremiumPage extends StatefulWidget {
  const PremiumPage({super.key});

  @override
  State<PremiumPage> createState() => _PremiumPageState();
}

class _PremiumPageState extends State<PremiumPage> {
  final InAppPurchaseService service = InAppPurchaseService();

  List<ProductDetails> products = [];
  bool loading = true;
  bool purchasing = false;

  // Plano atual (lido do Firestore users/{uid})
  String basePlan = 'gratis';

  // IAP
  bool iapAvailable = false;

  StreamSubscription<String>? _successSub;
  StreamSubscription<String>? _errorSub;

  @override
  void initState() {
    super.initState();
    _listenFeedback();
    _initialize();
  }

  @override
  void dispose() {
    _successSub?.cancel();
    _errorSub?.cancel();
    service.dispose();
    super.dispose();
  }

  void _listenFeedback() {
    _successSub = service.onSuccess.listen((msg) async {
      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(msg), backgroundColor: Colors.green),
      );

      // Recarrega dados após sucesso
      await _loadData();

      if (mounted) setState(() => purchasing = false);
    });

    _errorSub = service.onError.listen((msg) {
      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(msg), backgroundColor: Colors.red),
      );

      if (mounted) setState(() => purchasing = false);
    });
  }

  Future<void> _initialize() async {
    if (!mounted) return;
    setState(() => loading = true);

    try {
      final available = await service.checkAvailability();
      if (!mounted) return;
      setState(() => iapAvailable = available);

      await service.initialize();
      await _loadData();
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  Future<void> _loadData() async {
    final loadedProducts = await service.loadProducts(); // por padrão só o produto base
    final access = await service.loadUserAccess();

    if (!mounted) return;
    setState(() {
      products = loadedProducts;
      basePlan = (access['basePlan'] as String?) ?? 'gratis';
    });
  }

  ProductDetails? _findBaseProduct() {
    try {
      return products.firstWhere(
        (p) => p.id == InAppPurchaseService.paidBaseProductId,
      );
    } catch (_) {
      return null;
    }
  }

  bool get hasBasic => basePlan == 'basico';
  bool get hasBaseProductLoaded => _findBaseProduct() != null;

  bool get canAttemptPurchase =>
      !loading && !purchasing && !hasBasic && iapAvailable && hasBaseProductLoaded;

  String _buttonLabel() {
    if (hasBasic) return 'Plano ativo';
    if (!iapAvailable) return 'Compras indisponíveis neste aparelho';
    if (!hasBaseProductLoaded) return 'Produto não carregou da Play Store';

    final p = _findBaseProduct();
    if (p == null) return 'Desbloquear agora';
    return 'Desbloquear por ${p.price}';
  }

  Future<void> _purchaseBase() async {
    if (!canAttemptPurchase) return;

    final product = _findBaseProduct();
    if (product == null) return;

    if (!mounted) return;
    setState(() => purchasing = true);

    try {
      await service.buy(product);
    } catch (_) {
      if (!mounted) return;
      setState(() => purchasing = false);

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Falha ao iniciar pagamento.'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  Future<void> _restore() async {
    if (purchasing) return;
    setState(() => purchasing = true);

    try {
      await service.restorePurchases();
    } catch (_) {
      if (!mounted) return;
      setState(() => purchasing = false);

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Não foi possível restaurar compras.'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFFBFAF7),
      appBar: AppBar(
        backgroundColor: const Color(0xFFFBFAF7),
        elevation: 0,
        iconTheme: const IconThemeData(color: Colors.grey),
        title: const Text('Plano Premium', style: TextStyle(color: Colors.black)),
      ),
      body: loading
          ? const Center(child: CircularProgressIndicator())
          : Stack(
              children: [
                _buildContent(),
                if (purchasing) _buildLoading(),
              ],
            ),
    );
  }

  Widget _buildContent() {
    final disabledReason = (!iapAvailable)
        ? 'Compras indisponíveis neste aparelho.'
        : (!hasBaseProductLoaded)
            ? 'Não consegui carregar o produto na Play Store.'
            : '';

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        const SizedBox(height: 8),
        Center(
          child: Image.asset(
            'assets/images/sonoramente_logo_branco.png',
            height: 200,
            fit: BoxFit.contain,
          ),
        ),
        const SizedBox(height: 12),
        const Text(
          'Pague uma única vez e desbloqueie todos os áudios',
          style: TextStyle(fontSize: 20, fontWeight: FontWeight.w600),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 16),
        Container(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(28),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.05),
                blurRadius: 12,
                offset: const Offset(0, 6),
              ),
            ],
          ),
          child: Column(
            children: [
              _benefit(Icons.all_inclusive, 'Acesso vitalício'),
              _benefit(Icons.headphones, 'Todos os áudios disponíveis'),
              _benefit(Icons.edit, 'Sem assinatura'),
              _benefit(Icons.sync, 'Sem renovação'),
              if (!hasBasic && disabledReason.isNotEmpty) ...[
                const SizedBox(height: 10),
                Text(
                  disabledReason,
                  textAlign: TextAlign.center,
                  style: const TextStyle(fontSize: 12, color: Colors.redAccent),
                ),
              ],
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                height: 56,
                child: ElevatedButton(
                  onPressed: canAttemptPurchase ? _purchaseBase : null,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFFA8C3B0),
                    disabledBackgroundColor:
                        const Color(0xFFA8C3B0).withOpacity(0.35),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(20),
                    ),
                  ),
                  child: Text(
                    _buttonLabel(),
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      color: Colors.black,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 24),
        TextButton(
          onPressed: purchasing ? null : _restore,
          style: TextButton.styleFrom(foregroundColor: Colors.black),
          child: const Text('Restaurar compras'),
        ),
      ],
    );
  }

  Widget _benefit(IconData icon, String text) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: const Color(0xFFA8C3B0).withOpacity(0.1),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(icon, color: const Color(0xFFA8C3B0)),
          ),
          const SizedBox(width: 12),
          Text(text),
        ],
      ),
    );
  }

  Widget _buildLoading() {
    return Container(
      color: Colors.black45,
      child: const Center(
        child: CircularProgressIndicator(color: Colors.white),
      ),
    );
  }
}