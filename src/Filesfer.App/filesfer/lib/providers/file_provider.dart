import 'package:filesfer/services/file_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:dio/dio.dart';

final baseUrlProvider = Provider<String>((ref) {
  return 'http://10.0.2.2:5000';
});

final fileServiceProvider = Provider<FileService>((ref) {
  final baseUrl = ref.watch(baseUrlProvider);
  return FileService(
    dio: Dio(
      BaseOptions(
        baseUrl: baseUrl,
        receiveTimeout: const Duration(minutes: 30),
        connectTimeout: const Duration(seconds: 30),
        sendTimeout: const Duration(minutes: 30),
      ),
    ),
  );
});

final cancelTokenProvider = StateProvider<CancelToken>((ref) => CancelToken());

void resetCancelToken(WidgetRef ref) {
  ref.read(cancelTokenProvider.notifier).state = CancelToken();
}

final fileListProvider = FutureProvider<List<String>>((ref) {
  return ref.read(fileServiceProvider).fetchFiles();
});

final downloadProgressProvider = StateProvider<double>((ref) => 0.0);
final uploadedProgressProvider = StateProvider<double>((ref) => 0.0);
final downloadedFileNameProvider = StateProvider<String?>((ref) => null);

final themeModeProvider = StateProvider<ThemeMode>((ref) {
  final brightness =
      WidgetsBinding.instance.platformDispatcher.platformBrightness;
  return brightness == Brightness.dark ? ThemeMode.dark : ThemeMode.light;
});

final viewModeProvider = StateProvider<bool>((ref) => true);
