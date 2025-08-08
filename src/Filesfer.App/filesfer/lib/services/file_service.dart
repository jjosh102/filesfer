import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;

const String baseUrl = 'http://10.0.2.2:5000';

class FileService {
  final http.Client _client;

  FileService({required http.Client client}) : _client = client;
  Future<List<String>> fetchFiles() async {
    final response = await _client.get(Uri.parse('$baseUrl/files'));
    if (response.statusCode == 200) {
      return List<String>.from(jsonDecode(response.body));
    } else {
      throw Exception('Failed to load file list- ${response.reasonPhrase}');
    }
  }

  Future<void> downloadFile(
    String filename,
    String savePath, {
    required void Function(int bytesReceived, int totalBytes) onProgress,
  }) async {
    final request = http.Request(
      'GET',
      Uri.parse('$baseUrl/download/$filename'),
    );

    final response = await _client.send(request);

    if (response.statusCode != 200) {
      throw Exception(
        'Failed to download file. Status: ${response.statusCode}',
      );
    }

    final totalBytes = response.contentLength ?? 0;
    int bytesReceived = 0;

    final file = File('$savePath/$filename');
    final sink = file.openWrite();

    try {
      await for (final chunk in response.stream) {
        bytesReceived += chunk.length;
        sink.add(chunk);
        onProgress(bytesReceived, totalBytes);
      }
    } catch (e) {
      throw Exception('Download failed: $e');
    } finally {
      await sink.close();
    }
  }

  Future<void> uploadFile(
    File file, {
    required void Function(int bytesSent, int totalBytes) onProgress,
  }) async {
    final uri = Uri.parse('$baseUrl/upload');

    if (!file.existsSync()) {
      throw Exception('File does not exist: ${file.path}');
    }

    final totalBytes = await file.length();
    int bytesSent = 0;

    final request = http.MultipartRequest('POST', uri);

    request.files.add(
      http.MultipartFile(
        'file',
        file.openRead().map((chunk) {
          bytesSent += chunk.length;
          onProgress(bytesSent, totalBytes);
          return chunk;
        }),
        totalBytes,
        filename: file.path.split('/').last,
      ),
    );

    final response = await request.send();

    if (response.statusCode != 200) {
      final body = await response.stream.bytesToString();
      throw Exception('Upload failed: ${response.statusCode}, body: $body');
    }
  }
}
