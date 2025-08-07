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
      throw Exception('Failed to load file list');
    }
  }

  Future<void> downloadFile(String filename, String savePath) async {
    final request = http.Request(
      'GET',
      Uri.parse('$baseUrl/download/$filename'),
    );

    final response = await _client.send(request);

    if (response.statusCode == 200) {
      final file = File('$savePath/$filename');
      final sink = file.openWrite();

      await response.stream.pipe(sink);
      await sink.flush();
      await sink.close();
    } else {
      throw Exception(
        'Failed to download file. Status: ${response.statusCode}',
      );
    }
  }

  Future<void> uploadFile(File file) async {
    final uri = Uri.parse('$baseUrl/upload');

    if (!file.existsSync()) {
      throw Exception('File does not exist: ${file.path}');
    }

    final request = http.MultipartRequest('POST', uri);
    request.files.add(await http.MultipartFile.fromPath('file', file.path));

    final response = await request.send();

    if (response.statusCode != 200) {
      final body = await response.stream.bytesToString();
      throw Exception('Upload failed: ${response.statusCode}, body: $body');
    }
  }
}
