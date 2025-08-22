import 'dart:io';
import 'package:file_picker/file_picker.dart';
import 'package:filesfer/providers/file_transfer_notifier.dart';
import 'package:filesfer/widgets/file_app_bar.dart';
import 'package:filesfer/widgets/file_grid_view.dart';
import 'package:filesfer/widgets/file_list_view.dart';
import 'package:filesfer/widgets/transfer_section.dart';
import 'package:filesfer/extensions/time_ago.dart';
import 'package:filesfer/providers/providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:open_filex/open_filex.dart';

class FileTransferScreen extends ConsumerStatefulWidget {
  const FileTransferScreen({super.key});

  @override
  ConsumerState<FileTransferScreen> createState() => _FileTransferScreenState();
}

class _FileTransferScreenState extends ConsumerState<FileTransferScreen>
    with SingleTickerProviderStateMixin {
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
    final nameWithoutExtension = (dotIndex != -1) ? newFilename.substring(0, dotIndex) : newFilename;
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

  void _downloadSingleFile(String filename) async {
    final saveDir = await FilePicker.platform.getDirectoryPath();
    if (saveDir == null) {
      _showSnack('Download cancelled', error: true);
      return;
    }

    _lastDownloadDir = saveDir;
    final notifier = ref.read(fileTransferNotifierProvider.notifier);
    final uniquePath = _getUniqueFilePath(saveDir, filename);
    notifier.addDownload(filename, uniquePath);
    _showSnack('Download of $filename started.');
  }

  void _toggleFileSelection(String filename) {
    setState(() {
      if (_selectedFiles.contains(filename)) {
        _selectedFiles.remove(filename);
      } else {
        _selectedFiles.add(filename);
      }
      ref.read(selectedFilesCountProvider.notifier).state = _selectedFiles.length;
    });
  }

  void _clearSelection() {
    setState(() {
      _selectedFiles.clear();
      ref.read(selectedFilesCountProvider.notifier).state = 0;
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
    final viewMode = ref.watch(viewModeProvider);
    final isSelecting = _selectedFiles.isNotEmpty;

    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: FileAppBar(
          isSelecting: isSelecting,
          selectedFilesCount: _selectedFiles.length,
          onClearSelection: _clearSelection,
          onDownloadMultipleFiles: _downloadMultipleFiles,
          onOpenLastDownloadFolder: _openLastDownloadFolder,
        ),
        floatingActionButton: FloatingActionButton(
          onPressed: _uploadSelectedFiles,
          backgroundColor: Theme.of(context).colorScheme.primaryContainer,
          child: const Icon(Icons.upload_file),
        ),
        body: TabBarView(
          children: [
            RefreshIndicator(
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
                          style: Theme.of(context).textTheme.bodySmall?.copyWith(color: Colors.grey),
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
                                        ? FileListView(
                                            files: files,
                                            selectedFiles: _selectedFiles,
                                            onToggleSelection: _toggleFileSelection,
                                            onDownloadSingleFile: _downloadSingleFile,
                                            getFileIcon: _getFileIcon,
                                          )
                                        : FileGridView(
                                            files: files,
                                            selectedFiles: _selectedFiles,
                                            onToggleSelection: _toggleFileSelection,
                                            getFileIcon: _getFileIcon,
                                          ),
                                error: (_, _) => const Center(
                                  child: Text('Unable to load files. Please try again later.'),
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
            _buildTransferList(),
          ],
        ),
      ),
    );
  }

  Widget _buildTransferList() {
    final fileTransfers = ref.watch(fileTransferNotifierProvider);
    final uploadTransfers = fileTransfers.where((t) => !t.isDownload).toList();
    final downloadTransfers = fileTransfers.where((t) => t.isDownload).toList();

    if (uploadTransfers.isEmpty && downloadTransfers.isEmpty) {
      return const Center(child: Text('No active transfers.'));
    }

    return SingleChildScrollView(
      child: Column(
        children: [
          if (uploadTransfers.isNotEmpty)
            TransferSection(
              title: 'Uploads',
              transfers: uploadTransfers,
              color: Theme.of(context).colorScheme.primary,
            ),
          if (uploadTransfers.isNotEmpty && downloadTransfers.isNotEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 16),
              child: Divider(),
            ),
          if (downloadTransfers.isNotEmpty)
            TransferSection(
              title: 'Downloads',
              transfers: downloadTransfers,
              color: Theme.of(context).colorScheme.secondary,
            ),
        ],
      ),
    );
  }
}