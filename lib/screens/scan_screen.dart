import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

/// Pops with the raw QR string of the first code it sees.
class ScanScreen extends StatefulWidget {
  const ScanScreen({super.key});

  @override
  State<ScanScreen> createState() => _ScanScreenState();
}

class _ScanScreenState extends State<ScanScreen> {
  final _controller = MobileScannerController(formats: const [BarcodeFormat.qrCode]);
  bool _done = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Scan companion QR')),
      body: MobileScanner(
        controller: _controller,
        onDetect: (capture) {
          if (_done) return;
          final raw = capture.barcodes.map((b) => b.rawValue).whereType<String>().firstOrNull;
          if (raw == null) return;
          _done = true;
          Navigator.of(context).pop(raw);
        },
        errorBuilder: (context, error) => Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Text(
              'Camera unavailable (${error.errorCode.name}). Allow camera access in system settings, or enter the address manually.',
              textAlign: TextAlign.center,
            ),
          ),
        ),
      ),
    );
  }
}
