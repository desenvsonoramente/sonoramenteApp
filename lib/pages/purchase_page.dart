import 'package:flutter/material.dart';

class PurchasePage extends StatefulWidget {
  const PurchasePage({super.key});

  @override
  State<PurchasePage> createState() => _PurchasePageState();
}

class _PurchasePageState extends State<PurchasePage> {
  bool isProcessing = false;

  final benefits = const [
    {'icon': Icons.all_inclusive, 'text': 'Acesso vitalício'},
    {'icon': Icons.headphones, 'text': 'Todos os áudios disponíveis'},
    {'icon': Icons.shield, 'text': 'Sem assinatura'},
    {'icon': Icons.favorite, 'text': 'Sem renovação'},
  ];

  Future<void> processPurchase() async {
    if (!mounted) return;
    setState(() => isProcessing = true);

    // simula pagamento
    await Future.delayed(const Duration(seconds: 2));

    if (!mounted) return;
    setState(() => isProcessing = false);

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Compra realizada com sucesso!')),
    );

    await Future.delayed(const Duration(seconds: 1));

    if (!mounted) return;
    Navigator.pop(context); // volta pra Home
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFFAFAF7),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Row(
              children: [
                IconButton(
                  onPressed: () => Navigator.pop(context),
                  icon: const Icon(Icons.arrow_back, color: Colors.grey),
                ),
              ],
            ),
            const SizedBox(height: 24),

            /// Hero
            Column(
              children: [
                Container(
                  width: 96,
                  height: 96,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(24),
                    gradient: const LinearGradient(
                      colors: [
                        Color(0xFFA8C3B0),
                        Color(0xFFC6B7D8),
                        Color(0xFF6F8FAF),
                      ],
                    ),
                  ),
                  child: const Center(
                    child: Text('🎧', style: TextStyle(fontSize: 40)),
                  ),
                ),
                const SizedBox(height: 16),
                const Text(
                  'Desbloqueie todos os áudios',
                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 8),
                const Text(
                  'Você paga uma vez e usa sempre que precisar.',
                  style: TextStyle(color: Colors.grey),
                  textAlign: TextAlign.center,
                ),
              ],
            ),

            const SizedBox(height: 32),

            /// Price Card
            Container(
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(28),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.05),
                    blurRadius: 12,
                    offset: const Offset(0, 6),
                  )
                ],
              ),
              child: Column(
                children: [
                  const Text(
                    'Pagamento único',
                    style: TextStyle(color: Colors.grey),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: const [
                      Text(
                        'R\$ ',
                        style:
                            TextStyle(fontSize: 20, color: Colors.grey),
                      ),
                      Text(
                        '15',
                        style: TextStyle(
                          fontSize: 56,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      Text(
                        ',90',
                        style:
                            TextStyle(fontSize: 20, color: Colors.grey),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  const Text(
                    'Acesso vitalício',
                    style: TextStyle(
                      color: Color(0xFFA8C3B0),
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 24),

                  /// Benefits
                  Column(
                    children: benefits.map((b) {
                      return Padding(
                        padding: const EdgeInsets.symmetric(vertical: 6),
                        child: Row(
                          children: [
                            Container(
                              width: 40,
                              height: 40,
                              decoration: BoxDecoration(
                                color: const Color(0xFFA8C3B0)
                                    .withValues(alpha: 0.1),
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: Icon(
                                b['icon'] as IconData,
                                color: const Color(0xFFA8C3B0),
                              ),
                            ),
                            const SizedBox(width: 12),
                            Text(b['text'] as String),
                          ],
                        ),
                      );
                    }).toList(),
                  ),

                  const SizedBox(height: 24),

                  /// CTA
                  SizedBox(
                    width: double.infinity,
                    height: 56,
                    child: ElevatedButton(
                      onPressed: isProcessing ? null : processPurchase,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFFA8C3B0),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(20),
                        ),
                      ),
                      child: isProcessing
                          ? Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: const [
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
                          : const Text(
                              'Desbloquear Agora',
                              style: TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 24),

            /// Trust badges
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: const [
                Icon(Icons.shield, size: 16, color: Colors.grey),
                SizedBox(width: 4),
                Text(
                  'Pagamento seguro',
                  style: TextStyle(color: Colors.grey),
                ),
                SizedBox(width: 16),
                Icon(Icons.check, size: 16, color: Colors.grey),
                SizedBox(width: 4),
                Text(
                  'PIX aceito',
                  style: TextStyle(color: Colors.grey),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
