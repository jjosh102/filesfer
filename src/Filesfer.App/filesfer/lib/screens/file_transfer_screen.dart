import 'dart:io';
import 'package:file_picker/file_picker.dart';
import 'package:filesfer/models/file_transfer.dart';
import 'package:filesfer/providers/file_transfer_notifier.dart';
import 'package:filesfer/services/theme_service.dart';
import 'package:filesfer/widgets/transfer_progress_tile.dart';
import 'package:flutter/material.dart';
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
  final Set<String> _selectedFiles = {};

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

  Future<void> _uploadSelectedFiles() async {
    final result = await FilePicker.platform.pickFiles(allowMultiple: true);
    if (result == null || result.files.isEmpty) {
      _showSnack('No files selected', error: true);
      return;
    }

    final notifier = ref.read(fileTransferNotifierProvider.notifier);
    for (final platformFile in result.files) {
      if (platformFile.path != null) {
        final file = File(platformFile.path!);
        if (await file.exists() && await file.length() > 0) {
          notifier.addUpload(file);
        } else {
          _showSnack(
            'Skipping empty or invalid file: ${platformFile.name}',
            error: true,
          );
        }
      }
    }
    _showSnack('Uploads started for selected files.');
  }

  Future<void> _downloadMultipleFiles() async {
    if (_selectedFiles.isEmpty) {
      _showSnack('No files selected for download.');
      return;
    }

    final saveDir = await FilePicker.platform.getDirectoryPath();

    if (saveDir == null) {
      _showSnack('Download cancelled', error: true);
      return;
    }

    _lastDownloadDir = saveDir;
    final notifier = ref.read(fileTransferNotifierProvider.notifier);

    for (final filename in _selectedFiles) {
      final uniquePath = _getUniqueFilePath(saveDir, filename);
      notifier.addDownload(filename, uniquePath);
    }

    _showSnack('Download started for ${_selectedFiles.length} files.');
    _clearSelection();
  }

  void _toggleFileSelection(String filename) {
    setState(() {
      if (_selectedFiles.contains(filename)) {
        _selectedFiles.remove(filename);
      } else {
        _selectedFiles.add(filename);
      }
    });
  }

  void _clearSelection() {
    setState(() {
      _selectedFiles.clear();
    });
  }

  void _openLastDownloadFolder() {
    if (_lastDownloadDir != null) {
      OpenFilex.open(_lastDownloadDir!);
    } else {
      _showSnack('No downloaded folder found.', error: true);
    }
  }

  IconData _getFileIcon(String filename) {
    final extension = filename.split('.').last.toLowerCase();
    switch (extension) {
      case 'pdf':
        return Icons.picture_as_pdf;
      case 'doc':
      case 'docx':
        return Icons.description;
      case 'xls':
      case 'xlsx':
        return Icons.grid_on;
      case 'ppt':
      case 'pptx':
        return Icons.slideshow;
      case 'jpg':
      case 'jpeg':
      case 'png':
      case 'gif':
      case 'bmp':
        return Icons.image;
      case 'mp4':
      case 'mov':
      case 'avi':
      case 'mkv':
        return Icons.video_file;
      case 'mp3':
      case 'wav':
      case 'flac':
        return Icons.audio_file;
      case 'zip':
      case 'rar':
      case '7z':
        return Icons.folder_zip;
      case 'txt':
        return Icons.text_snippet;
      case 'dart':
      case 'js':
      case 'py':
      case 'html':
      case 'css':
        return Icons.code;
      default:
        return Icons.insert_drive_file;
    }
  }

  @override
  Widget build(BuildContext context) {
    final fileListAsync = ref.watch(fileListProvider);
    final fileTransfers = ref.watch(fileTransferNotifierProvider);
    final themeMode = ref.watch(themeModeProvider);
    final viewMode = ref.watch(viewModeProvider);
    final isSelecting = _selectedFiles.isNotEmpty;

    final uploadTransfers = fileTransfers.where((t) => !t.isDownload).toList();
    final downloadTransfers = fileTransfers.where((t) => t.isDownload).toList();

    return Scaffold(
      appBar: AppBar(
        title: isSelecting
            ? Text('${_selectedFiles.length} selected')
            : const Text('Filesfer'),
        leading: isSelecting
            ? IconButton(
                icon: const Icon(Icons.close),
                onPressed: _clearSelection,
              )
            : null,
        actions: isSelecting
            ? [
                IconButton(
                  icon: const Icon(Icons.download),
                  onPressed: _downloadMultipleFiles,
                ),
              ]
            : [
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
        onPressed: _uploadSelectedFiles,
        label: const Text('Upload Files'),
        icon: const Icon(Icons.upload_file),
      ),
      body: RefreshIndicator(
        onRefresh: _refreshFiles,
        child: Column(
          children: [
            if (uploadTransfers.isNotEmpty)
              _buildTransferSection(
                title: 'Uploads',
                transfers: uploadTransfers,
                color: Theme.of(context).colorScheme.primary,
              ),
            if (downloadTransfers.isNotEmpty)
              _buildTransferSection(
                title: 'Downloads',
                transfers: downloadTransfers,
                color: Theme.of(context).colorScheme.secondary,
              ),
            Expanded(
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
                                    ? const Center(
                                        child: Text('No files available'),
                                      )
                                    : viewMode
                                        ? ListView.separated(
                                            itemCount: files.length,
                                            separatorBuilder: (_, __) =>
                                                const Divider(height: 1),
                                            itemBuilder: (context, index) {
                                              final filename = files[index];
                                              final isSelected = _selectedFiles
                                                  .contains(filename);
                                              return ListTile(
                                                onTap: () =>
                                                    _toggleFileSelection(
                                                        filename),
                                                leading: isSelected
                                                    ? const Icon(
                                                        Icons.check_circle,
                                                        color: Colors.blue,
                                                      )
                                                    : Icon(
                                                        _getFileIcon(filename),
                                                      ),
                                                title: Text(filename),
                                                trailing: IconButton(
                                                  icon: const Icon(
                                                    Icons.download,
                                                  ),
                                                  onPressed: () {
                                                    _toggleFileSelection(
                                                        filename);
                                                    _downloadMultipleFiles();
                                                  },
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
                                              final isSelected = _selectedFiles
                                                  .contains(filename);
                                              return Card(
                                                color: isSelected
                                                    ? Theme.of(context)
                                                        .colorScheme
                                                        .primaryContainer
                                                    : null,
                                                child: InkWell(
                                                  onTap: () =>
                                                      _toggleFileSelection(
                                                          filename),
                                                  child: Center(
                                                    child: Column(
                                                      mainAxisSize:
                                                          MainAxisSize.min,
                                                      children: [
                                                        Icon(
                                                          _getFileIcon(filename),
                                                          size: 36,
                                                          color: isSelected
                                                              ? Theme.of(
                                                                      context)
                                                                  .colorScheme
                                                                  .onPrimaryContainer
                                                              : null,
                                                        ),
                                                        const SizedBox(
                                                            height: 8),
                                                        Text(
                                                          filename,
                                                          maxLines: 2,
                                                          overflow:
                                                              TextOverflow
                                                                  .ellipsis,
                                                          textAlign:
                                                              TextAlign.center,
                                                          style: TextStyle(
                                                            color: isSelected
                                                                ? Theme.of(
                                                                        context)
                                                                    .colorScheme
                                                                    .onPrimaryContainer
                                                                : null,
                                                          ),
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
                                loading: () => const Center(
                                  child: CircularProgressIndicator(),
                                ),
                              ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTransferSection({
    required String title,
    required List<FileTransfer> transfers,
    required Color color,
  }) {
    if (transfers.isEmpty) return const SizedBox.shrink();

    return Container(
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(color: Theme.of(context).dividerColor),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Row(
              children: [
                Icon(
                  title == 'Uploads'
                      ? Icons.upload_file
                      : Icons.download_for_offline,
                  color: color,
                ),
                const SizedBox(width: 8),
                Text(
                  title,
                  style: Theme.of(context).textTheme.titleSmall!.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                ),
              ],
            ),
          ),
          SizedBox(
            height: 220, 
            child: ListView.builder(
              itemCount: transfers.length,
              itemBuilder: (context, index) {
                final transfer = transfers[index];
                return TransferProgressTile(transfer: transfer);
              },
            ),
          ),
        ],
      ),
    );
  }
}