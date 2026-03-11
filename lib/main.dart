import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

void main() {
  runApp(const ProviderScope(child: PixoraTestApp()));
}

class PixoraTestApp extends StatelessWidget {
  const PixoraTestApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Pixora Test',
      debugShowCheckedModeBanner: false,
      theme: ThemeData.dark(useMaterial3: true),
      home: const HomePage(),
    );
  }
}

// Simple counter provider to test Riverpod works
final counterProvider = StateProvider<int>((ref) => 0);

class HomePage extends ConsumerWidget {
  const HomePage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final count = ref.watch(counterProvider);

    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        title: const Text('Pixora Test iOS'),
        backgroundColor: const Color(0xFF6A11CB),
      ),
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(32),
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [Color(0xFF6A11CB), Color(0xFF2575FC)],
                ),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.check_circle, size: 64, color: Colors.greenAccent),
                  const SizedBox(height: 16),
                  const Text(
                    'Riverpod OK!',
                    style: TextStyle(
                      fontSize: 28,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Contador: $count',
                    style: const TextStyle(fontSize: 20, color: Colors.white70),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),
            ElevatedButton.icon(
              onPressed: () => ref.read(counterProvider.notifier).state++,
              icon: const Icon(Icons.add),
              label: const Text('Incrementar'),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF6A11CB),
                padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 16),
              ),
            ),
            const SizedBox(height: 16),
            ElevatedButton.icon(
              onPressed: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const SecondPage()),
                );
              },
              icon: const Icon(Icons.navigate_next),
              label: const Text('Ir a página 2'),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF2575FC),
                padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 16),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class SecondPage extends StatelessWidget {
  const SecondPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        title: const Text('Página 2'),
        backgroundColor: const Color(0xFF2575FC),
      ),
      body: const Center(
        child: Text(
          'Navegación OK!',
          style: TextStyle(fontSize: 28, color: Colors.white),
        ),
      ),
    );
  }
}
