import 'dart:async';
import 'dart:convert';
import 'dart:io';

class FileService {
  final String host;
  final int port;
  final Duration timeout;

  Socket? _socket;
  final StreamController<String> _responseController =
      StreamController<String>.broadcast();
  final _responseSubscription = <StreamSubscription>[];

  FileService({
    required this.host,
    required this.port,
    this.timeout = const Duration(seconds: 10),
  });

  Future<void> _connect() async {
    if (_socket != null) {
      return;
    }

    try {
      _socket = await Socket.connect(host, port, timeout: timeout);
      _socket!.listen(
        (data) {
          final messages = utf8.decode(data).split('\n');
          for (var msg in messages) {
            if (msg.isNotEmpty) {
              _responseController.add(msg);
            }
          }
        },
        onDone: () {
          disconnect();
        },
        onError: (error) {
          disconnect();
        },
        cancelOnError: true,
      );
    } on SocketException catch (e) {
      throw Exception('Failed to connect to server: $e');
    }
  }

  Future<void> disconnect() async {
    for (var sub in _responseSubscription) {
      await sub.cancel();
    }
    _responseSubscription.clear();

    if (_socket != null) {
      await _socket!.close();
      _socket = null;
    }
  }

  Future<List<String>> fetchFiles() async {
    await _connect();

    final completer = Completer<List<String>>();

    var sub = _responseController.stream.listen((msg) {
      if (msg.startsWith('LIST|')) {
        final fileList = msg.substring('LIST|'.length);
        completer.complete(fileList.isEmpty ? [] : fileList.split('|'));
      } else if (msg.startsWith('ERROR|')) {
        completer.completeError(
          Exception('Server error: ${msg.substring('ERROR|'.length)}'),
        );
      }
    });

    _responseSubscription.add(sub);
    _socket!.write('LIST\n');

    try {
      final result = await completer.future.timeout(timeout);
      await sub.cancel();
      _responseSubscription.remove(sub);
      return result;
    } on TimeoutException {
      await sub.cancel();
      _responseSubscription.remove(sub);
      throw TimeoutException('Timeout while waiting for file list.');
    } on Exception catch (_) {
      await sub.cancel();
      _responseSubscription.remove(sub);
      rethrow;
    }
  }

  Future<bool> downloadFile(
    String filename,
    String savePath, {
    required void Function(int bytesReceived, int totalBytes) onProgress,
    bool Function()? isCancelled,
  }) async {
    await _connect();

    _socket!.write('DOWNLOAD|$filename\n');

    final completer = Completer<bool>();
    late StreamSubscription<String> sub;

    sub = _responseController.stream.listen((msg) async {
      if (msg.startsWith('DOWNLOAD_START|')) {
        final totalBytes = int.parse(msg.substring('DOWNLOAD_START|'.length));
        await sub.cancel();

        final file = File(savePath);
        final sink = file.openWrite();
        int bytesReceived = 0;

        _socket!.listen(
          (data) async {
            if (isCancelled != null && isCancelled()) {
              _socket!.close();
              await sink.close();
              completer.complete(false);
              return;
            }

            sink.add(data);
            bytesReceived += data.length;
            onProgress(bytesReceived, totalBytes);

            if (bytesReceived >= totalBytes) {
              _socket!.listen(
                (data) async {
                  if (utf8.decode(data).trim() == 'DOWNLOAD_DONE') {
                    await sink.close();
                    completer.complete(true);
                    _socket!.close();
                  }
                },
                onDone: () =>
                    completer.completeError('Connection closed prematurely'),
                onError: (error) {
                  sink.close();
                  completer.completeError(error);
                },
              );
            }
          },
          onError: (error) {
            sink.close();
            completer.completeError(error);
          },
        );
      } else if (msg.startsWith('ERROR|')) {
        completer.completeError(
          Exception('Server error: ${msg.substring('ERROR|'.length)}'),
        );
        sub.cancel();
      }
    });

    _socket!.write('DOWNLOAD|$filename\n');

    try {
      return await completer.future.timeout(timeout);
    } on TimeoutException {
      await sub.cancel();
      throw TimeoutException('Download timed out.');
    } on Exception {
      await sub.cancel();
      rethrow;
    }
  }

  Future<bool> uploadFile(
    File file, {
    required void Function(int bytesSent, int totalBytes) onProgress,
    required void Function() onCancel,
    bool Function()? isCancelled,
  }) async {
    if (!file.existsSync()) {
      throw Exception('File does not exist: ${file.path}');
    }
    await _connect();

    final completer = Completer<bool>();
    final filename = file.uri.pathSegments.last;
    final totalBytes = await file.length();

    _socket!.write('UPLOAD_INIT|$filename|$totalBytes\n');

    late StreamSubscription<String> sub;
    sub = _responseController.stream.listen((msg) async {
      if (msg == 'UPLOAD_COMPLETE') {
        await sub.cancel();
        completer.complete(true);
      } else if (msg.startsWith('ERROR|')) {
        await sub.cancel();
        completer.completeError(
          Exception('Server upload error: ${msg.substring('ERROR|'.length)}'),
        );
      }
    });

    try {
      final ackCompleter = Completer<void>();
      _responseController.stream
          .firstWhere((msg) => msg == 'UPLOAD_ACK' || msg.startsWith('ERROR|'))
          .then((msg) {
            if (msg == 'UPLOAD_ACK') {
              ackCompleter.complete();
            } else {
              ackCompleter.completeError(
                Exception('Server rejected upload: $msg'),
              );
            }
          });

      await ackCompleter.future.timeout(timeout);

      final fileStream = file.openRead();
      int bytesSent = 0;

      await for (var chunk in fileStream) {
        if (isCancelled != null && isCancelled()) {
          _socket!.write('UPLOAD_CANCEL\n');
          onCancel();
          throw Exception('Upload cancelled by user.');
        }

        _socket!.add(chunk);
        bytesSent += chunk.length;
        onProgress(bytesSent, totalBytes);

        await _socket!.flush();
      }


      _socket!.write('UPLOAD_DONE\n');

      return await completer.future.timeout(timeout);
    } on TimeoutException {
      await sub.cancel();
      throw TimeoutException('Upload timed out.');
    } on Exception catch (e) {
      await sub.cancel();
      rethrow;
    } finally {
      await sub.cancel();
    }
  }
}
