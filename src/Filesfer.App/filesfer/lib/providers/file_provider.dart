import 'package:filesfer/services/file_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';



final tcpHostProvider = Provider<String>((ref) {
  if (bool.fromEnvironment('dart.vm.product')) {
    return dotenv.env['PRODUCTION_TCP_HOST'] ?? 'prod.tcpserver.com';
  } else {
    return dotenv.env['DEV_TCP_HOST'] ?? 'localhost';
  }
});

// final tcpPortProvider = Provider<int>((ref) {
//   if (bool.fromEnvironment('dart.vm.product')) {
//     return int.tryParse(dotenv.env['PRODUCTION_TCP_PORT'] ?? '') ?? 9000;
//   } else {
//     return int.tryParse(dotenv.env['DEV_TCP_PORT'] ?? '') ?? 9000;
//   }
// });

final fileServiceProvider = Provider<FileService>((ref) {
 // final host = ref.watch(tcpHostProvider);
  //final port = ref.watch(tcpPortProvider);
  return FileService(host: '10.0.2.2', port: 9000);
});

final fileListProvider = FutureProvider<List<String>>((ref) async {
  final service = ref.read(fileServiceProvider);
  return await service.fetchFiles();
});

final themeModeProvider = StateProvider<ThemeMode>((ref) {
  final brightness = WidgetsBinding.instance.platformDispatcher.platformBrightness;
  return brightness == Brightness.dark ? ThemeMode.dark : ThemeMode.light;
});

final viewModeProvider = StateProvider<bool>((ref) => true);


