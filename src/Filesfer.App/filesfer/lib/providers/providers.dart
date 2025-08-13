import 'package:filesfer/services/file_service.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart' show kReleaseMode;
import 'package:shared_preferences/shared_preferences.dart';

final baseUrlProvider = Provider<String>((ref) {
  if (kReleaseMode) {
    return dotenv.env['PRODUCTION_API_URL']!;
  } else {
    return dotenv.env['DEV_API_URL']!;
  }
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


final viewModeProvider = StateProvider<bool>((ref) => true);

final serverStatusStreamProvider = StreamProvider.autoDispose<bool>((
  ref,
) async* {
  final service = ref.read(fileServiceProvider);

  while (true) {
    try {
      final isUp = await service.isServerUp();
      yield isUp;
    } catch (_) {
      yield false;
    }
    await Future.delayed(const Duration(seconds: 60));
  }
});

//initialize shared preferences during app startup
final sharedPreferencesProvider = Provider<SharedPreferences>((ref) {
  throw UnimplementedError();
});
