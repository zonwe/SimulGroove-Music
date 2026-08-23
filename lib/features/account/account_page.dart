import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';

class AccountPage extends ConsumerStatefulWidget {
  const AccountPage({super.key});

  @override
  ConsumerState<AccountPage> createState() => _AccountPageState();
}

class _AccountPageState extends ConsumerState<AccountPage> {
  final _username = TextEditingController();
  final _password = TextEditingController();
  bool _busy = false;
  bool _syncing = false;
  String? _error;
  String? _syncMessage;

  @override
  void dispose() {
    _username.dispose();
    _password.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final account = ref.watch(accountProvider);
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: Card(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: account.when(
                loading: () => const Center(child: CircularProgressIndicator()),
                error: (error, _) => Text('账号读取失败：$error'),
                data: (value) => value == null
                    ? _loginForm(context)
                    : _profile(context, value.displayName, value.username),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _loginForm(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      const Icon(Icons.account_circle_outlined, size: 58),
      const SizedBox(height: 14),
      Text(
        '登录',
        textAlign: TextAlign.center,
        style: Theme.of(context).textTheme.headlineSmall,
      ),
      const SizedBox(height: 6),
      const Text(
        '连接 SimulGroove Music API。首次使用的账号会由开发后端自动创建。',
        textAlign: TextAlign.center,
      ),
      const SizedBox(height: 22),
      TextField(
        controller: _username,
        decoration: const InputDecoration(labelText: '账号或邮箱'),
      ),
      const SizedBox(height: 12),
      TextField(
        controller: _password,
        obscureText: true,
        decoration: const InputDecoration(labelText: '密码'),
        onSubmitted: (_) => _signIn(),
      ),
      if (_error != null)
        Padding(
          padding: const EdgeInsets.only(top: 10),
          child: Text(
            _error!,
            style: TextStyle(color: Theme.of(context).colorScheme.error),
          ),
        ),
      const SizedBox(height: 18),
      FilledButton(
        onPressed: _busy ? null : _signIn,
        child: Text(_busy ? '登录中…' : '登录'),
      ),
    ],
  );

  Widget _profile(BuildContext context, String displayName, String username) =>
      Column(
        children: [
          const CircleAvatar(radius: 38, child: Icon(Icons.person, size: 38)),
          const SizedBox(height: 14),
          Text(displayName, style: Theme.of(context).textTheme.headlineSmall),
          const SizedBox(height: 4),
          Text(username),
          const SizedBox(height: 12),
          const SizedBox(height: 16),
          FilledButton.icon(
            onPressed: _syncing ? null : _sync,
            icon: _syncing
                ? const SizedBox.square(
                    dimension: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.sync),
            label: Text(_syncing ? '同步中…' : '立即同步歌单'),
          ),
          const SizedBox(height: 8),
          OutlinedButton.icon(
            onPressed: _busy || _syncing ? null : _signOut,
            icon: const Icon(Icons.logout),
            label: const Text('退出登录'),
          ),
          if (_syncMessage != null) ...[
            const SizedBox(height: 10),
            Text(
              _syncMessage!,
              textAlign: TextAlign.center,
              style: TextStyle(color: Theme.of(context).colorScheme.primary),
            ),
          ],
          if (_error != null) ...[
            const SizedBox(height: 8),
            Text(
              _error!,
              textAlign: TextAlign.center,
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          ],
        ],
      );

  Future<void> _signIn() async {
    setState(() {
      _busy = true;
      _error = null;
      _syncMessage = null;
    });
    try {
      await ref
          .read(authRepositoryProvider)
          .signIn(username: _username.text, password: _password.text);
      final result = await ref.read(authRepositoryProvider).syncNow();
      if (mounted) {
        setState(
          () => _syncMessage =
              '已登录并同步 ${result.uploaded} 个歌单、${result.uploadedLikes} 首喜欢歌曲',
        );
      }
      _password.clear();
    } catch (error) {
      if (mounted) setState(() => _error = error.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _sync() async {
    setState(() {
      _syncing = true;
      _syncMessage = null;
      _error = null;
    });
    try {
      final result = await ref.read(authRepositoryProvider).syncNow();
      if (mounted) {
        setState(
          () => _syncMessage =
              '同步完成：上传 ${result.uploaded} 个歌单和 ${result.uploadedLikes} 首喜欢歌曲；'
              '新增 ${result.downloaded} 个歌单，匹配 ${result.downloadedLikes} 首喜欢歌曲',
        );
      }
    } catch (error) {
      if (mounted) setState(() => _error = error.toString());
    } finally {
      if (mounted) setState(() => _syncing = false);
    }
  }

  Future<void> _signOut() async {
    await ref.read(authRepositoryProvider).signOut();
    if (mounted) setState(() => _syncMessage = null);
  }
}
