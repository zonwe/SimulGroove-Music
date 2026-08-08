import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../core/online_music/online_music_error.dart';
import '../../core/online_music/online_track.dart';
import 'online_search_controller.dart';
import 'online_track_tile.dart';

class OnlineSearchPage extends ConsumerStatefulWidget {
  const OnlineSearchPage({super.key});

  @override
  ConsumerState<OnlineSearchPage> createState() => _OnlineSearchPageState();
}

class _OnlineSearchPageState extends ConsumerState<OnlineSearchPage> {
  late final TextEditingController _query;
  late final OnlineSearchController _controller;
  final Set<String> _resolvingTrackIds = {};

  @override
  void initState() {
    super.initState();
    _controller = ref.read(onlineSearchControllerProvider);
    _query = TextEditingController(text: _controller.state.query);
  }

  @override
  void dispose() {
    _query.dispose();
    super.dispose();
  }

  Future<void> _play(OnlineTrack track) async {
    if (_resolvingTrackIds.contains(track.id)) return;
    setState(() => _resolvingTrackIds.add(track.id));
    try {
      await ref.read(onlineTrackPlaybackProvider).play(track);
    } catch (error) {
      if (!mounted) return;
      final message = switch (error) {
        OnlineMusicException exception => exception.message,
        UnsupportedError exception =>
          exception.message?.toString() ?? '当前平台暂不支持在线播放。',
        _ => '在线播放失败，请稍后重试。',
      };
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text(message)));
    } finally {
      if (mounted) setState(() => _resolvingTrackIds.remove(track.id));
    }
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final horizontalPadding = constraints.maxWidth < 600 ? 16.0 : 24.0;
        return Padding(
          padding: EdgeInsets.fromLTRB(
            horizontalPadding,
            20,
            horizontalPadding,
            0,
          ),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 1040),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    '在线搜索',
                    style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    '搜索已配置的音乐来源。结果不会写入本地音乐库。',
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 18),
                  AnimatedBuilder(
                    animation: _controller,
                    builder: (context, _) =>
                        ValueListenableBuilder<TextEditingValue>(
                          valueListenable: _query,
                          builder: (context, value, _) {
                            final loading =
                                _controller.state.status ==
                                OnlineSearchStatus.loading;
                            return TextField(
                              controller: _query,
                              textInputAction: TextInputAction.search,
                              decoration: InputDecoration(
                                labelText: '歌曲、专辑或艺术家',
                                hintText: '输入关键字开始搜索',
                                prefixIcon: const Icon(Icons.travel_explore),
                                suffixIcon: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    if (value.text.isNotEmpty)
                                      IconButton(
                                        tooltip: '清空搜索',
                                        onPressed: () {
                                          _query.clear();
                                          _controller.queryChanged('');
                                        },
                                        icon: const Icon(Icons.clear),
                                      ),
                                    IconButton(
                                      tooltip: '立即搜索',
                                      onPressed: loading
                                          ? null
                                          : () => _controller.searchNow(
                                              _query.text,
                                            ),
                                      icon: loading
                                          ? const SizedBox.square(
                                              dimension: 20,
                                              child: CircularProgressIndicator(
                                                strokeWidth: 2,
                                              ),
                                            )
                                          : const Icon(Icons.search),
                                    ),
                                  ],
                                ),
                              ),
                              onChanged: _controller.queryChanged,
                              onSubmitted: _controller.searchNow,
                            );
                          },
                        ),
                  ),
                  const SizedBox(height: 16),
                  Expanded(
                    child: AnimatedBuilder(
                      animation: _controller,
                      builder: (context, _) => _SearchBody(
                        state: _controller.state,
                        onRetry: _controller.retry,
                        onPlay: _play,
                        resolvingTrackIds: _resolvingTrackIds,
                        playbackSupported: ref
                            .watch(onlineTrackPlaybackProvider)
                            .supported,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

class _SearchBody extends StatelessWidget {
  const _SearchBody({
    required this.state,
    required this.onRetry,
    required this.onPlay,
    required this.resolvingTrackIds,
    required this.playbackSupported,
  });

  final OnlineSearchState state;
  final VoidCallback onRetry;
  final ValueChanged<OnlineTrack> onPlay;
  final Set<String> resolvingTrackIds;
  final bool playbackSupported;

  @override
  Widget build(BuildContext context) => switch (state.status) {
    OnlineSearchStatus.idle => const _SearchMessage(
      icon: Icons.manage_search_rounded,
      title: '输入关键字开始搜索',
      message: '需要先在账号页登录，并由服务端启用允许的音乐来源。',
    ),
    OnlineSearchStatus.loading => const _LoadingState(),
    OnlineSearchStatus.empty => _SearchMessage(
      icon: Icons.search_off_rounded,
      title: '没有找到相关结果',
      message: '可以尝试歌曲原名、艺术家名称，或减少关键字后重新搜索。',
      action: OutlinedButton.icon(
        onPressed: onRetry,
        icon: const Icon(Icons.refresh),
        label: const Text('重新搜索'),
      ),
    ),
    OnlineSearchStatus.error => _SearchMessage(
      icon: Icons.cloud_off_outlined,
      title: '在线搜索失败',
      message: state.message ?? '在线音乐服务暂时不可用。',
      liveRegion: true,
      action: FilledButton.icon(
        onPressed: onRetry,
        icon: const Icon(Icons.refresh),
        label: const Text('重试'),
      ),
    ),
    OnlineSearchStatus.data => _ResultsList(
      state: state,
      onPlay: onPlay,
      resolvingTrackIds: resolvingTrackIds,
      playbackSupported: playbackSupported,
    ),
    OnlineSearchStatus.partial => _ResultsList(
      state: state,
      partial: true,
      onPlay: onPlay,
      resolvingTrackIds: resolvingTrackIds,
      playbackSupported: playbackSupported,
    ),
  };
}

class _LoadingState extends StatelessWidget {
  const _LoadingState();

  @override
  Widget build(BuildContext context) => Semantics(
    liveRegion: true,
    label: '正在搜索在线音乐',
    child: const Column(
      children: [
        LinearProgressIndicator(),
        Expanded(
          child: Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                CircularProgressIndicator(),
                SizedBox(height: 16),
                Text('正在搜索多个音乐来源…'),
              ],
            ),
          ),
        ),
      ],
    ),
  );
}

class _ResultsList extends StatelessWidget {
  const _ResultsList({
    required this.state,
    required this.onPlay,
    required this.resolvingTrackIds,
    required this.playbackSupported,
    this.partial = false,
  });

  final OnlineSearchState state;
  final bool partial;
  final ValueChanged<OnlineTrack> onPlay;
  final Set<String> resolvingTrackIds;
  final bool playbackSupported;

  @override
  Widget build(BuildContext context) => ListView.separated(
    key: const PageStorageKey<String>('online-search-results'),
    padding: const EdgeInsets.only(bottom: 24),
    itemCount: state.items.length + (partial ? 1 : 0),
    separatorBuilder: (_, _) => const SizedBox(height: 10),
    itemBuilder: (context, index) {
      if (partial && index == 0) {
        final providers = state.warnings
            .map((warning) => warning.provider)
            .toSet()
            .join('、');
        return Semantics(
          liveRegion: true,
          child: Material(
            color: Theme.of(context).colorScheme.tertiaryContainer,
            borderRadius: BorderRadius.circular(8),
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Row(
                children: [
                  const Icon(Icons.warning_amber_rounded),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      providers.isEmpty
                          ? '部分来源暂时不可用，已显示其余搜索结果。'
                          : '$providers 暂时不可用，已显示其余搜索结果。',
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      }
      final itemIndex = partial ? index - 1 : index;
      final track = state.items[itemIndex];
      return OnlineTrackTile(
        key: ValueKey(track.id),
        track: track,
        playbackSupported: playbackSupported,
        resolving: resolvingTrackIds.contains(track.id),
        onPlay: () => onPlay(track),
      );
    },
  );
}

class _SearchMessage extends StatelessWidget {
  const _SearchMessage({
    required this.icon,
    required this.title,
    required this.message,
    this.action,
    this.liveRegion = false,
  });

  final IconData icon;
  final String title;
  final String message;
  final Widget? action;
  final bool liveRegion;

  @override
  Widget build(BuildContext context) => Semantics(
    liveRegion: liveRegion,
    child: Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(vertical: 24),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                icon,
                size: 58,
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
              const SizedBox(height: 14),
              Text(
                title,
                textAlign: TextAlign.center,
                style: Theme.of(
                  context,
                ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 7),
              Text(
                message,
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
              if (action case final action?) ...[
                const SizedBox(height: 18),
                action,
              ],
            ],
          ),
        ),
      ),
    ),
  );
}
