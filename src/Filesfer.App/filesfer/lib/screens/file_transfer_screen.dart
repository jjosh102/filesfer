import 'dart:io';
import 'package:file_picker/file_picker.dart';
import 'package:filesfer/providers/file_provider.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class FileTransferScreen extends ConsumerStatefulWidget {
  const FileTransferScreen({super.key});

  @override
  ConsumerState<FileTransferScreen> createState() => _FileTransferScreenState();
}

class _FileTransferScreenState extends ConsumerState<FileTransferScreen> {
  bool _isRefreshing = false;

  void _showSnack(String message, {bool error = false}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: error ? Colors.redAccent : null,
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  Future<void> _refreshFiles() async {
    setState(() => _isRefreshing = true);
    ref.invalidate(fileListProvider);
    await Future.delayed(const Duration(milliseconds: 500));
    if (mounted) setState(() => _isRefreshing = false);
  }

  Future<void> _uploadSelectedFile() async {
    final service = ref.read(fileServiceProvider);
    try {
      final result = await FilePicker.platform.pickFiles();
      if (result == null || result.files.single.path == null) {
        _showSnack('No file selected', error: true);
        return;
      }

      final file = File(result.files.single.path!);
      if (!file.existsSync() || file.lengthSync() == 0) {
        _showSnack('Please select a valid non-empty file', error: true);
        return;
      }

      await service.uploadFile(file);
      await _refreshFiles();
      _showSnack('Upload successful');
    } catch (_) {
      _showSnack(
        'Something went wrong while uploading. Please try again.',
        error: true,
      );
    }
  }

  Future<void> _downloadFile(String filename) async {
    final service = ref.read(fileServiceProvider);
    try {
      final saveDir = await FilePicker.platform.getDirectoryPath();
      if (saveDir == null) {
        _showSnack('Download cancelled', error: true);
        return;
      }

      await service.downloadFile(filename, saveDir);
      _showSnack('File saved to $saveDir');
    } catch (_) {
      _showSnack(
        'Failed to download file. Please check your connection.',
        error: true,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final fileListAsync = ref.watch(fileListProvider);
    final themeMode = ref.watch(themeModeProvider);
    final viewMode = ref.watch(viewModeProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Filesfer'),
        actions: [
          IconButton(
            tooltip: 'Toggle Theme',
            icon: Icon(
              themeMode == ThemeMode.dark ? Icons.light_mode : Icons.dark_mode,
            ),
            onPressed: () {
              ref
                  .read(themeModeProvider.notifier)
                  .state = themeMode == ThemeMode.dark
                  ? ThemeMode.light
                  : ThemeMode.dark;
            },
          ),
          IconButton(
            tooltip: 'Toggle View',
            icon: Icon(viewMode ? Icons.grid_view : Icons.list),
            onPressed: () =>
                ref.read(viewModeProvider.notifier).state = !viewMode,
          ),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            Wrap(
              spacing: 12,
              children: [
                FilledButton.icon(
                  icon: const Icon(Icons.upload_file),
                  label: const Text('Upload'),
                  onPressed: _uploadSelectedFile,
                ),
                FilledButton.icon(
                  icon: const Icon(Icons.refresh),
                  label: const Text('Refresh'),
                  onPressed: _refreshFiles,
                ),
              ],
            ),
            const SizedBox(height: 20),
            Expanded(
              child: AnimatedSwitcher(
                duration: const Duration(milliseconds: 400),
                child: _isRefreshing
                    ? const Center(child: CircularProgressIndicator())
                    : fileListAsync.when(
                        data: (files) => files.isEmpty
                            ? const Center(child: Text('No files available'))
                            : viewMode
                            ? ListView.separated(
                                itemCount: files.length,
                                separatorBuilder: (_, __) =>
                                    const Divider(height: 1),
                                itemBuilder: (context, index) {
                                  final filename = files[index];
                                  return ListTile(
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(12),
                                    ),
                                    leading: const Icon(
                                      Icons.insert_drive_file,
                                    ),
                                    title: Text(filename),
                                    trailing: IconButton(
                                      icon: const Icon(Icons.download),
                                      onPressed: () => _downloadFile(filename),
                                    ),
                                  );
                                },
                              )
                            : GridView.builder(
                                itemCount: files.length,
                                gridDelegate:
                                    const SliverGridDelegateWithFixedCrossAxisCount(
                                      crossAxisCount: 2,
                                      crossAxisSpacing: 12,
                                      mainAxisSpacing: 12,
                                    ),
                                itemBuilder: (context, index) {
                                  final filename = files[index];
                                  return Card(
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(16),
                                    ),
                                    child: InkWell(
                                      borderRadius: BorderRadius.circular(16),
                                      onTap: () => _downloadFile(filename),
                                      child: Center(
                                        child: Padding(
                                          padding: const EdgeInsets.all(12),
                                          child: Column(
                                            mainAxisSize: MainAxisSize.min,
                                            children: [
                                              const Icon(
                                                Icons.insert_drive_file,
                                                size: 36,
                                              ),
                                              const SizedBox(height: 8),
                                              Text(
                                                filename,
                                                maxLines: 2,
                                                overflow: TextOverflow.ellipsis,
                                                textAlign: TextAlign.center,
                                              ),
                                            ],
                                          ),
                                        ),
                                      ),
                                    ),
                                  );
                                },
                              ),
                        error: (_, __) => const Center(
                          child: Text(
                            'Unable to load files. Please try again later.',
                          ),
                        ),
                        loading: () =>
                            const Center(child: CircularProgressIndicator()),
                      ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
