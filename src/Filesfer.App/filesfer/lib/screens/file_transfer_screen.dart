import 'dart:io';
import 'package:dio/dio.dart';
import 'package:file_picker/file_picker.dart';
import 'package:filesfer/services/theme_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:filesfer/extensions/time_ago.dart';
import 'package:filesfer/providers/providers.dart';
import 'package:open_filex/open_filex.dart';

class FileTransferScreen extends ConsumerStatefulWidget {
  const FileTransferScreen({super.key});

  @override
  ConsumerState<FileTransferScreen> createState() => _FileTransferScreenState();
}

class _FileTransferScreenState extends ConsumerState<FileTransferScreen> {
  bool _isRefreshing = false;
  DateTime? _lastUpdated;
  String? _lastDownloadDir;

  final ValueNotifier<String> _progressMessage = ValueNotifier('');
  final ValueNotifier<double?> _progressValue = ValueNotifier(null);

  void _showSnack(String message, {bool error = false}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: error ? Colors.redAccent : null,
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  void _showProgressBottomSheet(String title) {
    _progressMessage.value = '$title 0%';
    _progressValue.value = 0;

    showModalBottomSheet(
      context: context,
      isDismissible: false,
      enableDrag: false,
      backgroundColor: Theme.of(context).colorScheme.surface,
      builder: (_) {
        return Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(title, style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 12),
              ValueListenableBuilder<double?>(
                valueListenable: _progressValue,
                builder: (_, value, _) => LinearProgressIndicator(value: value),
              ),
              const SizedBox(height: 8),
              ValueListenableBuilder<String>(
                valueListenable: _progressMessage,
                builder: (_, message, _) =>
                    Text(message, style: Theme.of(context).textTheme.bodySmall),
              ),
              const SizedBox(height: 8),
              ElevatedButton.icon(
                onPressed: () {
                  ref.read(cancelTokenProvider).cancel('User cancelled');
                  _hideProgressBottomSheet();
                  _showSnack('Operation cancelled');
                },
                icon: const Icon(Icons.cancel),
                label: const Text('Cancel'),
              ),
            ],
          ),
        );
      },
    );
  }

  void _hideProgressBottomSheet() {
    if (Navigator.canPop(context)) Navigator.pop(context);
  }

  Future<void> _refreshFiles() async {
    setState(() => _isRefreshing = true);
    ref.invalidate(fileListProvider);
    await Future.delayed(const Duration(milliseconds: 500));
    if (mounted) {
      setState(() {
        _isRefreshing = false;
        _lastUpdated = DateTime.now();
      });
    }
  }

  String _getUniqueFilePath(String directory, String filename) {
    String newFilename = filename;
    int copyNumber = 1;

    final dotIndex = newFilename.lastIndexOf('.');
    final nameWithoutExtension = (dotIndex != -1)
        ? newFilename.substring(0, dotIndex)
        : newFilename;
    final extension = (dotIndex != -1) ? newFilename.substring(dotIndex) : '';

    while (File('$directory/$newFilename').existsSync()) {
      newFilename = '$nameWithoutExtension (copy $copyNumber)$extension';
      copyNumber++;
    }
    return '$directory/$newFilename';
  }

  Future<void> _handleFileOperation({
    required Future<bool> Function(CancelToken cancelToken) action,
    required String progressTitle,
    required String successMessage,
  }) async {
    resetCancelToken(ref);
    final cancelToken = ref.read(cancelTokenProvider);
    try {
      _showProgressBottomSheet(progressTitle);
      final isSuccess = await action(cancelToken);
      if (isSuccess) {
        _showSnack(successMessage);
      }
      _hideProgressBottomSheet();
    } on PlatformException catch (e) {
      _hideProgressBottomSheet();
      if (e.message?.contains('No space left on device') ?? false) {
        _showSnack(
          'Not enough storage space. Please free up some space and try again.',
          error: true,
        );
      } else {
        _showSnack('An error occurred: ${e.message}', error: true);
      }
    } on DioException catch (e) {
      _hideProgressBottomSheet();
      if (CancelToken.isCancel(e)) return;
      _showSnack('Network error: ${e.message}', error: true);
    } catch (e) {
      _hideProgressBottomSheet();
      _showSnack('Unexpected error: $e', error: true);
    }
  }

  Future<void> _uploadSelectedFile() async {
    final service = ref.read(fileServiceProvider);
    final result = await FilePicker.platform.pickFiles();

    if (result == null || result.files.first.path == null) {
      _showSnack('No file selected', error: true);
      return;
    }

    final filePath = result.files.first.path!;
    final file = File(filePath);

    if (!file.existsSync() || file.lengthSync() == 0) {
      _showSnack('Please select a valid non-empty file', error: true);
      return;
    }

    await _handleFileOperation(
      progressTitle: 'Uploading File',
      successMessage: 'Upload successful',
      action: (cancelToken) async {
        final isSuccess = await service.uploadFile(
          file,
          onProgress: (bytesSent, totalBytes) {
            final percent = totalBytes > 0 ? bytesSent / totalBytes : 0.0;
            _progressValue.value = percent;
            _progressMessage.value =
                'Uploading: $bytesSent / $totalBytes bytes (${(percent * 100).toStringAsFixed(1)}%)';
          },
          cancelToken: cancelToken,
        );
        if (isSuccess) {
          await _refreshFiles();
        }
        return isSuccess;
      },
    );
  }

  Future<void> _downloadFile(String filename) async {
    final service = ref.read(fileServiceProvider);
    final saveDir = await FilePicker.platform.getDirectoryPath();

    if (saveDir == null) {
      _showSnack('Download cancelled', error: true);
      return;
    }
    final uniquePath = _getUniqueFilePath(saveDir, filename);
    debugPrint('Saving to: $uniquePath');
    _lastDownloadDir = saveDir;
    await _handleFileOperation(
      progressTitle: 'Downloading File',
      successMessage: 'File saved to $uniquePath',
      action: (cancelToken) async {
        final isSuccess = await service.downloadFile(
          filename,
          uniquePath,
          onProgress: (bytesReceived, totalBytes) {
            final percent = totalBytes > 0 ? bytesReceived / totalBytes : 0.0;
            _progressValue.value = percent;
            _progressMessage.value =
                'Downloading: $bytesReceived / $totalBytes bytes (${(percent * 100).toStringAsFixed(1)}%)';
          },
          cancelToken: cancelToken,
        );
        return isSuccess;
      },
    );
  }

  void _openLastDownloadFolder() {
    if (_lastDownloadDir != null) {
      OpenFilex.open(_lastDownloadDir!);
    } else {
      _showSnack('No downloaded folder found.', error: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    // ref.listen<AsyncValue<bool>>(serverStatusStreamProvider, (prev, next) {
    //   next.whenData((isUp) {
    //     ScaffoldMessenger.of(context).showSnackBar(
    //       SnackBar(
    //         behavior: SnackBarBehavior.floating,
    //         backgroundColor: isUp ? Colors.green[600] : Colors.red[600],
    //         content: Row(
    //           children: [
    //             Icon(
    //               isUp ? Icons.cloud_done : Icons.cloud_off,
    //               color: Colors.white,
    //             ),
    //             const SizedBox(width: 12),
    //             Text(
    //               isUp ? 'Server is online' : 'Server is unreachable',
    //               style: const TextStyle(color: Colors.white),
    //             ),
    //           ],
    //         ),
    //         duration: const Duration(seconds: 2),
    //       ),
    //     );
    //     if (isUp) {
    //       _refreshFiles();
    //     }
    //   });
    // });
    final fileListAsync = ref.watch(fileListProvider);
    final themeMode = ref.watch(themeModeProvider);
    final viewMode = ref.watch(viewModeProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Filesfer'),
        actions: [
          PopupMenuButton<String>(
            icon: const Icon(Icons.more_vert),
            onSelected: (value) {
              switch (value) {
                case 'theme':
                   ref.read(themeModeProvider.notifier).toggleTheme();
                  break;
                case 'view':
                  ref.read(viewModeProvider.notifier).state = !viewMode;
                  break;
                case 'open':
                  _openLastDownloadFolder();
                  break;
              }
            },
            itemBuilder: (context) => [
              PopupMenuItem(
                value: 'theme',
                child: Row(
                  children: [
                    Icon(
                      themeMode == ThemeMode.dark
                          ? Icons.light_mode
                          : Icons.dark_mode,
                    ),
                    const SizedBox(width: 8),
                    const Text('Toggle Theme'),
                  ],
                ),
              ),
              PopupMenuItem(
                value: 'view',
                child: Row(
                  children: [
                    Icon(viewMode ? Icons.list : Icons.grid_view),
                    const SizedBox(width: 8),
                    const Text('Toggle View'),
                  ],
                ),
              ),
              const PopupMenuItem(
                value: 'open',
                child: Row(
                  children: [
                    Icon(Icons.folder_open),
                    SizedBox(width: 8),
                    Text('Open Downloads'),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _uploadSelectedFile,
        label: const Text('Upload'),
        icon: const Icon(Icons.upload_file),
      ),
      body: RefreshIndicator(
        onRefresh: _refreshFiles,
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            children: [
              if (_lastUpdated != null)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Text(
                    'Last updated ${_lastUpdated!.toTimeAgo()}',
                    style: Theme.of(
                      context,
                    ).textTheme.bodySmall?.copyWith(color: Colors.grey),
                  ),
                ),
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
                                      leading: const Icon(
                                        Icons.insert_drive_file,
                                      ),
                                      title: Text(filename),
                                      trailing: IconButton(
                                        icon: const Icon(Icons.download),
                                        onPressed: () =>
                                            _downloadFile(filename),
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
                                      child: InkWell(
                                        onTap: () => _downloadFile(filename),
                                        child: Center(
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
      ),
    );
  }
}
