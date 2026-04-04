import 'package:flutter/material.dart';
import '../../../../core/services/credit_service.dart';

class AIGeneratePage extends StatefulWidget {
  const AIGeneratePage({super.key});

  @override
  State<AIGeneratePage> createState() => _AIGeneratePageState();
}

class _AIGeneratePageState extends State<AIGeneratePage> {
  final _promptController = TextEditingController();
  String? _selectedStyle;

  final _styles = [
    'Anime', 'Cyberpunk', 'Fantasy', 'Minimalist',
    'Nature', 'Abstract', 'Pixel Art', 'Dark',
  ];

  @override
  void dispose() {
    _promptController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Coming Soon banner
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    const Color(0xFF7C4DFF).withOpacity(0.3),
                    const Color(0xFF00B4D8).withOpacity(0.3),
                  ],
                ),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(
                  color: const Color(0xFF7C4DFF).withOpacity(0.4),
                ),
              ),
              child: Column(
                children: [
                  const Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.auto_awesome, color: Color(0xFF00E5FF), size: 28),
                      SizedBox(width: 10),
                      Text(
                        'AI Generator',
                        style: TextStyle(
                          fontSize: 22,
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                    decoration: BoxDecoration(
                      color: Colors.amber.withOpacity(0.2),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: Colors.amber.withOpacity(0.5)),
                    ),
                    child: const Text(
                      'COMING SOON',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                        color: Colors.amber,
                        letterSpacing: 2,
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    'Generate wallpapers and ringtones with AI.\nSave credits now to be ready!',
                    style: TextStyle(
                      fontSize: 13,
                      color: Colors.white.withOpacity(0.6),
                      height: 1.5,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 16),
                  // Credits display
                  ListenableBuilder(
                    listenable: CreditService.instance,
                    builder: (context, _) => Container(
                      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                      decoration: BoxDecoration(
                        color: Colors.black26,
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.diamond, size: 20, color: Color(0xFF00E5FF)),
                          const SizedBox(width: 8),
                          Text(
                            '${CreditService.instance.balance} credits saved',
                            style: const TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.bold,
                              color: Colors.white,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 28),

            // Prompt section (disabled)
            const Text(
              'Describe your wallpaper',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _promptController,
              enabled: false,
              maxLines: 3,
              decoration: InputDecoration(
                hintText: 'A cyberpunk dragon flying over neon city at night...',
                hintStyle: TextStyle(color: Colors.white.withOpacity(0.2)),
                filled: true,
                fillColor: Colors.white.withOpacity(0.05),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                  borderSide: BorderSide(color: Colors.white.withOpacity(0.1)),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                  borderSide: BorderSide(color: Colors.white.withOpacity(0.1)),
                ),
                disabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                  borderSide: BorderSide(color: Colors.white.withOpacity(0.05)),
                ),
              ),
            ),
            const SizedBox(height: 20),

            // Style chips (disabled)
            const Text(
              'Style',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: _styles.map((style) {
                final selected = _selectedStyle == style;
                return ChoiceChip(
                  label: Text(style),
                  selected: selected,
                  onSelected: null, // Disabled
                  backgroundColor: Colors.white.withOpacity(0.05),
                  selectedColor: const Color(0xFF7C4DFF).withOpacity(0.3),
                  labelStyle: TextStyle(
                    color: selected ? const Color(0xFF7C4DFF) : Colors.white38,
                    fontSize: 13,
                  ),
                  side: BorderSide(
                    color: selected
                        ? const Color(0xFF7C4DFF)
                        : Colors.white.withOpacity(0.08),
                  ),
                );
              }).toList(),
            ),
            const SizedBox(height: 20),

            // Reference image upload (disabled)
            const Text(
              'Reference image (optional)',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 10),
            GestureDetector(
              onTap: null, // Disabled
              child: Container(
                width: double.infinity,
                height: 140,
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.03),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(
                    color: Colors.white.withOpacity(0.06),
                    style: BorderStyle.solid,
                  ),
                ),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.add_photo_alternate_outlined,
                        size: 40, color: Colors.white.withOpacity(0.15)),
                    const SizedBox(height: 8),
                    Text(
                      'Upload reference image',
                      style: TextStyle(
                        color: Colors.white.withOpacity(0.15),
                        fontSize: 13,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 24),

            // Generate button (disabled)
            SizedBox(
              width: double.infinity,
              height: 52,
              child: ElevatedButton.icon(
                onPressed: null, // Disabled
                icon: const Icon(Icons.auto_awesome, size: 20),
                label: const Text(
                  'Generate Wallpaper — 30 credits',
                  style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF7C4DFF),
                  foregroundColor: Colors.white,
                  disabledBackgroundColor: const Color(0xFF7C4DFF).withOpacity(0.2),
                  disabledForegroundColor: Colors.white38,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 10),
            Center(
              child: Text(
                'Cost: 30 credits per wallpaper · 50 credits per ringtone',
                style: TextStyle(fontSize: 11, color: Colors.white.withOpacity(0.25)),
              ),
            ),
            const SizedBox(height: 40),
          ],
        ),
      ),
    );
  }
}
