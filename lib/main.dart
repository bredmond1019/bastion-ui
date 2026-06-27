import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

void main() {
  runApp(const ProviderScope(child: BastionApp()));
}

/// Root application widget — thin shell; screens are wired per block.
class BastionApp extends StatelessWidget {
  const BastionApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'BastionUI',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.blueGrey),
        useMaterial3: true,
      ),
      // Home routes to the settings/connection surface.
      // Task 6 replaces this placeholder once the banner is wired.
      home: const _PlaceholderHome(),
    );
  }
}

/// Placeholder home widget — replaced in Task 6 when the connection banner
/// and settings route are wired into the full shell.
class _PlaceholderHome extends StatelessWidget {
  const _PlaceholderHome();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('BastionUI')),
      body: const Center(
        child: Text('Settings / connection surface — wired in Task 6'),
      ),
    );
  }
}
