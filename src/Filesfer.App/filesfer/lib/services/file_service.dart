import 'dart:async';
import 'dart:io';
import 'package:dio/dio.dart';

class FileService {
  final Dio _dio;

  FileService({required Dio dio}) : _dio = dio;

  Future<List<String>> fetchFiles() async {
    final response = await _dio.get('/files');
    if (response.statusCode == 200) {
      return List<String>.from(response.data);
    } else {
      throw Exception('Failed to load file list: ${response.statusMessage}');
    }
  }

  Future<bool> downloadFile(
    String filename,
    String savePath, {
    required void Function(int bytesReceived, int totalBytes) onProgress,
    required CancelToken cancelToken,
  }) async {
    try {
      await _dio.download(
        '/download/$filename',
        savePath,
        onReceiveProgress: onProgress,
        cancelToken: cancelToken,
        deleteOnError: true,
        options: Options(
          responseType: ResponseType.stream,
          followRedirects: false,
          receiveTimeout: const Duration(minutes: 5),
          sendTimeout: const Duration(minutes: 5),
        ),
      );
      return true;
    } on DioException catch (e) {
      if (CancelToken.isCancel(e)) {
        return false;
      }
      return false;
    } catch (e) {
      return false;
    }
  }

  Future<bool> uploadFile(
    File file, {
    required void Function(int bytesSent, int totalBytes) onProgress,
    required CancelToken cancelToken,
  }) async {
    if (!file.existsSync()) {
      throw Exception('File does not exist: ${file.path}');
    }

    final formData = FormData.fromMap({
      'file': await MultipartFile.fromFile(
        file.path,
        filename: file.path.split('/').last,
      ),
    });

    try {
      await _dio.post(
        '/upload',
        data: formData,
        cancelToken: cancelToken,
        onSendProgress: onProgress,
      );
      return true;
    } on DioException catch (e) {
      if (CancelToken.isCancel(e)) {
        return false;
      }
      return false;
    }
  }

  Future<bool> isServerUp() async {
    try {
      final response = await _dio.get('/health');
      return response.statusCode == 200;
    } catch (_) {
      return false;
    }
  }
}
