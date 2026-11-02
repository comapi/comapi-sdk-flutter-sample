import 'package:flutter/material.dart';
import '../theme/dotdigital_brand.dart';

// ============================================================================
// PROMO SCREEN - DEEP LINK DESTINATION
// ============================================================================
// Target screen for deep links matching `ddexample://promo`.
//
// Demonstrates how deep links configured in Dotdigital Program Builder campaigns
// direct users directly to special offers, marketing campaigns, or discount codes
// upon notification tap.
// ============================================================================

class PromoScreen extends StatelessWidget {
  final Map<String, dynamic>? extraData;

  const PromoScreen({super.key, this.extraData});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Exclusive Promotion'),
        backgroundColor: DotdigitalBrand.inkBlack,
        foregroundColor: DotdigitalBrand.white,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(18.0),
        child: Column(
          children: [
            Container(
              width: double.infinity,
              decoration: BoxDecoration(
                color: DotdigitalBrand.signalPink,
                borderRadius: BorderRadius.circular(28),
                border: Border.all(color: DotdigitalBrand.inkBlack, width: 1.5),
              ),
              padding: const EdgeInsets.all(28.0),
              child: Column(
                children: [
                  Container(
                    padding: const EdgeInsets.all(14),
                    decoration: const BoxDecoration(
                      color: DotdigitalBrand.inkBlack,
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(Icons.local_offer, color: DotdigitalBrand.neon, size: 36),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'SPECIAL CAMPAIGN OFFER',
                    style: DotdigitalBrand.eyebrowStyle(
                      fontSize: 11,
                      color: DotdigitalBrand.inkBlack,
                    ),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    '25% off your next order.',
                    textAlign: TextAlign.center,
                    style: DotdigitalBrand.headlineStyle(
                      fontSize: 30,
                      color: DotdigitalBrand.inkBlack,
                    ),
                  ),
                  const SizedBox(height: 20),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 10),
                    decoration: BoxDecoration(
                      color: DotdigitalBrand.neon,
                      borderRadius: BorderRadius.circular(999),
                      border: Border.all(color: DotdigitalBrand.inkBlack, width: 1.5),
                    ),
                    child: Text(
                      'DOTPUSH25',
                      style: TextStyle(
                        fontFamily: DotdigitalBrand.fontBody,
                        color: DotdigitalBrand.inkBlack,
                        fontWeight: FontWeight.w600,
                        letterSpacing: 2,
                        fontSize: 18,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),
            Container(
              width: double.infinity,
              decoration: BoxDecoration(
                color: DotdigitalBrand.softSand,
                borderRadius: BorderRadius.circular(24),
                border: Border.all(color: DotdigitalBrand.warmSand, width: 1.5),
              ),
              padding: const EdgeInsets.all(20.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'ROUTING VERIFICATION',
                    style: DotdigitalBrand.eyebrowStyle(fontSize: 10, color: DotdigitalBrand.darkSand),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Deep Link Verification',
                    style: DotdigitalBrand.headerStyle(fontSize: 19),
                  ),
                  const SizedBox(height: 10),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    decoration: BoxDecoration(
                      color: DotdigitalBrand.white,
                      borderRadius: BorderRadius.circular(999),
                      border: Border.all(color: DotdigitalBrand.warmSand),
                    ),
                    child: const Text(
                      'ddexample://promo',
                      style: TextStyle(
                        fontFamily: 'monospace',
                        fontWeight: FontWeight.w600,
                        color: DotdigitalBrand.inkBlack,
                      ),
                    ),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    'Demonstrates how deep links dispatched from Dotdigital Program Builder route the user immediately to targeted campaign content upon push notification tap.',
                    style: DotdigitalBrand.bodyStyle(color: DotdigitalBrand.charcoal, fontSize: 13),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
