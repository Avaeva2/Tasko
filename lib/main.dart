import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'student/student_app.dart';
import 'student/student_store.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  if (kIsWeb) SemanticsBinding.instance.ensureSemantics();
  const url = String.fromEnvironment('SUPABASE_URL');
  const key = String.fromEnvironment('SUPABASE_ANON_KEY');
  SupabaseClient? client;
  if (url.isNotEmpty && key.isNotEmpty) {
    await Supabase.initialize(
      url: url,
      publishableKey: key,
      authOptions: FlutterAuthClientOptions(
        localStorage: SharedPreferencesLocalStorage(
          persistSessionKey:
              'tasko.students.auth.v1.${Uri.parse(url).authority}',
        ),
      ),
    );
    client = Supabase.instance.client;
  }
  final store = StudentStore(client: client);
  await store.initialize();
  if (const bool.fromEnvironment('TASKO_STUDENTS_DEMO') ||
      const bool.fromEnvironment('TASKO_DEMO')) {
    await store.enterDemo();
  }
  runApp(StudentApp(store: store));
}
