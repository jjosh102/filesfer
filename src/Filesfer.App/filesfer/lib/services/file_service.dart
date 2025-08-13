import 'dart:async';
import 'dart:convert';
import 'dart:io';

class FileService {
  final String host;
  final int port;
  final Duration timeout;

  Socket? _socket;
  final StreamController<List<int>> _socketDataController =
      StreamController<List<int>>.broadcast();

  FileService({
    required this.host,
    required this.port,
    this.timeout = const Duration(minutes: 10),
  });

  Future<void> _connect() async {
    if (_socket != null) {
      return;
    }

    try {
      _socket = await Socket.connect(host, port, timeout: timeout);
      _socket!.listen(
        (data) {
          _socketDataController.add(data);
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
    if (_socket != null) {
      await _socket!.close();
      _socket = null;
    }
  }

  Future<List<String>> fetchFiles() async {
    await _connect();

    final completer = Completer<List<String>>();
    final controlMessageStream = _socketDataController.stream
        .transform(Utf8Decoder())
        .transform(const LineSplitter());

    late StreamSubscription<String> sub;
    sub = controlMessageStream.listen((msg) {
      if (msg.startsWith('LIST|')) {
        final fileList = msg.substring('LIST|'.length);
        completer.complete(fileList.isEmpty ? [] : fileList.split('|'));
      } else if (msg.startsWith('ERROR|')) {
        completer.completeError(
          Exception('Server error: ${msg.substring('ERROR|'.length)}'),
        );
      }
    });

    _socket!.write('LIST\n');

    try {
      final result = await completer.future.timeout(timeout);
      await sub.cancel();
      return result;
    } on TimeoutException {
      await sub.cancel();
      throw TimeoutException('Timeout while waiting for file list.');
    } on Exception catch (_) {
      await sub.cancel();
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

    final completer = Completer<bool>();
    final file = File(savePath);
    final sink = file.openWrite();

    final controlMessageStream = _socketDataController.stream
        .transform(Utf8Decoder())
        .transform(const LineSplitter());
    late StreamSubscription<String> controlMessageSubscription;

    controlMessageSubscription = controlMessageStream.listen(
      (msg) async {
        if (completer.isCompleted) return; 

        if (msg.startsWith('DOWNLOAD_START|')) {
          await controlMessageSubscription.cancel();
          final totalBytes = int.parse(msg.substring('DOWNLOAD_START|'.length));
          int bytesReceived = 0;

          try {
            await for (var chunk in _socketDataController.stream) {
              if (isCancelled != null && isCancelled()) {
                await sink.close();
                if (!completer.isCompleted) {
                  completer.complete(false); 
                }
                return;
              }

              sink.add(chunk);
              bytesReceived += chunk.length;
              onProgress(bytesReceived, totalBytes);

              if (bytesReceived >= totalBytes) {
                await sink.close();
                break;
              }
            }

            final doneMsg = await controlMessageStream
                .firstWhere(
                  (m) =>
                      m.startsWith('DOWNLOAD_DONE') || m.startsWith('ERROR|'),
                  orElse: () => 'ERROR|Connection closed prematurely',
                )
                .timeout(timeout);

            if (doneMsg == 'DOWNLOAD_DONE') {
              if (!completer.isCompleted) {
                completer.complete(true); 
              }
            } else {
              if (!completer.isCompleted) {
                completer.completeError(
                  Exception(
                    'Server error: ${doneMsg.substring('ERROR|'.length)}',
                  ),
                );
              }
            }
          } on Exception catch (e) {
            await sink.close();
            if (!completer.isCompleted) {
              completer.completeError(e); 
            }
          }
        } else if (msg.startsWith('ERROR|')) {
          await controlMessageSubscription.cancel();
          await sink.close();
          if (!completer.isCompleted) {
            completer.completeError(
              Exception(msg.substring('ERROR|'.length)),
            ); 
          }
        }
      },
      onError: (error) {
        if (!completer.isCompleted) {
          completer.completeError(error);
        }
      },
      onDone: () {
        if (!completer.isCompleted) {
          completer.completeError(Exception('Connection closed unexpectedly.'));
        }
      },
    );

    _socket!.write('DOWNLOAD|$filename\n');

    try {
      return await completer.future.timeout(timeout);
    } on TimeoutException {
      if (!completer.isCompleted) {
        await controlMessageSubscription.cancel();
        await sink.close();
        completer.completeError(TimeoutException('Download timed out.'));
      }
      rethrow;
    } finally {
      if (!completer.isCompleted) {
        await controlMessageSubscription.cancel();
      }
    }
  }

  Future<bool> uploadFile(
    File file, {
    required void Function(int bytesSent, int totalBytes) onProgress,
    bool Function()? isCancelled,
  }) async {
    if (!file.existsSync()) {
      throw Exception('File does not exist: ${file.path}');
    }
    await _connect();

    final filename = file.uri.pathSegments.last;
    final totalBytes = await file.length();
    final completer = Completer<bool>();

    final controlMessageStream = _socketDataController.stream
        .transform(Utf8Decoder())
        .transform(const LineSplitter());

    late StreamSubscription<String> sub;
    sub = controlMessageStream.listen(
      (msg) async {
        if (msg == 'UPLOAD_ACK') {
          try {
            final fileStream = file.openRead();
            int bytesSent = 0;

            await for (var chunk in fileStream) {
              if (isCancelled != null && isCancelled()) {
                _socket!.write('UPLOAD_CANCEL\n');
                completer.complete(false);
                return;
              }

              _socket!.add(chunk);
              bytesSent += chunk.length;
              onProgress(bytesSent, totalBytes);
              await _socket!.flush();
            }

            _socket!.write('UPLOAD_DONE\n');
          } catch (e) {
            _socket!.write('UPLOAD_CANCEL\n');
            completer.completeError(e);
          }
        } else if (msg == 'UPLOAD_COMPLETE') {
          completer.complete(true);
          await sub.cancel();
        } else if (msg.startsWith('ERROR|')) {
          completer.completeError(Exception(msg.substring('ERROR|'.length)));
          await sub.cancel();
        }
      },
      onError: (error) {
        if (!completer.isCompleted) {
          completer.completeError(error);
        }
        sub.cancel();
      },
      onDone: () {
        if (!completer.isCompleted) {
          completer.completeError(Exception('Connection closed unexpectedly.'));
        }
      },
    );

    _socket!.write('UPLOAD_INIT|$filename|$totalBytes\n');

    try {
      final ackMessage = await controlMessageStream
          .firstWhere((msg) => msg == 'UPLOAD_ACK' || msg.startsWith('ERROR|'))
          .timeout(timeout);

      if (ackMessage.startsWith('ERROR|')) {
        await sub.cancel();
        throw Exception(ackMessage.substring('ERROR|'.length));
      }

      return await completer.future.timeout(timeout);
    } on TimeoutException {
      await sub.cancel();
      throw TimeoutException('Upload timed out.');
    } finally {
      await sub.cancel();
    }
  }
}
