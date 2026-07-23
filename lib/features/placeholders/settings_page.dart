import 'package:flutter/material.dart';

class SettingsPage extends StatelessWidget {
  const SettingsPage({super.key});

  @override
  Widget build(BuildContext context) => ListView(
    padding: const EdgeInsets.all(24),
    children: [
      Text(
        '设置',
        style: Theme.of(
          context,
        ).textTheme.headlineMedium?.copyWith(fontWeight: FontWeight.w700),
      ),
      const SizedBox(height: 18),
      const Card(
        child: Column(
          children: [
            ListTile(
              leading: Icon(Icons.audio_file_outlined),
              title: Text('本地格式'),
              subtitle: Text('MP3、FLAC、M4A/AAC、WAV、OGG、Opus；Windows 尝试支持 WMA'),
            ),
            Divider(height: 1),
            ListTile(
              leading: Icon(Icons.sync_outlined),
              title: Text('后台同步'),
              subtitle: Text('尚未连接服务器'),
              trailing: Chip(label: Text('预留')),
            ),
          ],
        ),
      ),
    ],
  );
}
