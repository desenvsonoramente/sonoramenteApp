class PurchaseModel {
  final String userEmail;
  final double amount;
  final String paymentMethod;
  final String status; // pending, completed, failed
  final bool hasLifetimeAccess;

  PurchaseModel({
    required this.userEmail,
    required this.amount,
    this.paymentMethod = 'pix',
    this.status = 'pending',
    this.hasLifetimeAccess = true,
  });

  factory PurchaseModel.fromJson(Map<String, dynamic> json) {
    return PurchaseModel(
      userEmail: json['user_email'],
      amount: (json['amount'] as num).toDouble(),
      paymentMethod: json['payment_method'] ?? 'pix',
      status: json['status'] ?? 'pending',
      hasLifetimeAccess: json['has_lifetime_access'] ?? true,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'user_email': userEmail,
      'amount': amount,
      'payment_method': paymentMethod,
      'status': status,
      'has_lifetime_access': hasLifetimeAccess,
    };
  }

  bool get isCompleted => status == 'completed';
}
