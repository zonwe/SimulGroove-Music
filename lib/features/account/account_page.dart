import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../core/auth/backend_gateway.dart';

class AccountPage extends ConsumerStatefulWidget {
  const AccountPage({super.key});

  @override
  ConsumerState<AccountPage> createState() => _AccountPageState();
}

class _AccountPageState extends ConsumerState<AccountPage> {
  final _serverAddress = TextEditingController();
  final _username = TextEditingController();
  final _password = TextEditingController();
  bool _addressEdited = false;
  bool _showServerSettings = false;
  bool _busy = false;
  bool _syncing = false;
  String? _error;
  String? _syncMessage;

  @override
  void initState() {
    super.initState();
    // 把已保存的地址同步进输入框（含初始值）；用户一旦手动编辑就不再覆盖。
    ref.listenManual(backendBaseUrlProvider, (previous, next) {
      if (_addressEdited) return;
      final value = next.value;
      if (value == null || _serverAddress.text == value) return;
      _serverAddress.text = value;
    }, fireImmediately: true);
  }

  @override
  void dispose() {
    _serverAddress.dispose();
    _username.dispose();
    _password.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final account = ref.watch(accountProvider);
    final savedAddress = ref.watch(backendBaseUrlProvider).value ?? '';
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
                    ? _loginForm(context, savedAddress)
                    : _profile(context, value.displayName, value.username),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _loginForm(BuildContext context, String savedAddress) {
    // 服务器地址默认收进「高级设置」：登录页不再直接摊开后端地址，
    // 只有未配置或用户正在编辑时才展开，避免首次使用没有入口。
    final showServerField = _showServerSettings || savedAddress.isEmpty;
    return Column(
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
        if (showServerField) ...[
          TextField(
            controller: _serverAddress,
            keyboardType: TextInputType.url,
            autocorrect: false,
            enabled: !_busy,
            decoration: const InputDecoration(
              labelText: '服务器地址',
              hintText: 'https://music.example.com',
              helperText: '后端 Music.Api 的地址，保存后立即生效',
            ),
            onChanged: (_) {
              _addressEdited = true;
              if (!_showServerSettings) {
                setState(() => _showServerSettings = true);
              }
            },
          ),
          if (savedAddress.isEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text(
                '请填写服务器地址后登录',
                style: TextStyle(color: Theme.of(context).colorScheme.primary),
              ),
            ),
          const SizedBox(height: 12),
        ],
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
        if (savedAddress.isNotEmpty)
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              onPressed: _busy
                  ? null
                  : () => setState(() {
                      final open = !showServerField;
                      _showServerSettings = open;
                      if (!open) {
                        // 收起时丢弃未保存的草稿，下次展开仍是已保存的地址。
                        _addressEdited = false;
                        _serverAddress.text = savedAddress;
                      }
                    }),
              icon: Icon(
                showServerField ? Icons.expand_less : Icons.tune,
                size: 18,
              ),
              label: Text(showServerField ? '收起服务器设置' : '高级设置'),
            ),
          ),
      ],
    );
  }

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
            label: Text(_syncing ? '同步中…' : '立即同步音乐库'),
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
    final address = normalizeBackendBaseUrl(_serverAddress.text);
    final parsed = Uri.tryParse(address);
    if (address.isEmpty || parsed == null || parsed.host.isEmpty) {
      setState(() => _error = '请填写服务器地址，例如 https://music.example.com。');
      return;
    }
    if (parsed.scheme != 'http' && parsed.scheme != 'https') {
      setState(() => _error = '服务器地址需要以 http:// 或 https:// 开头。');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
      _syncMessage = null;
    });
    try {
      // 先持久化地址；网关每次请求都会读取该设置，下一次登录立即生效。
      await ref
          .read(databaseProvider)
          .setSetting(backendBaseUrlSettingKey, address);
      await ref
          .read(authRepositoryProvider)
          .signIn(username: _username.text, password: _password.text);
      final result = await ref.read(authRepositoryProvider).syncNow();
      if (mounted) {
        setState(
          () => _syncMessage =
              '已登录并同步 ${result.uploaded} 个歌单、${result.uploadedLikes} 首喜欢歌曲、'
              '${result.uploadedPresets} 个均衡器预设',
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
              '同步完成：上传 ${result.uploaded} 个歌单、${result.uploadedLikes} 首喜欢歌曲和'
              '${result.uploadedPresets} 个均衡器预设；新增 ${result.downloaded} 个歌单、'
              '${result.downloadedLikes} 首喜欢歌曲和 ${result.downloadedPresets} 个均衡器预设',
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
