import 'package:flutter/material.dart';

import '../widgets/scanner_overlay.dart';

// ---------------------------------------------------------------------------
// Screen
// ---------------------------------------------------------------------------

/// Full-screen barcode/card scanner with no associated listing.
///
/// Cards are identified and result chips are shown exactly as in
/// [ListingDetailScreen], but matches are not persisted anywhere — this is
/// purely an identification tool.
///
/// The [ScannerOverlay] manages its own camera lifecycle; this screen only
/// provides the shell (Scaffold, back button, capture button).
class QuickScanScreen extends StatefulWidget {
  const QuickScanScreen({super.key});

  @override
  State<QuickScanScreen> createState() => _QuickScanScreenState();
}

class _QuickScanScreenState extends State<QuickScanScreen> {
  final _scannerKey = GlobalKey<ScannerOverlayState>();

  bool _detecting     = false;

  // ---------------------------------------------------------------------------
  // Build
  // ---------------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      resizeToAvoidBottomInset: false,
      body: Stack(
        children: [
          // Full-screen scanner — no onCardAdded or onCardUpdated so matches
          // are never persisted (the overlay still shows result chips).
          Positioned.fill(
            child: ScannerOverlay(
              key:                _scannerKey,
              isActive:           true,
              showCaptureButton:  false,
              showTuningButton:   true,
              onCardAdded:        null,
              onDetectionChanged: (d) => setState(() => _detecting     = d),
            ),
          ),

          // Capture button — pinned to bottom-centre above the system nav bar.
            Positioned(
              bottom: 0,
              left:   0,
              right:  0,
              child: SafeArea(
                top: false,
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  child: Center(
                    child: CaptureButton(
                      detecting: _detecting,
                      onTap: () => _scannerKey.currentState?.capture(),
                    ),
                  ),
                ),
              ),
            ),

          // Back button — top-left, matching ListingDetailScreen style.
          Positioned(
            top: 0, left: 0,
            child: SafeArea(
              bottom: false,
              child: Padding(
                padding: const EdgeInsets.all(6),
                child: IconButton(
                  icon:      const Icon(Icons.arrow_back_ios_new_rounded),
                  color:     Colors.white,
                  style:     IconButton.styleFrom(backgroundColor: Colors.black45),
                  tooltip:   'Back',
                  onPressed: () => Navigator.pop(context),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
