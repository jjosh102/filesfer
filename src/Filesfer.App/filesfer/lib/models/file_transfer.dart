import 'package:dio/dio.dart';

enum TransferStatus { pending, inProgress, completed, failed, cancelled }

class FileTransfer {
  final String id;
  final String filename;
  final bool isDownload;
  final CancelToken cancelToken;
  TransferStatus status;
  double progress;
  String? errorMessage;
  String? localPath;
  String? saveDir;

  FileTransfer({
    required this.id,
    required this.filename,
    required this.isDownload,
    required this.cancelToken,
    this.status = TransferStatus.pending,
    this.progress = 0.0,
    this.errorMessage,
    this.localPath,
    this.saveDir,
  });
}