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

    final completer = Completer<bool>();
    final file = File(savePath);
    final sink = file.openWrite();
    late StreamSubscription<String> sub;

    sub = _responseController.stream.listen(
      (msg) async {
        if (msg.startsWith('DOWNLOAD_START|')) {
          await sub.cancel(); 

          final totalBytes = int.parse(msg.substring('DOWNLOAD_START|'.length));
          int bytesReceived = 0;

          try {
           
            await for (var chunk in _socket!) {
              if (isCancelled != null && isCancelled()) {
                await sink.close();
                _socket!.close();
                completer.complete(false);
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

            final doneMsg = await _responseController.stream.firstWhere(
              (m) => m.startsWith('DOWNLOAD_DONE'),
              orElse: () => 'ERROR|Connection closed prematurely',
            );

            if (doneMsg == 'DOWNLOAD_DONE') {
              completer.complete(true);
            } else {
              completer.completeError(Exception('Server error: $doneMsg'));
            }
          } on Exception catch (e) {
            await sink.close();
            completer.completeError(e);
          }
        } else if (msg.startsWith('ERROR|')) {
          completer.completeError(Exception(msg.substring('ERROR|'.length)));
          await sub.cancel();
        }
      },
      onError: (error) {
        if (!completer.isCompleted) {
          completer.completeError(error);
        }
      },
      onDone: () {
        if (!completer.isCompleted) {
          completer.completeError(Exception('Connection closed prematurely.'));
        }
      },
    );

    _socket!.write('DOWNLOAD|$filename\n');

    try {
      return await completer.future.timeout(timeout);
    } on TimeoutException {
      await sub.cancel();
      await sink.close();
      throw TimeoutException('Download timed out.');
    } on Exception {
      await sub.cancel();
      await sink.close();
      rethrow;
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
    late StreamSubscription<String> sub;

    sub = _responseController.stream.listen(
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
      return await completer.future.timeout(timeout);
    } on TimeoutException {
      await sub.cancel();
      throw TimeoutException('Upload timed out.');
    } finally {
      await sub.cancel();
    }
  }
}
