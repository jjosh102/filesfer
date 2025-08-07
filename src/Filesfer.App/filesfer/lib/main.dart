import 'package:filesfer/screens/file_transfer_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

void main() {
  runApp(const ProviderScope(child: MyApp()));
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Filesfer',
      theme: ThemeData.dark().copyWith(
        scaffoldBackgroundColor: const Color(
          0xFF0D1117,
        ), 
        cardColor: const Color(0xFF161B22), 
        textTheme: ThemeData.dark().textTheme.apply(
          bodyColor: Colors.white,
          displayColor: Colors.white,
        ),
        chipTheme: ChipThemeData.fromDefaults(
          secondaryColor: Colors.grey[800]!,
          brightness: Brightness.dark,
          labelStyle: const TextStyle(color: Colors.white),
        ),
      ),
      home: const FileTransferScreen(),
    );
  }
}
