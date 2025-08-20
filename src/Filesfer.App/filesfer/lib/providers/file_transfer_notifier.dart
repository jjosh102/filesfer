import 'dart:async';
import 'dart:io';
import 'package:dio/dio.dart';
import 'package:filesfer/models/file_transfer.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:filesfer/providers/providers.dart';
import 'package:uuid/uuid.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

final fileTransferNotifierProvider =
    StateNotifierProvider<FileTransferNotifier, List<FileTransfer>>((ref) {
  return FileTransferNotifier(ref);
});

class FileTransferNotifier extends StateNotifier<List<FileTransfer>> {
  final Ref ref;
  final int maxConcurrentTransfers = 10;
  final Uuid _uuid = const Uuid();
  static const Duration _updateInterval = Duration(milliseconds: 500);

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
    final activeTransfers = state.where(
      (t) => t.status == TransferStatus.inProgress,
    );
    if (activeTransfers.length >= maxConcurrentTransfers) return;

    final pendingTransfer = state.firstWhereOrNull(
      (t) => t.status == TransferStatus.pending,
    );

    if (pendingTransfer == null) {
      _maybeDisableWakelock();
      return;
    }

    _updateTransferState(
      pendingTransfer.id,
      (t) => t.copyWith(status: TransferStatus.inProgress),
    );

    await WakelockPlus.enable();
    final fileService = ref.read(fileServiceProvider);

    final operation = pendingTransfer.isDownload
        ? fileService.downloadFile(
            pendingTransfer.filename,
            pendingTransfer.saveDir ?? '',
            onProgress: (bytesReceived, totalBytes) {
              _updateTransferProgress(
                pendingTransfer.id,
                bytesReceived,
                totalBytes,
              );
            },
            cancelToken: pendingTransfer.cancelToken,
          )
        : fileService.uploadFile(
            File(pendingTransfer.localPath!),
            onProgress: (bytesSent, totalBytes) {
              _updateTransferProgress(
                pendingTransfer.id,
                bytesSent,
                totalBytes,
              );
            },
            cancelToken: pendingTransfer.cancelToken,
          );

    try {
      final isSuccess = await operation;
      if (isSuccess) {
        _updateTransferState(
          pendingTransfer.id,
          (t) => t.copyWith(status: TransferStatus.completed, progress: 1.0),
        );
        ref.invalidate(fileListProvider);
      } else {
        _updateTransferState(
          pendingTransfer.id,
          (t) => t.copyWith(status: TransferStatus.cancelled),
        );
      }
    } on DioException catch (e) {
      if (CancelToken.isCancel(e)) {
        _updateTransferState(
          pendingTransfer.id,
          (t) => t.copyWith(status: TransferStatus.cancelled),
        );
      } else {
        _updateTransferState(
          pendingTransfer.id,
          (t) => t.copyWith(status: TransferStatus.failed, errorMessage: e.message),
        );
      }
    } catch (e) {
      _updateTransferState(
        pendingTransfer.id,
        (t) => t.copyWith(status: TransferStatus.failed, errorMessage: e.toString()),
      );
    } finally {
      _maybeDisableWakelock();
      _startNextTransfer();
    }
  }

  void _updateTransferProgress(String id, int bytesTransferred, int totalBytes) {
    state = [
      for (final t in state)
        if (t.id == id)
          if (DateTime.now().difference(t.lastUIUpdate) >= _updateInterval)
            t.copyWith(
              progress: bytesTransferred / totalBytes,
              speed: _calculateSpeed(t, bytesTransferred),
              lastBytes: bytesTransferred,
              totalBytes: totalBytes,
              lastUpdateTime: DateTime.now(),
              lastUIUpdate: DateTime.now(),
            )
          else
            t
        else
          t,
    ];
  }

  double _calculateSpeed(FileTransfer transfer, int currentBytes) {
    final now = DateTime.now();
    final timeElapsed = now.difference(transfer.lastUpdateTime).inMilliseconds / 1000.0;
    
    if (timeElapsed == 0 || transfer.lastBytes == currentBytes) {
      return transfer.speed;
    }

    final bytesSinceLastUpdate = currentBytes - transfer.lastBytes;
    final speedInBytesPerSecond = bytesSinceLastUpdate / timeElapsed;
    return speedInBytesPerSecond;
  }

  void _updateTransferState(String id, FileTransfer Function(FileTransfer) update) {
    state = [
      for (final t in state)
        if (t.id == id)
          update(t)
        else
          t,
    ];
  }

  void _maybeDisableWakelock() {
    final hasActiveTransfers = state.any(
      (t) => t.status == TransferStatus.inProgress,
    );
    if (!hasActiveTransfers) {
      WakelockPlus.disable();
    }
  }

  void removeTransfer(String id) {
    state = [
      for (final t in state)
        if (t.id != id) t,
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