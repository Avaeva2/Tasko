// Local development only: uses the verification account created by native tests.
// No credentials are stored in this source or used by the main app entrypoint.
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:tasko/legacy/data/tasko_store.dart';
import 'package:tasko/legacy/legacy_main.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  const url = String.fromEnvironment('SUPABASE_URL');
  if (!url.startsWith('http://127.0.0.1:')) {
    throw StateError('Showcase bootstrap is only for local Supabase.');
  }
  await Supabase.initialize(
    url: url,
    publishableKey: const String.fromEnvironment('SUPABASE_ANON_KEY'),
  );
  final store = TaskoStore(client: Supabase.instance.client);
  await store.initialize();
  if (!store.isAuthenticated) {
    await store.signIn(
      const String.fromEnvironment('TASKO_TEST_EMAIL'),
      const String.fromEnvironment('TASKO_TEST_PASSWORD'),
    );
  }
  runApp(TaskoApp(store: store));
}
