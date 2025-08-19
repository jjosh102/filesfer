import 'package:filesfer/providers/providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

class QRScannerScreen extends ConsumerStatefulWidget {
  const QRScannerScreen({super.key});

  @override
  ConsumerState<QRScannerScreen> createState() => _QRScannerScreenState();
}

class _QRScannerScreenState extends ConsumerState<QRScannerScreen> {
  final MobileScannerController controller = MobileScannerController();

  bool _isProcessing = false;

  Future<void> _uploadFromGallery() async {
    final ImagePicker picker = ImagePicker();
    final XFile? image = await picker.pickImage(source: ImageSource.gallery);

    if (image != null) {
      final barcode = await controller.analyzeImage(image.path);
      if (barcode!.barcodes.isNotEmpty && barcode.barcodes.first.rawValue != null) {
        final code = barcode.barcodes.first.rawValue!;
      
        ref.read(qrCodeProvider.notifier).state = code;
      
        if (mounted) {
          Navigator.pop(context);
        }
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('No QR code found in the image.')),
          );
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Scan or Upload QR Code'),
      ),
      body: Stack(
        children: <Widget>[
          MobileScanner(
            controller: controller,
            onDetect: (capture) {
              if (_isProcessing) return; 

              final List<Barcode> barcodes = capture.barcodes;
              if (barcodes.isNotEmpty) {
                final code = barcodes.first.rawValue;
                if (code != null) {
                  _isProcessing = true;
                  
                  controller.stop();
                  ref.read(qrCodeProvider.notifier).state = code;
                  
                  if (mounted) {
                    Navigator.pop(context);
                  }
                }
              }
            },
          ),
          Center(
            child: Container(
              width: 200,
              height: 200,
              decoration: BoxDecoration(
                border: Border.all(color: Colors.red, width: 2),
                borderRadius: BorderRadius.circular(10),
              ),
            ),
          ),
          SafeArea(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Padding(
                  padding: const EdgeInsets.only(top: 24.0),
                  child: Text(
                    'Scan QR code or upload from your gallery.',
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                          color: Colors.white,
                          backgroundColor: Colors.black54,
                        ),
                  ),
                ),
                const Spacer(),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 48.0),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: [
                      ElevatedButton.icon(
                        onPressed: () {
                          _isProcessing = false; 
                          controller.start();
                        },
                        icon: const Icon(Icons.camera_alt),
                        label: const Text('Scan'),
                      ),
                      ElevatedButton.icon(
                        onPressed: _uploadFromGallery,
                        icon: const Icon(Icons.photo_library),
                        label: const Text('Upload'),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }
}