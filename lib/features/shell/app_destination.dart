import 'package:flutter/material.dart';

enum AppDestination {
  playlists('歌单', Icons.queue_music_outlined, Icons.queue_music),
  library('音乐库', Icons.library_music_outlined, Icons.library_music),
  onlineSearch('在线搜索', Icons.travel_explore_outlined, Icons.travel_explore),
  recognition('听歌识曲', Icons.graphic_eq_outlined, Icons.graphic_eq),
  account('账号', Icons.person_outline, Icons.person),
  settings('设置', Icons.settings_outlined, Icons.settings);

  const AppDestination(this.label, this.icon, this.selectedIcon);

  final String label;
  final IconData icon;
  final IconData selectedIcon;
}
