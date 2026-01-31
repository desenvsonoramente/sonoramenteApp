import 'package:flutter/material.dart';
import 'package:in_app_purchase/in_app_purchase.dart';

import '../services/in_app_purchase_service.dart';

class PremiumPage extends StatefulWidget {
  const PremiumPage({super.key});

  @override
  State<PremiumPage> createState() => _PremiumPageState();
}

class _PremiumPageState extends State<PremiumPage> {
  final service = InAppPurchaseService();

  List<ProductDetails> products = [];
  bool loading = true;
  bool purchasing = false;

  String basePlan = 'gratis';

  @override
  void initState() {
    super.initState();
    _init();
    _listenFeedback();
  }

  void _listenFeedback() {
    service.onSuccess.listen((msg) {
      if (!mounted || !context.mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(msg),
          backgroundColor: Colors.green,
        ),
      );
    });

    service.onError.listen((msg) {
      if (!mounted || !context.mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(msg),
          backgroundColor: Colors.red,
        ),
      );
    });
  }

  Future<void> _init() async {
    await service.initialize();
    products = await service.loadProducts();

    final access = await service.loadUserAccess();
    basePlan = access['basePlan'] ?? 'gratis';

    if (!mounted) return;
    setState(() => loading = false);
  }

  ProductDetails? _findBasic() {
    try {
      return products.firstWhere(
        (p) => p.id == InAppPurchaseService.basicId,
      );
    } catch (_) {
      return null;
    }
  }

  bool get hasBasic => basePlan == 'basico';

  Future<void> _purchaseBasic() async {
    final product = _findBasic();
    if (product == null) return;

    if (!mounted) return;
    setState(() => purchasing = true);

    try {
      await service.buy(product);
    } catch (_) {
      if (!mounted || !context.mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Falha ao iniciar pagamento.'),
          backgroundColor: Colors.red,
        ),
      );
    }

    await Future.delayed(const Duration(seconds: 2));
    await _init();

    if (!mounted) return;
    setState(() => purchasing = false);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFFBFAF7),
      appBar: AppBar(
        backgroundColor: const Color(0xFFFBFAF7),
        elevation: 0,
        iconTheme: const IconThemeData(color: Colors.grey),
        title: const Text(
          'Plano Premium',
          style: TextStyle(color: Colors.black),
        ),
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
                color: Colors.black.withValues(alpha: 0.05),
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
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                height: 56,
                child: ElevatedButton(
                  onPressed:
                      hasBasic || purchasing ? null : _purchaseBasic,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFFA8C3B0),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(20),
                    ),
                  ),
                  child: purchasing
                      ? const Row(
                          mainAxisAlignment:
                              MainAxisAlignment.center,
                          children: [
                            SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.white,
                              ),
                            ),
                            SizedBox(width: 12),
                            Text('Processando...'),
                          ],
                        )
                      : Text(
                          hasBasic
                              ? 'Plano ativo'
                              : 'Desbloquear agora',
                          style: const TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w500,
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
          onPressed:
              purchasing ? null : service.restorePurchases,
          style: TextButton.styleFrom(
            foregroundColor: Colors.black,
          ),
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
              color:
                  const Color(0xFFA8C3B0).withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(12),
            ),
            child:
                Icon(icon, color: const Color(0xFFA8C3B0)),
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
