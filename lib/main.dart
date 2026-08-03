import 'package:flutter/material.dart';
import 'services/local_database.dart';
import 'screens/login_screen.dart';
import 'screens/posko_client_screen.dart';
import 'theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await LocalDatabase.instance.init();
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'ELDN Local Edge Server',
      theme: appTheme,
      home: LoginScreen(database: LocalDatabase.instance),
      routes: {PoskoClientScreen.routeName: (_) => const PoskoClientScreen()},
      debugShowCheckedModeBanner: false,
    );
  }
}
