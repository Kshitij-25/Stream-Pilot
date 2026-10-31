import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

/// Built-in vector icons, referenced as `mi:name` in a button's `icon`.
const materialIconSet = <String, IconData>{
  'mic': Icons.mic,
  'mic_off': Icons.mic_off,
  'headset': Icons.headset,
  'headset_off': Icons.headset_off,
  'volume_up': Icons.volume_up,
  'volume_down': Icons.volume_down,
  'volume_off': Icons.volume_off,
  'play': Icons.play_arrow,
  'pause': Icons.pause,
  'play_pause': Icons.play_circle,
  'stop': Icons.stop,
  'skip_next': Icons.skip_next,
  'skip_prev': Icons.skip_previous,
  'record': Icons.fiber_manual_record,
  'videocam': Icons.videocam,
  'videocam_off': Icons.videocam_off,
  'live': Icons.sensors,
  'camera': Icons.photo_camera,
  'screen': Icons.desktop_windows,
  'monitor_off': Icons.mobile_off,
  'laptop': Icons.laptop,
  'keyboard': Icons.keyboard,
  'mouse': Icons.mouse,
  'gamepad': Icons.sports_esports,
  'chat': Icons.chat_bubble,
  'forum': Icons.forum,
  'notifications': Icons.notifications,
  'notifications_off': Icons.notifications_off,
  'lock': Icons.lock,
  'unlock': Icons.lock_open,
  'power': Icons.power_settings_new,
  'sleep': Icons.bedtime,
  'folder': Icons.folder,
  'home': Icons.home,
  'back': Icons.arrow_back,
  'link': Icons.link,
  'web': Icons.public,
  'music': Icons.music_note,
  'queue_music': Icons.queue_music,
  'movie': Icons.movie,
  'edit': Icons.edit,
  'cut': Icons.content_cut,
  'copy': Icons.content_copy,
  'paste': Icons.content_paste,
  'undo': Icons.undo,
  'redo': Icons.redo,
  'save': Icons.save,
  'delete': Icons.delete,
  'search': Icons.search,
  'settings': Icons.settings,
  'terminal': Icons.terminal,
  'code': Icons.code,
  'bolt': Icons.bolt,
  'star': Icons.star,
  'heart': Icons.favorite,
  'thumb_up': Icons.thumb_up,
  'timer': Icons.timer,
  'clock': Icons.access_time,
  'cloud': Icons.cloud,
  'light': Icons.lightbulb,
  'sun': Icons.wb_sunny,
  'moon': Icons.dark_mode,
  'swap': Icons.swap_horiz,
  'shuffle': Icons.shuffle,
  'repeat': Icons.repeat,
  'add': Icons.add,
  'remove': Icons.remove,
  'check': Icons.check_circle,
  'close': Icons.cancel,
  'warning': Icons.warning,
  'info': Icons.info,
  'camera_switch': Icons.cameraswitch,
  'layers': Icons.layers,
  'dashboard': Icons.dashboard,
  'speed': Icons.speed,
  'memory': Icons.memory,
  'replay': Icons.replay,
  'flag': Icons.flag,
  'campaign': Icons.campaign,
  'hourglass': Icons.hourglass_bottom,
  'coffee': Icons.coffee,
  'emoji': Icons.emoji_emotions,
  'person': Icons.person,
  'group': Icons.group,
  'block': Icons.block,
  'gavel': Icons.gavel,
  'tune': Icons.tune,
  'analytics': Icons.analytics,
  'history': Icons.history,
  'smart_toy': Icons.smart_toy,
  'volume_mute': Icons.volume_mute,
  'visibility': Icons.visibility,
  'visibility_off': Icons.visibility_off,
  'photo_camera': Icons.photo_camera,
  'graphic_eq': Icons.graphic_eq,
  'tv': Icons.tv,
  'speaker': Icons.speaker,
  'fast_forward': Icons.fast_forward,
  'shield': Icons.shield,
  'bookmark': Icons.bookmark,
  'screen_share': Icons.screen_share,
  'headphones': Icons.headphones,
  'monitor': Icons.monitor,
};

final Map<String, Uint8List> _bytesCache = {};

Uint8List imageBytes(String b64) => _bytesCache.putIfAbsent(b64, () {
      if (_bytesCache.length > 80) _bytesCache.clear();
      return base64Decode(b64);
    });

/// Lets the user pick a picture, scales it to a square icon and returns it as base64 PNG.
Future<String?> pickIconImage() async {
  final file = await ImagePicker().pickImage(source: ImageSource.gallery, maxWidth: 512, maxHeight: 512);
  if (file == null) return null;
  final bytes = await file.readAsBytes();
  final codec = await ui.instantiateImageCodec(bytes, targetWidth: 160);
  final frame = await codec.getNextFrame();
  final png = await frame.image.toByteData(format: ui.ImageByteFormat.png);
  frame.image.dispose();
  if (png == null) return null;
  return base64Encode(png.buffer.asUint8List());
}

/// Renders a button face icon: custom picture > Material icon (`mi:name`) > emoji / text.
class DeckIcon extends StatelessWidget {
  final String icon;
  final String? image;
  final double size;
  final Color color;

  const DeckIcon({super.key, required this.icon, this.image, this.size = 34, this.color = Colors.white});

  @override
  Widget build(BuildContext context) {
    if (image != null && image!.isNotEmpty) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(size * 0.18),
        child: Image.memory(imageBytes(image!), width: size, height: size, fit: BoxFit.cover, gaplessPlayback: true),
      );
    }
    if (icon.startsWith('mi:')) {
      return Icon(materialIconSet[icon.substring(3)] ?? Icons.help_outline, size: size, color: color);
    }
    if (icon.isEmpty) return const SizedBox.shrink();
    return Text(icon, style: TextStyle(fontSize: size), maxLines: 1);
  }
}
