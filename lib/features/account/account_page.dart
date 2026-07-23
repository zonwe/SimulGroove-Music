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
  String? _error;

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
      const Text('当前使用本地模拟账号，不会发送网络请求。', textAlign: TextAlign.center),
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
          const Chip(
            avatar: Icon(Icons.science_outlined, size: 18),
            label: Text('本地模拟账号'),
          ),
          const SizedBox(height: 10),
          const Text(
            '后续接入后台时将替换 AuthRepository，密码不会保存在本地数据库。',
            textAlign: TextAlign.center,
          ),
        ],
      );

  Future<void> _signIn() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await ref
          .read(authRepositoryProvider)
          .signIn(username: _username.text, password: _password.text);
      _password.clear();
    } catch (error) {
      if (mounted) setState(() => _error = error.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }
}
