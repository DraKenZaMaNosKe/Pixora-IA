import 'package:flutter/material.dart';
import 'icon_room_preview_page.dart';

class IconRoomsPage extends StatelessWidget {
  const IconRoomsPage({super.key});

  static const _rooms = [
    _RoomInfo('icon_room_01', 'Mystic Portal'),
    _RoomInfo('icon_room_02', 'Digital Dawn'),
    _RoomInfo('icon_room_03', 'Candy Kingdom'),
    _RoomInfo('icon_room_04', 'Neon District'),
    _RoomInfo('icon_room_05', 'Crystal Cave'),
    _RoomInfo('icon_room_06', 'Jungle Ruins'),
    _RoomInfo('icon_room_07', 'Luxury Penthouse'),
    _RoomInfo('icon_room_08', 'Space Station'),
    _RoomInfo('icon_room_09', 'Steampunk Lab'),
    _RoomInfo('icon_room_10', 'Zen Garden'),
    _RoomInfo('icon_room_11', 'Cyber Alley'),
    _RoomInfo('icon_room_12', 'Enchanted Forest'),
    _RoomInfo('icon_room_13', 'Haunted Mansion'),
    _RoomInfo('icon_room_14', 'Wild West'),
    _RoomInfo('icon_room_15', 'Retro Arcade'),
    _RoomInfo('icon_room_16', 'Frozen Palace'),
    _RoomInfo('icon_room_17', 'Egyptian Temple'),
    _RoomInfo('icon_room_18', 'Atlantis Lab'),
    _RoomInfo('icon_room_19', 'Tron Grid'),
    _RoomInfo('icon_room_20', 'Synthwave'),
    _RoomInfo('icon_room_21', 'Voxel World'),
    _RoomInfo('icon_room_22', 'Retro Office'),
    _RoomInfo('icon_room_23', 'Neon Gallery'),
    _RoomInfo('icon_room_24', 'Beach Resort'),
    _RoomInfo('icon_room_25', 'Gothic Castle'),
    _RoomInfo('icon_room_26', 'Penthouse Night'),
  ];

  @override
  Widget build(BuildContext context) {
    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: _rooms.length,
      itemBuilder: (context, index) {
        final room = _rooms[index];
        return _RoomCard(room: room, index: index);
      },
    );
  }
}

class _RoomInfo {
  final String assetName;
  final String title;
  const _RoomInfo(this.assetName, this.title);
}

class _RoomCard extends StatelessWidget {
  final _RoomInfo room;
  final int index;
  const _RoomCard({required this.room, required this.index});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => IconRoomPreviewPage(
            assetName: room.assetName,
            title: room.title,
          ),
        ),
      ),
      child: Container(
        margin: const EdgeInsets.only(bottom: 16),
        height: 120,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(
              color: _glowColorForIndex(index).withOpacity(0.3),
              blurRadius: 16,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(16),
          child: Stack(
            fit: StackFit.expand,
            children: [
              Image.asset(
                'assets/icon_rooms/${room.assetName}.png',
                fit: BoxFit.cover,
              ),
              // Gradient overlay
              Container(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.centerLeft,
                    end: Alignment.centerRight,
                    colors: [
                      Colors.black.withOpacity(0.7),
                      Colors.transparent,
                      Colors.black.withOpacity(0.5),
                    ],
                  ),
                ),
              ),
              // Title and badge
              Positioned(
                bottom: 12,
                left: 16,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          colors: [
                            _glowColorForIndex(index),
                            _glowColorForIndex(index).withOpacity(0.6),
                          ],
                        ),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: const Text(
                        'ICON ROOM',
                        style: TextStyle(
                          fontSize: 9,
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                          letterSpacing: 1.2,
                        ),
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      room.title,
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                      ),
                    ),
                  ],
                ),
              ),
              // Arrow icon
              Positioned(
                right: 16,
                bottom: 12,
                child: Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: _glowColorForIndex(index).withOpacity(0.3),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: _glowColorForIndex(index).withOpacity(0.5),
                    ),
                  ),
                  child: const Icon(
                    Icons.panorama_horizontal,
                    color: Colors.white,
                    size: 20,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Color _glowColorForIndex(int i) {
    const colors = [
      Color(0xFF7C4DFF),
      Color(0xFF00E5FF),
      Color(0xFFFF6090),
      Color(0xFF69F0AE),
      Color(0xFFFFD740),
      Color(0xFFFF6E40),
    ];
    return colors[i % colors.length];
  }
}
