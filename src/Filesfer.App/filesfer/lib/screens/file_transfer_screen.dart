import 'dart:io';
import 'package:filesfer/providers/file_provider.dart';
import 'package:filesfer/services/file_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:file_picker/file_picker.dart';

class FileTransferScreen extends ConsumerStatefulWidget {
  const FileTransferScreen({super.key});

  @override
  ConsumerState<FileTransferScreen> createState() => _FileTransferScreenState();
}

class _FileTransferScreenState extends ConsumerState<FileTransferScreen> {
  bool _isRefreshing = false;

  Future<void> _refreshFiles() async {
    setState(() => _isRefreshing = true);
    ref.invalidate(fileListProvider);
    await Future.delayed(const Duration(milliseconds: 800));
    if (mounted) setState(() => _isRefreshing = false);
  }

  Future<void> _uploadSelectedFile(FileService service) async {
    final result = await FilePicker.platform.pickFiles();
    if (result == null || result.files.single.path == null) return;

    final file = File(result.files.single.path!);

    if (!file.existsSync() || file.lengthSync() == 0) {
       if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please select a non-empty file')),
      );
      return;
    }

    try {
      await service.uploadFile(file);
      await _refreshFiles();
       if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Upload Successful')));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Upload failed: $e')));
    }
  }

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
            Row(
              children: [
                ElevatedButton.icon(
                  icon: const Icon(Icons.upload_file),
                  label: const Text('Upload File'),
                  onPressed: () => _uploadSelectedFile(service),
                ),
                const SizedBox(width: 10),
                ElevatedButton.icon(
                  icon: const Icon(Icons.refresh),
                  label: const Text('Refresh'),
                  onPressed: _refreshFiles,
                ),
              ],
            ),
            const SizedBox(height: 20),
            Expanded(
              child: AnimatedSwitcher(
                duration: const Duration(milliseconds: 500),
                child: _isRefreshing
                    ? const Center(child: CircularProgressIndicator())
                    : fileListAsync.when(
                        data: (files) => ListView.builder(
                          key: const ValueKey('fileList'),
                          itemCount: files.length,
                          itemBuilder: (context, index) {
                            final filename = files[index];
                            return ListTile(
                              leading: const Icon(Icons.insert_drive_file),
                              title: Text(filename),
                              trailing: IconButton(
                                icon: const Icon(Icons.download),
                                onPressed: () async {
                                  final saveDir = await FilePicker.platform
                                      .getDirectoryPath();
                                  if (!mounted) return;

                                  if (saveDir != null) {
                                    await service.downloadFile(
                                      filename,
                                      saveDir,
                                    );
                                    if (!mounted) return;

                                    ScaffoldMessenger.of(context).showSnackBar(
                                      SnackBar(
                                        content: Text('Downloaded to $saveDir'),
                                      ),
                                    );
                                  }
                                },
                              ),
                            );
                          },
                        ),
                        loading: () => const Center(
                          key: ValueKey('loading'),
                          child: CircularProgressIndicator(),
                        ),
                        error: (err, _) => Center(child: Text('Error: $err')),
                      ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
