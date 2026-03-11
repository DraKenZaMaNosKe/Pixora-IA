import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:http/http.dart' as http;
import 'package:cached_network_image/cached_network_image.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:path_provider/path_provider.dart';
import 'dart:convert';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Hive.initFlutter();
  await MobileAds.instance.initialize();
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

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  List<String> imageUrls = [];
  bool loading = true;
  String? error;
  String statusText = 'Cargando...';

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    // Test path_provider
    try {
      final dir = await getApplicationDocumentsDirectory();
      statusText = 'Docs: ${dir.path.split('/').last}';
    } catch (e) {
      statusText = 'path_provider error: $e';
    }

    // Test permission_handler
    try {
      final photoStatus = await Permission.photos.status;
      statusText += ' | Photos: $photoStatus';
    } catch (e) {
      statusText += ' | perm error: $e';
    }

    await _loadImages();
  }

  Future<void> _loadImages() async {
    try {
      final response = await http.get(
        Uri.parse('https://picsum.photos/v2/list?page=1&limit=12'),
      );
      if (response.statusCode == 200) {
        final List data = json.decode(response.body);
        setState(() {
          imageUrls = data
              .map<String>((item) => 'https://picsum.photos/id/${item['id']}/400/800')
              .toList();
          loading = false;
        });
      } else {
        setState(() {
          error = 'HTTP ${response.statusCode}';
          loading = false;
        });
      }
    } catch (e) {
      setState(() {
        error = e.toString();
        loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        title: const Text('Pixora FULL Test'),
        backgroundColor: const Color(0xFF6A11CB),
      ),
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    if (loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (error != null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.error, size: 64, color: Colors.red),
            const SizedBox(height: 16),
            Text('Error: $error', style: const TextStyle(color: Colors.white)),
          ],
        ),
      );
    }
    return Column(
      children: [
        Container(
          padding: const EdgeInsets.all(12),
          child: Column(
            children: [
              const Text(
                'ALL DEPENDENCIES OK!',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: Colors.greenAccent,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                statusText,
                style: const TextStyle(fontSize: 10, color: Colors.white38),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
        Expanded(
          child: GridView.builder(
            padding: const EdgeInsets.all(8),
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 2,
              childAspectRatio: 0.5,
              crossAxisSpacing: 8,
              mainAxisSpacing: 8,
            ),
            itemCount: imageUrls.length,
            itemBuilder: (context, index) {
              return ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: CachedNetworkImage(
                  imageUrl: imageUrls[index],
                  fit: BoxFit.cover,
                  placeholder: (_, __) => Container(
                    color: Colors.grey[900],
                    child: const Center(child: CircularProgressIndicator(strokeWidth: 2)),
                  ),
                  errorWidget: (_, __, ___) => Container(
                    color: Colors.grey[900],
                    child: const Icon(Icons.broken_image, color: Colors.white38),
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}
