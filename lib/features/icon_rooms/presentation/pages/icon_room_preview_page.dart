import 'package:flutter/material.dart';

class IconRoomPreviewPage extends StatefulWidget {
  final String assetName;
  final String title;

  const IconRoomPreviewPage({
    super.key,
    required this.assetName,
    required this.title,
  });

  @override
  State<IconRoomPreviewPage> createState() => _IconRoomPreviewPageState();
}

class _IconRoomPreviewPageState extends State<IconRoomPreviewPage> {
  late ScrollController _scrollController;

  @override
  void initState() {
    super.initState();
    _scrollController = ScrollController();
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final screenHeight = MediaQuery.of(context).size.height;

    return Scaffold(
      backgroundColor: Colors.black,
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        title: Text(widget.title),
        actions: [
          IconButton(
            icon: const Icon(Icons.wallpaper),
            tooltip: 'Set as wallpaper',
            onPressed: () {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('Save the image and set it as your wallpaper from your gallery'),
                  behavior: SnackBarBehavior.floating,
                ),
              );
            },
          ),
        ],
      ),
      body: Center(
        child: SizedBox(
          height: screenHeight * 0.75,
          child: SingleChildScrollView(
            controller: _scrollController,
            scrollDirection: Axis.horizontal,
            physics: const BouncingScrollPhysics(),
            child: Image.asset(
              'assets/icon_rooms/${widget.assetName}.png',
              fit: BoxFit.fitHeight,
            ),
          ),
        ),
      ),
      bottomNavigationBar: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              Colors.transparent,
              Colors.black.withOpacity(0.9),
            ],
          ),
        ),
        child: SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                'Scroll horizontally to explore the room',
                style: TextStyle(color: Colors.white38, fontSize: 12),
              ),
              const SizedBox(height: 4),
              const Text(
                'Place your app icons on the themed spots!',
                style: TextStyle(color: Colors.white54, fontSize: 13),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
