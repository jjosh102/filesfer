import 'dart:async';
import 'package:filesfer/providers/providers.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

final ipAddressProvider = StateNotifierProvider<IpAddressNotifier, String>((
  ref,
) {
  final prefs = ref.read(sharedPreferencesProvider);
  return IpAddressNotifier(prefs);
});

class IpAddressNotifier extends StateNotifier<String> {
  final SharedPreferences _prefs;
  IpAddressNotifier(this._prefs)
    : super(_prefs.getString('server_ip') ?? 'http://localhost:8080');

  Future<void> setIpAddress(String ip) async {
    state = ip;
    await _prefs.setString('server_ip', ip);
  }
}
