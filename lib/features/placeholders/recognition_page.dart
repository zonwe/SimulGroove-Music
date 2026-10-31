import 'package:flutter/material.dart';

class RecognitionPage extends StatelessWidget {
  const RecognitionPage({super.key});

  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.all(24),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 480),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 104,
              height: 104,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: Theme.of(
                  context,
                ).colorScheme.primary.withValues(alpha: 0.18),
              ),
              child: const Icon(Icons.graphic_eq_rounded, size: 54),
            ),
            const SizedBox(height: 22),
            Text('听歌识曲', style: Theme.of(context).textTheme.headlineMedium),
            const SizedBox(height: 10),
            const Text(
              '入口已经预留，识别引擎将在后续版本接入；当前版本不申请麦克风权限。',
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 20),
            FilledButton.icon(
              onPressed: null,
              icon: Icon(Icons.mic_none),
              label: Text('开始识别（尚未实现）'),
            ),
          ],
        ),
      ),
    ),
  );
}
