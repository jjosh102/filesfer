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
    late File file;
    late IOSink sink;
    int totalBytes = 0;
    int bytesReceived = 0;
    bool downloadStarted = false;

    sub = _responseController.stream.listen((msg) async {
      if (isCancelled != null && isCancelled()) {
        await sub.cancel();
        completer.complete(false);
        return;
      }

      if (msg.startsWith('DOWNLOAD_START|')) {
        totalBytes = int.parse(msg.substring('DOWNLOAD_START|'.length));
        file = File(savePath);
        sink = file.openWrite();
        downloadStarted = true;
      } else if (msg.startsWith('DOWNLOAD_CHUNK|')) {
        if (downloadStarted) {
          final bytes = base64Decode(msg.substring('DOWNLOAD_CHUNK|'.length));
          sink.add(bytes);
          bytesReceived += bytes.length;
          onProgress(bytesReceived, totalBytes);
        }
      } else if (msg == 'DOWNLOAD_DONE') {
        await sink.close();
        await sub.cancel();
        completer.complete(true);
      } else if (msg.startsWith('ERROR|')) {
        print('Download error: ${msg.substring('ERROR|'.length)}');
        if (downloadStarted) await sink.close();
        await sub.cancel();
        completer.complete(false);
      }
    });

    _responseSubscription.add(sub);

    try {
      return await completer.future.timeout(timeout);
    } on TimeoutException {
      if (downloadStarted) await sink.close();
      await sub.cancel();
      throw TimeoutException('Download timed out.');
    } finally {
      _responseSubscription.remove(sub);
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
      if (msg == 'UPLOAD_ACK') {
        final fileStream = file.openRead();
        int bytesSent = 0;

        await for (var chunk in fileStream) {
          if (isCancelled != null && isCancelled()) {
            _socket!.write('UPLOAD_CANCEL\n');
            await sub.cancel();
            onCancel(); 
            completer.complete(false);
            return;
          }

          _socket!.add(chunk);
          bytesSent += chunk.length;
          onProgress(bytesSent, totalBytes);
        }

        _socket!.write('UPLOAD_DONE\n');
      } else if (msg == 'UPLOAD_COMPLETE') {
        await sub.cancel();
        completer.complete(true);
      } else if (msg.startsWith('ERROR|')) {
        await sub.cancel();
        completer.complete(false);
        throw Exception(
          'Server upload error: ${msg.substring('ERROR|'.length)}',
        );
      }
    });

    _responseSubscription.add(sub);

    try {
      return await completer.future.timeout(timeout);
    } on TimeoutException {
      await sub.cancel();
      throw TimeoutException('Upload timed out.');
    } finally {
      _responseSubscription.remove(sub);
    }
  }
}
