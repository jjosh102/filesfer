import 'package:filesfer/providers/ip_address_notifier.dart';
import 'package:filesfer/services/file_service.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:dio/dio.dart';
import 'package:shared_preferences/shared_preferences.dart';

final sharedPreferencesProvider = Provider<SharedPreferences>((ref) {
  throw UnimplementedError();
});

final baseUrlProvider = Provider<String>((ref) {
  return ref.watch(ipAddressProvider);
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

final fileListProvider = FutureProvider.autoDispose<List<String>>((ref) {
  ref.watch(ipAddressProvider);
  return ref.read(fileServiceProvider).fetchFiles();
});

final viewModeProvider = StateProvider<bool>((ref) => true);
final qrCodeProvider = StateProvider<String?>((ref) => null);
final selectedFilesCountProvider = StateProvider<int>((ref) => 0);