import 'package:filesfer/providers/ip_address_notifier.dart';
import 'package:filesfer/screens/file_transfer_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class IpInputScreen extends ConsumerStatefulWidget {
  final bool isInitial;

  const IpInputScreen({super.key, required this.isInitial});

  @override
  ConsumerState<IpInputScreen> createState() => _IpInputScreenState();
}

class _IpInputScreenState extends ConsumerState<IpInputScreen> {
  final _controller = TextEditingController();
  final _formKey = GlobalKey<FormState>();

  @override
  void initState() {
    super.initState();
    _controller.text = ref.read(ipAddressProvider);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _saveIpAndNavigate() async {
    if (_formKey.currentState!.validate()) {
      final ip = _controller.text.trim();

      await ref.read(ipAddressProvider.notifier).setIpAddress(ip);

      if (mounted) {
        if (widget.isInitial) {
          Navigator.of(context).pushAndRemoveUntil(
            MaterialPageRoute(builder: (context) => const FileTransferScreen()),
            (Route<dynamic> route) => false,
          );
        } else {
          Navigator.of(context).pop();
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: !widget.isInitial,
      child: Scaffold(
        appBar: AppBar(
          title: Text(widget.isInitial ? 'Set Server IP' : 'Modify Server IP'),
          automaticallyImplyLeading: !widget.isInitial,
        ),
        body: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  widget.isInitial
                      ? 'Please enter the IP address of your server to get started.'
                      : 'Update the server IP address.',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 24),
                TextFormField(
                  controller: _controller,
                  decoration: const InputDecoration(
                    labelText: 'Server IP Address',
                    hintText: 'e.g., http://192.168.1.100:8080',
                    border: OutlineInputBorder(),
                  ),
                  validator: (value) {
                    if (value == null || value.isEmpty) {
                      return 'IP address cannot be empty';
                    }
                    if (!value.startsWith('http://') &&
                        !value.startsWith('https://')) {
                      return 'Please include http:// or https://';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 16),
                ElevatedButton(
                  onPressed: _saveIpAndNavigate,
                  child: const Text('Connect'),
                ),
                const SizedBox(height: 8),
                const Divider(),
                const SizedBox(height: 8),
                const Text(
                  'Or use a QR code',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontStyle: FontStyle.italic),
                ),
                const SizedBox(height: 8),
                ElevatedButton.icon(
                  onPressed: () {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('QR code scanning coming soon!'),
                      ),
                    );
                  },
                  icon: const Icon(Icons.qr_code_scanner),
                  label: const Text('Scan QR Code'),
                  style: ElevatedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 16),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
