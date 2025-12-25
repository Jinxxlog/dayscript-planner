class CreditPack {
  final String productId;
  final int priceKrw;
  final int credits;
  const CreditPack({
    required this.productId,
    required this.priceKrw,
    required this.credits,
  });
}

class SubscriptionPack {
  final String tier; // "pro" | "premium"
  final int days;
  final int costCredits;
  const SubscriptionPack({
    required this.tier,
    required this.days,
    required this.costCredits,
  });
}

class BillingCatalog {
  static const creditPacks = <CreditPack>[
    CreditPack(productId: 'credit_1000', priceKrw: 1000, credits: 100),
    CreditPack(productId: 'credit_5000', priceKrw: 5000, credits: 500),
    CreditPack(productId: 'credit_10000', priceKrw: 10000, credits: 1000),
    CreditPack(productId: 'credit_50000', priceKrw: 50000, credits: 5000),
  ];

  static Set<String> get creditProductIds =>
      creditPacks.map((e) => e.productId).toSet();

  static int? creditsForProductId(String productId) {
    for (final p in creditPacks) {
      if (p.productId == productId) return p.credits;
    }
    return null;
  }

  static const proPacks = <SubscriptionPack>[
    SubscriptionPack(tier: 'pro', days: 7, costCredits: 70),
    SubscriptionPack(tier: 'pro', days: 30, costCredits: 340),
    SubscriptionPack(tier: 'pro', days: 100, costCredits: 990),
  ];

  static const premiumPacks = <SubscriptionPack>[
    SubscriptionPack(tier: 'premium', days: 7, costCredits: 120),
    SubscriptionPack(tier: 'premium', days: 30, costCredits: 620),
    SubscriptionPack(tier: 'premium', days: 100, costCredits: 1590),
  ];
}
