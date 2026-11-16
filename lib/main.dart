import 'package:flutter/material.dart';
import 'package:flutter_patcher/flutter_patcher.dart';

import 'ota/ota_screen.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // Loads the installed OTA patch (if any) and enables crash protection.
  await FlutterPatcher.init();
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Learn OTA',
      theme: ThemeData(
        colorScheme: .fromSeed(seedColor: Colors.deepPurple),
      ),
      home: const HomePage(),
    );
  }
}

class HomePage extends StatelessWidget {
  const HomePage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
        title: const Text('Learn OTA'),
        actions: [
          IconButton(
            icon: const Icon(Icons.system_update),
            tooltip: 'OTA updates',
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const OtaScreen()),
            ),
          ),
        ],
      ),
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            FilledButton(
              onPressed: () => ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Hello Patch 1')),
              ),
              child: const Text('Hello Patch 1'),
            ),
            const SizedBox(height: 16),
            FilledButton(
              onPressed: () => ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Hello Patch 2')),
              ),
              child: const Text('Hello Patch 2'),
            ),
          ],
        ),
      ),
    );
  }
}
