import 'package:filesfer/services/file_service.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;

final httpClientProvider = Provider<http.Client>((ref) {
  final client = http.Client();
  ref.onDispose(() => client.close());
  return client;
});

final fileServiceProvider = Provider<FileService>((ref) {
  final client = ref.watch(httpClientProvider);
  return FileService(client: client);
});

final fileListProvider = FutureProvider<List<String>>((ref) {
  return ref.read(fileServiceProvider).fetchFiles();
});
