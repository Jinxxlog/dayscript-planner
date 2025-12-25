import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../services/ads/ad_controller.dart';

class AdFloatingBanner extends StatelessWidget {
  const AdFloatingBanner({super.key});

  @override
  Widget build(BuildContext context) {
    return Consumer<AdController>(
      builder: (context, ads, _) {
        final banner = ads.banner;
        if (banner == null) return const SizedBox.shrink();
        return banner;
      },
    );
  }
}

