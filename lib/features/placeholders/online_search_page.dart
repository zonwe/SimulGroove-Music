import 'package:flutter/material.dart';

class OnlineSearchPage extends StatefulWidget {
  const OnlineSearchPage({super.key});

  @override
  State<OnlineSearchPage> createState() => _OnlineSearchPageState();
}

class _OnlineSearchPageState extends State<OnlineSearchPage> {
  final _query = TextEditingController();

  @override
  void dispose() {
    _query.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.all(24),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '在线搜索',
          style: Theme.of(
            context,
          ).textTheme.headlineMedium?.copyWith(fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 8),
        const Text('这里将用于聚合后续接入的音乐服务 API。'),
        const SizedBox(height: 20),
        TextField(
          controller: _query,
          decoration: InputDecoration(
            hintText: '搜索歌曲、专辑或艺术家',
            prefixIcon: const Icon(Icons.travel_explore),
            suffixIcon: IconButton(
              tooltip: '搜索',
              onPressed: () => setState(() {}),
              icon: const Icon(Icons.search),
            ),
          ),
          onSubmitted: (_) => setState(() {}),
        ),
        const Spacer(),
        Center(
          child: Column(
            children: [
              Icon(
                Icons.cloud_off_outlined,
                size: 62,
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
              const SizedBox(height: 12),
              const Text('暂未接入在线音乐服务'),
              const SizedBox(height: 5),
              const Text('搜索接口已预留，当前不会发起网络请求。'),
            ],
          ),
        ),
        const Spacer(),
      ],
    ),
  );
}
