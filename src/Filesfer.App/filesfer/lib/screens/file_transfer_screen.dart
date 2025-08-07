import 'dart:io';
import 'package:filesfer/providers/file_provider.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:file_picker/file_picker.dart';

class FileTransferScreen extends ConsumerStatefulWidget {
  const FileTransferScreen({super.key});

  @override
  ConsumerState<FileTransferScreen> createState() => _FileTransferScreenState();
}

class _FileTransferScreenState extends ConsumerState<FileTransferScreen> {
  @override
  Widget build(BuildContext context) {
    final fileListAsync = ref.watch(fileListProvider);
    final service = ref.read(fileServiceProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Filesfer')),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            ElevatedButton.icon(
              icon: const Icon(Icons.upload_file),
              label: const Text('Upload File'),
              onPressed: () async {
                final result = await FilePicker.platform.pickFiles();
                if (!mounted) return;

                if (result != null && result.files.single.path != null) {
                  final file = File(result.files.single.path!);
                  await service.uploadFile(file);
                  if (!mounted) return;

                  ref.refresh(fileListProvider);
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Upload Successful')),
                  );
                }
              },
            ),
            const SizedBox(height: 20),
            Expanded(
              child: fileListAsync.when(
                data: (files) => ListView.builder(
                  itemCount: files.length,
                  itemBuilder: (context, index) {
                    final filename = files[index];
                    return ListTile(
                      leading: const Icon(Icons.insert_drive_file),
                      title: Text(filename),
                      trailing: IconButton(
                        icon: const Icon(Icons.download),
                        onPressed: () async {
                          final saveDir = await FilePicker.platform.getDirectoryPath();
                          if (!mounted) return;

                          if (saveDir != null) {
                            await service.downloadFile(filename, saveDir);
                            if (!mounted) return;

                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(content: Text('Downloaded to $saveDir')),
                            );
                          }
                        },
                      ),
                    );
                  },
                ),
                loading: () => const Center(child: CircularProgressIndicator()),
                error: (err, _) => Center(child: Text('Error: $err')),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
