import 'package:dio/dio.dart';

enum TransferStatus { pending, inProgress, completed, failed, cancelled }

class FileTransfer {
  final String id;
  final String filename;
  final bool isDownload;
  final CancelToken cancelToken;
  final String? saveDir;
  final String? localPath;
  final TransferStatus status;
  final double progress;
  final String? errorMessage;
  final double speed;
  final int lastBytes;
  final int totalBytes;
  final DateTime lastUpdateTime;
  final DateTime lastUIUpdate;

  FileTransfer({
    required this.id,
    required this.filename,
    required this.isDownload,
    required this.cancelToken,
    this.saveDir,
    this.localPath,
    this.status = TransferStatus.pending,
    this.progress = 0.0,
    this.errorMessage,
    this.speed = 0.0,
    this.lastBytes = 0,
    this.totalBytes = 0,
    DateTime? lastUpdateTime,
    DateTime? lastUIUpdate,
  }) : lastUpdateTime = lastUpdateTime ?? DateTime.now(),
       lastUIUpdate = lastUIUpdate ?? DateTime.now();

  FileTransfer copyWith({
    String? id,
    String? filename,
    bool? isDownload,
    CancelToken? cancelToken,
    String? saveDir,
    String? localPath,
    TransferStatus? status,
    double? progress,
    String? errorMessage,
    double? speed,
    int? lastBytes,
    int? totalBytes,
    DateTime? lastUpdateTime,
    DateTime? lastUIUpdate,
  }) {
    return FileTransfer(
      id: id ?? this.id,
      filename: filename ?? this.filename,
      isDownload: isDownload ?? this.isDownload,
      cancelToken: cancelToken ?? this.cancelToken,
      saveDir: saveDir ?? this.saveDir,
      localPath: localPath ?? this.localPath,
      status: status ?? this.status,
      progress: progress ?? this.progress,
      errorMessage: errorMessage ?? this.errorMessage,
      speed: speed ?? this.speed,
      lastBytes: lastBytes ?? this.lastBytes,
      totalBytes: totalBytes ?? this.totalBytes,
      lastUpdateTime: lastUpdateTime ?? this.lastUpdateTime,
      lastUIUpdate: lastUIUpdate ?? this.lastUIUpdate,
    );
  }
}
