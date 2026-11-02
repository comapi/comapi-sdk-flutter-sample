import 'package:flutter/material.dart';
import '../theme/dotdigital_brand.dart';

// ============================================================================
// PRODUCT DETAIL SCREEN - DEEP LINK DESTINATION
// ============================================================================
// Target screen for deep links matching `ddexample://product/:id`.
//
// Demonstrates:
// 1. URL Scheme resolution: Navigated to when a push carrying a deep link is tapped.
// 2. Click Tracking verification: Confirms that passing the incoming intent/response
//    to the native SDK successfully triggers Dotdigital analytics tracking.
// 3. Custom Data consumption: Displays accompanying `dd_data` payload parameters.
// ============================================================================

class ProductDetailScreen extends StatelessWidget {
  final String productId;
  final Map<String, dynamic>? extraData;

  const ProductDetailScreen({
    super.key,
    required this.productId,
    this.extraData,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Product $productId'),
        backgroundColor: DotdigitalBrand.inkBlack,
        foregroundColor: DotdigitalBrand.white,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(18.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              decoration: BoxDecoration(
                color: DotdigitalBrand.softSand,
                borderRadius: BorderRadius.circular(24),
                border: Border.all(color: DotdigitalBrand.warmSand, width: 1.5),
              ),
              padding: const EdgeInsets.all(22.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                          color: DotdigitalBrand.neon,
                          borderRadius: BorderRadius.circular(18),
                        ),
                        child: const Icon(Icons.shopping_bag, color: DotdigitalBrand.inkBlack, size: 32),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'DEEP LINK TARGET VERIFIED',
                              style: DotdigitalBrand.eyebrowStyle(
                                fontSize: 10,
                                color: DotdigitalBrand.darkSand,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              'Product #$productId',
                              style: DotdigitalBrand.headlineStyle(fontSize: 24),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const Divider(height: 32, color: DotdigitalBrand.warmSand),
                  Text(
                    'DEEP LINK URI',
                    style: DotdigitalBrand.eyebrowStyle(fontSize: 10, color: DotdigitalBrand.darkSand),
                  ),
                  const SizedBox(height: 6),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                    decoration: BoxDecoration(
                      color: DotdigitalBrand.white,
                      borderRadius: BorderRadius.circular(999),
                      border: Border.all(color: DotdigitalBrand.warmSand),
                    ),
                    child: SelectableText(
                      'ddexample://product/$productId',
                      style: const TextStyle(
                        fontFamily: 'monospace',
                        fontWeight: FontWeight.w600,
                        color: DotdigitalBrand.inkBlack,
                      ),
                    ),
                  ),
                  const SizedBox(height: 18),
                  Text(
                    'DOTDIGITAL CLICK TRACKING STATUS',
                    style: DotdigitalBrand.eyebrowStyle(fontSize: 10, color: DotdigitalBrand.darkSand),
                  ),
                  const SizedBox(height: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    decoration: BoxDecoration(
                      color: DotdigitalBrand.neon,
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.check_circle, color: DotdigitalBrand.inkBlack, size: 16),
                        SizedBox(width: 6),
                        Flexible(
                          child: Text(
                            'Tracked via handlePushNotification / handleNotificationResponse',
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              color: DotdigitalBrand.inkBlack,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            if (extraData != null && extraData!.isNotEmpty) ...[
              const SizedBox(height: 24),
              Text(
                'PAYLOAD METADATA',
                style: DotdigitalBrand.eyebrowStyle(fontSize: 10, color: DotdigitalBrand.darkSand),
              ),
              const SizedBox(height: 4),
              Text(
                'Associated Custom Data (dd_data)',
                style: DotdigitalBrand.headerStyle(fontSize: 19),
              ),
              const SizedBox(height: 10),
              Container(
                decoration: BoxDecoration(
                  color: DotdigitalBrand.softSand,
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: DotdigitalBrand.warmSand, width: 1.5),
                ),
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  children: extraData!.entries.map((e) {
                    return Padding(
                      padding: const EdgeInsets.symmetric(vertical: 4.0),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '${e.key}: ',
                            style: const TextStyle(
                              fontWeight: FontWeight.bold,
                              fontFamily: 'monospace',
                              color: DotdigitalBrand.inkBlack,
                            ),
                          ),
                          Expanded(
                            child: Text(
                              '${e.value}',
                              style: const TextStyle(
                                fontFamily: 'monospace',
                                color: DotdigitalBrand.charcoal,
                              ),
                            ),
                          ),
                        ],
                      ),
                    );
                  }).toList(),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
