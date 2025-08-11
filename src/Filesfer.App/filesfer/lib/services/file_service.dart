import 'dart:async';
import 'dart:io';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';

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

  Future<void> downloadFile(
    String filename,
    String savePath, {
    required void Function(int bytesReceived, int totalBytes) onProgress,
    required CancelToken cancelToken,
  }) async {
    try {
      await _dio.download(
        '/download/$filename',
        '$savePath/$filename',
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
    } on DioException catch (e) {
      debugPrint('❌ DioException: ${e.message}');
      debugPrint('📦 Response: ${e.response}');

      if (CancelToken.isCancel(e)) {
        throw Exception('Download cancelled');
      }
      throw Exception('Download failed: ${e.message ?? 'Unknown error'}');
    } catch (e) {
      debugPrint('❌ Unexpected error: $e');
      rethrow;
    }
  }

  Future<void> uploadFile(
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
    } on DioException catch (e) {
      if (CancelToken.isCancel(e)) {
        throw Exception('Upload cancelled');
      }
      throw Exception('Upload failed: ${e.message}');
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
