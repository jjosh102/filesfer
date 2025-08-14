import 'dart:async';
import 'dart:io';
import 'package:dio/dio.dart';
import 'package:filesfer/models/file_transfer.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:filesfer/providers/providers.dart';
import 'package:uuid/uuid.dart';


final fileTransferNotifierProvider =
    StateNotifierProvider<FileTransferNotifier, List<FileTransfer>>((ref) {
  return FileTransferNotifier(ref);
});

class FileTransferNotifier extends StateNotifier<List<FileTransfer>> {
  final Ref ref;
  final int maxConcurrentTransfers = 10; 
  final Uuid _uuid = const Uuid();

  FileTransferNotifier(this.ref) : super([]);

  void addDownload(String filename, String saveDir) {
    final newTransfer = FileTransfer(
      id: _uuid.v4(),
      filename: filename,
      isDownload: true,
      cancelToken: CancelToken(),
      saveDir: saveDir,
    );
    state = [...state, newTransfer];
    _startNextTransfer();
  }

  void addUpload(File file) {
    final newTransfer = FileTransfer(
      id: _uuid.v4(),
      filename: file.path.split('/').last,
      isDownload: false,
      cancelToken: CancelToken(),
      localPath: file.path,
    );
    state = [...state, newTransfer];
    _startNextTransfer();
  }

  Future<void> _startNextTransfer() async {
    final activeTransfers =
        state.where((t) => t.status == TransferStatus.inProgress);
    if (activeTransfers.length >= maxConcurrentTransfers) return;

    final pendingTransfer =
        state.firstWhereOrNull((t) => t.status == TransferStatus.pending);
    if (pendingTransfer == null) return;

    _updateTransferStatus(pendingTransfer.id, TransferStatus.inProgress);

    final fileService = ref.read(fileServiceProvider);
    
    final operation = pendingTransfer.isDownload
        ? fileService.downloadFile(
            pendingTransfer.filename,
            pendingTransfer.saveDir ?? '',
            onProgress: (bytesReceived, totalBytes) {
              _updateTransferProgress(
                  pendingTransfer.id, bytesReceived / totalBytes);
            },
            cancelToken: pendingTransfer.cancelToken,
          )
        : fileService.uploadFile(
            File(pendingTransfer.localPath!),
            onProgress: (bytesSent, totalBytes) {
              _updateTransferProgress(
                  pendingTransfer.id, bytesSent / totalBytes);
            },
            cancelToken: pendingTransfer.cancelToken,
          );

    try {
      final isSuccess = await operation;
      if (isSuccess) {
        _updateTransferStatus(pendingTransfer.id, TransferStatus.completed);
        ref.invalidate(fileListProvider); 
      } else {
        _updateTransferStatus(pendingTransfer.id, TransferStatus.cancelled);
      }
    } on DioException catch (e) {
      if (CancelToken.isCancel(e)) {
        _updateTransferStatus(pendingTransfer.id, TransferStatus.cancelled);
      } else {
        _updateTransferStatus(pendingTransfer.id, TransferStatus.failed,
            errorMessage: e.message);
      }
    } catch (e) {
      _updateTransferStatus(pendingTransfer.id, TransferStatus.failed,
          errorMessage: e.toString());
    } finally {
      _startNextTransfer();
    }
  }

  void _updateTransferProgress(String id, double progress) {
    state = [
      for (final t in state)
        if (t.id == id) t..progress = progress else t
    ];
  }

  void _updateTransferStatus(String id, TransferStatus newStatus,
      {String? errorMessage}) {
    state = [
      for (final t in state)
        if (t.id == id) t..status = newStatus..errorMessage = errorMessage else t
    ];
  }
  
  void removeTransfer(String id) {
    state = [
      for (final t in state)
        if (t.id != id) t
    ];
  }
  
  void cancelTransfer(String id) {
    final transfer = state.firstWhereOrNull((t) => t.id == id);
    if (transfer != null && transfer.status == TransferStatus.inProgress) {
      transfer.cancelToken.cancel('User cancelled transfer');
    }
  }
}

extension FirstWhereOrNullExtension<E> on Iterable<E> {
  E? firstWhereOrNull(bool Function(E) test) {
    for (final element in this) {
      if (test(element)) {
        return element;
      }
    }
    return null;
  }
}