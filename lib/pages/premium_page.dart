import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
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
  String basePlan = 'gratis';

  // ================= DIAGNÓSTICO (TELA) =================
  bool showDebug = false;
  bool iapAvailable = false;
  String lastEvent = '';
  String lastEventType = ''; // 'success' | 'error' | ''

  @override
  void initState() {
    super.initState();
    _initialize();
  }

  @override
  void dispose() {
    service.dispose();
    super.dispose();
  }

  Future<void> _initialize() async {
    iapAvailable = await service.checkAvailability();
    await service.initialize();
    _listenFeedback();
    await _loadData();
  }

  Future<void> _loadData() async {
    products = await service.loadProducts(); // por padrão só basicProductId
    final access = await service.loadUserAccess();
    basePlan = access['basePlan'] ?? 'gratis';
    if (!mounted) return;
    setState(() => loading = false);
  }

  void _listenFeedback() {
    service.onSuccess.listen((msg) async {
      lastEvent = msg;
      lastEventType = 'success';

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(msg), backgroundColor: Colors.green),
      );

      await _loadData();
      if (mounted) setState(() => purchasing = false);
    });

    service.onError.listen((msg) {
      lastEvent = msg;
      lastEventType = 'error';

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(msg), backgroundColor: Colors.red),
      );

      if (mounted) setState(() => purchasing = false);
    });
  }

  ProductDetails? _findBasic() {
    try {
      return products.firstWhere(
        (p) => p.id == InAppPurchaseService.paidBaseProductId,
      );
    } catch (_) {
      return null;
    }
  }

  bool get hasBasic => basePlan == 'basico';

  bool get hasBasicProductLoaded => _findBasic() != null;

  bool get canAttemptPurchase =>
      !loading && !purchasing && !hasBasic && iapAvailable && hasBasicProductLoaded;

  String _buttonLabel() {
    if (hasBasic) return 'Plano ativo';
    if (!iapAvailable) return 'Compras indisponíveis neste aparelho';
    if (!hasBasicProductLoaded) return 'Produto não carregou da Play Store';
    final p = _findBasic();
    if (p == null) return 'Desbloquear agora';
    return 'Desbloquear por ${p.price}';
    // Se quiser “Desbloquear agora” sem preço, troca aqui.
  }

  Future<void> _purchaseBasic() async {
    if (!canAttemptPurchase) return;

    final product = _findBasic();
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

  // ================= DIAGNÓSTICO: TEXTO E AÇÕES =================

  String _diagnosticText() {
    final foundIds = products.map((p) => p.id).toList();
    final basic = _findBasic();

    return [
      'DIAGNÓSTICO (PremiumPage)',
      '--------------------------------',
      'IAP disponível (isAvailable): $iapAvailable',
      'Produto esperado: ${InAppPurchaseService.paidBaseProductId}',
      'Produto carregou: ${basic != null}',
      if (basic != null) 'Preço: ${basic.price} (${basic.currencyCode})',
      'BasePlan (Firestore): $basePlan',
      'Produtos retornados: $foundIds',
      'Pode tentar compra (canAttemptPurchase): $canAttemptPurchase',
      'Último evento: ${lastEventType.isEmpty ? "-" : lastEventType.toUpperCase()}',
      'Mensagem: ${lastEvent.isEmpty ? "-" : lastEvent}',
      '--------------------------------',
      'DICA: se isAvailable=false => problema do dispositivo/emulador.',
      'DICA: se produto não carrega => app não instalado pela Play / conta não testadora / produto não ativo.',
    ].join('\n');
  }

  Future<void> _copyDiagnostic() async {
    final text = _diagnosticText();
    await Clipboard.setData(ClipboardData(text: text));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Diagnóstico copiado. Cole aqui no chat.'),
        backgroundColor: Colors.black87,
      ),
    );
  }

  Future<void> _refreshDiagnostic() async {
    setState(() => loading = true);
    iapAvailable = await service.checkAvailability();
    await _loadData();
    if (!mounted) return;
    setState(() => loading = false);
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
        actions: [
          IconButton(
            tooltip: showDebug ? 'Ocultar diagnóstico' : 'Ver diagnóstico',
            icon: Icon(showDebug ? Icons.bug_report : Icons.bug_report_outlined),
            onPressed: () => setState(() => showDebug = !showDebug),
          ),
        ],
      ),
      body: loading
          ? const Center(child: CircularProgressIndicator())
          : Stack(
              children: [
                _buildContent(),
                if (showDebug) _buildDebugPanel(),
                if (purchasing) _buildLoading(),
              ],
            ),
    );
  }

  Widget _buildContent() {
    final disabledReason = (!iapAvailable)
        ? 'Compras indisponíveis neste aparelho.'
        : (!hasBasicProductLoaded)
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
                  onPressed: canAttemptPurchase ? _purchaseBasic : null,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFFA8C3B0),
                    disabledBackgroundColor: const Color(0xFFA8C3B0).withValues(alpha: 0.35),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                  ),
                  child: purchasing
                      ? const Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                            ),
                            SizedBox(width: 12),
                            Text('Processando...'),
                          ],
                        )
                      : Text(
                          _buttonLabel(),
                          textAlign: TextAlign.center,
                          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: Colors.black),
                        ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 24),
        TextButton(
          onPressed: purchasing ? null : service.restorePurchases,
          style: TextButton.styleFrom(foregroundColor: Colors.black),
          child: const Text('Restaurar compras'),
        ),
      ],
    );
  }

  Widget _buildDebugPanel() {
    final diag = _diagnosticText();

    Color chipColor() {
      if (lastEventType == 'success') return Colors.green;
      if (lastEventType == 'error') return Colors.red;
      return Colors.grey;
    }

    String chipLabel() {
      if (lastEventType == 'success') return 'SUCESSO';
      if (lastEventType == 'error') return 'ERRO';
      return 'SEM EVENTO';
    }

    return Align(
      alignment: Alignment.bottomCenter,
      child: Container(
        margin: const EdgeInsets.all(12),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(18),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.12),
              blurRadius: 12,
              offset: const Offset(0, 6),
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                Chip(
                  label: Text(chipLabel(), style: const TextStyle(color: Colors.white)),
                  backgroundColor: chipColor(),
                ),
                const Spacer(),
                IconButton(
                  tooltip: 'Recarregar dados',
                  icon: const Icon(Icons.refresh),
                  onPressed: loading ? null : _refreshDiagnostic,
                ),
                IconButton(
                  tooltip: 'Copiar diagnóstico',
                  icon: const Icon(Icons.copy),
                  onPressed: _copyDiagnostic,
                ),
                IconButton(
                  tooltip: 'Fechar',
                  icon: const Icon(Icons.close),
                  onPressed: () => setState(() => showDebug = false),
                ),
              ],
            ),
            const SizedBox(height: 8),
            SizedBox(
              height: 180,
              child: SingleChildScrollView(
                child: Text(
                  diag,
                  style: const TextStyle(
                    fontFamily: 'monospace',
                    fontSize: 12,
                    height: 1.25,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
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
              color: const Color(0xFFA8C3B0).withValues(alpha: 0.1),
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
