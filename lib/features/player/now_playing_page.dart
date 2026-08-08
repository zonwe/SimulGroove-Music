import 'package:audio_service/audio_service.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../core/lyrics/lrc_parser.dart';
import '../../core/player/music_audio_handler.dart';
import '../../core/window/desktop_window_controller.dart';
import '../library/artwork_view.dart';
import '../shell/windows_title_bar.dart';
import 'compact_player.dart';
import 'queue_sheet.dart';
import 'track_info_sheet.dart';
import 'volume_control.dart';

class NowPlayingPage extends ConsumerStatefulWidget {
  const NowPlayingPage({super.key});

  @override
  ConsumerState<NowPlayingPage> createState() => _NowPlayingPageState();
}

class _NowPlayingPageState extends ConsumerState<NowPlayingPage> {
  bool _showLyrics = false;
  int _lyricsViewGeneration = 0;

  @override
  Widget build(BuildContext context) {
    final handler = ref.watch(audioHandlerProvider);
    final isAndroid =
        !kIsWeb && defaultTargetPlatform == TargetPlatform.android;
    final regularPlayer = Column(
      children: [
        const WindowsTitleBar(),
        Expanded(
          child: ValueListenableBuilder<bool>(
            valueListenable: playbackQueueDockOpen,
            builder: (context, queueOpen, _) {
              final docked =
                  WindowsTitleBar.isVisible &&
                  MediaQuery.sizeOf(context).width >= 900 &&
                  queueOpen;
              return Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Expanded(
                    child: Scaffold(
                      appBar: AppBar(
                        title: const Text('正在播放'),
                        actions: [
                          IconButton(
                            tooltip: '播放列表',
                            onPressed: () =>
                                showPlaybackQueue(context, handler),
                            icon: const Icon(Icons.queue_music_rounded),
                          ),
                        ],
                      ),
                      body: StreamBuilder<MediaItem?>(
                        stream: handler.mediaItem,
                        builder: (context, itemSnapshot) {
                          final item = itemSnapshot.data;
                          if (item == null) {
                            return const Center(child: Text('当前没有播放歌曲'));
                          }
                          return SafeArea(
                            child: Padding(
                              padding: const EdgeInsets.fromLTRB(
                                24,
                                10,
                                24,
                                24,
                              ),
                              child: Column(
                                children: [
                                  Expanded(
                                    child: GestureDetector(
                                      behavior: HitTestBehavior.opaque,
                                      onTap: () => setState(() {
                                        _showLyrics = !_showLyrics;
                                        if (_showLyrics) {
                                          _lyricsViewGeneration++;
                                        }
                                      }),
                                      child: AnimatedSwitcher(
                                        duration: const Duration(
                                          milliseconds: 220,
                                        ),
                                        child: _showLyrics
                                            ? _LyricsPanel(
                                                key: ValueKey((
                                                  item.id,
                                                  _lyricsViewGeneration,
                                                )),
                                                lyrics:
                                                    item.extras?['lyrics']
                                                        as String?,
                                                positionStream:
                                                    handler.positionStream,
                                                initialPosition: handler
                                                    .playbackState
                                                    .value
                                                    .position,
                                              )
                                            : LayoutBuilder(
                                                builder: (context, constraints) {
                                                  final size = constraints
                                                      .biggest
                                                      .shortestSide
                                                      .clamp(180.0, 320.0);
                                                  return Center(
                                                    child: ArtworkView(
                                                      key: const ValueKey(
                                                        'cover',
                                                      ),
                                                      bytes:
                                                          item.extras?['artwork']
                                                              as Uint8List?,
                                                      size: size,
                                                      borderRadius: 12,
                                                    ),
                                                  );
                                                },
                                              ),
                                      ),
                                    ),
                                  ),
                                  const SizedBox(height: 16),
                                  Row(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      Flexible(
                                        child: Text(
                                          item.title,
                                          textAlign: TextAlign.center,
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          style: Theme.of(context)
                                              .textTheme
                                              .headlineSmall
                                              ?.copyWith(
                                                fontWeight: FontWeight.w700,
                                              ),
                                        ),
                                      ),
                                      const SizedBox(width: 4),
                                      StreamBuilder<Set<String>>(
                                        stream: ref
                                            .read(databaseProvider)
                                            .watchLikedTrackIds(),
                                        builder: (context, likedSnapshot) {
                                          final liked =
                                              likedSnapshot.data?.contains(
                                                item.id,
                                              ) ??
                                              false;
                                          return IconButton(
                                            tooltip: liked ? '取消喜欢' : '喜欢',
                                            icon: Icon(
                                              liked
                                                  ? Icons.favorite
                                                  : Icons.favorite_border,
                                            ),
                                            onPressed: () => ref
                                                .read(databaseProvider)
                                                .setTrackLiked(item.id, !liked),
                                          );
                                        },
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    '${item.artist ?? '未知艺术家'} · ${item.album ?? '未知专辑'}',
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: Theme.of(context)
                                        .textTheme
                                        .bodyMedium
                                        ?.copyWith(
                                          color: Theme.of(
                                            context,
                                          ).colorScheme.onSurfaceVariant,
                                        ),
                                  ),
                                  const SizedBox(height: 18),
                                  StreamBuilder<Duration>(
                                    stream: handler.positionStream,
                                    builder: (context, positionSnapshot) {
                                      final position =
                                          positionSnapshot.data ??
                                          Duration.zero;
                                      final duration =
                                          item.duration ?? Duration.zero;
                                      return Column(
                                        children: [
                                          Slider(
                                            value: position.inMilliseconds
                                                .clamp(
                                                  0,
                                                  duration.inMilliseconds == 0
                                                      ? 1
                                                      : duration.inMilliseconds,
                                                )
                                                .toDouble(),
                                            max: duration.inMilliseconds <= 0
                                                ? 1
                                                : duration.inMilliseconds
                                                      .toDouble(),
                                            onChanged: (value) => handler.seek(
                                              Duration(
                                                milliseconds: value.round(),
                                              ),
                                            ),
                                          ),
                                          Row(
                                            mainAxisAlignment:
                                                MainAxisAlignment.spaceBetween,
                                            children: [
                                              Text(_format(position)),
                                              Text(_format(duration)),
                                            ],
                                          ),
                                        ],
                                      );
                                    },
                                  ),
                                  StreamBuilder<PlaybackState>(
                                    stream: handler.playbackState,
                                    initialData: handler.playbackState.value,
                                    builder: (context, snapshot) {
                                      final state =
                                          snapshot.data ??
                                          handler.playbackState.value;
                                      final playing = state.playing;
                                      final playbackMode =
                                          _playbackModeFromState(state);
                                      final compactControls =
                                          isAndroid ||
                                          MediaQuery.sizeOf(context).width <
                                              700;
                                      final modeButton = IconButton(
                                        tooltip: _playbackModeLabel(
                                          playbackMode,
                                        ),
                                        onPressed: () =>
                                            handler.setPlaybackMode(
                                              _nextPlaybackMode(playbackMode),
                                            ),
                                        icon: Icon(
                                          _playbackModeIcon(playbackMode),
                                          color: Theme.of(
                                            context,
                                          ).colorScheme.primary,
                                        ),
                                      );
                                      final infoButton = IconButton(
                                        tooltip: '歌曲信息',
                                        onPressed: () =>
                                            showTrackInfo(context, item),
                                        icon: const Icon(
                                          Icons.info_outline_rounded,
                                        ),
                                      );
                                      final trailingControls =
                                          WindowsTitleBar.isVisible
                                          ? VolumeControl(
                                              handler: handler,
                                              showSlider: !compactControls,
                                            )
                                          : const SizedBox.shrink();
                                      final leftControls = Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [modeButton],
                                      );
                                      final primaryControls = Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          IconButton.filledTonal(
                                            iconSize: 30,
                                            tooltip: '上一首',
                                            onPressed: handler.skipToPrevious,
                                            icon: const Icon(
                                              Icons.skip_previous_rounded,
                                            ),
                                          ),
                                          SizedBox(
                                            width: compactControls ? 8 : 22,
                                          ),
                                          IconButton.filled(
                                            iconSize: 38,
                                            tooltip: playing ? '暂停' : '播放',
                                            onPressed: playing
                                                ? handler.pause
                                                : handler.play,
                                            icon: Icon(
                                              playing
                                                  ? Icons.pause_rounded
                                                  : Icons.play_arrow_rounded,
                                            ),
                                          ),
                                          SizedBox(
                                            width: compactControls ? 8 : 22,
                                          ),
                                          IconButton.filledTonal(
                                            iconSize: 30,
                                            tooltip: '下一首',
                                            onPressed: handler.skipToNext,
                                            icon: const Icon(
                                              Icons.skip_next_rounded,
                                            ),
                                          ),
                                        ],
                                      );
                                      if (isAndroid) {
                                        return Row(
                                          children: [
                                            Expanded(
                                              child: Align(
                                                alignment: Alignment.centerLeft,
                                                child: modeButton,
                                              ),
                                            ),
                                            primaryControls,
                                            Expanded(
                                              child: Align(
                                                alignment:
                                                    Alignment.centerRight,
                                                child: infoButton,
                                              ),
                                            ),
                                          ],
                                        );
                                      }
                                      return Row(
                                        children: [
                                          Expanded(
                                            child: Align(
                                              alignment: Alignment.centerLeft,
                                              child: leftControls,
                                            ),
                                          ),
                                          SizedBox(
                                            width: compactControls ? 8 : 20,
                                          ),
                                          primaryControls,
                                          Expanded(
                                            child: Align(
                                              alignment: Alignment.centerRight,
                                              child: trailingControls,
                                            ),
                                          ),
                                        ],
                                      );
                                    },
                                  ),
                                ],
                              ),
                            ),
                          );
                        },
                      ),
                    ),
                  ),
                  if (docked)
                    SizedBox(
                      width: 336,
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          color: Theme.of(
                            context,
                          ).colorScheme.surfaceContainerLow,
                          border: Border(
                            left: BorderSide(
                              color: Theme.of(
                                context,
                              ).colorScheme.outlineVariant,
                            ),
                          ),
                        ),
                        child: PlaybackQueuePanel(
                          handler: handler,
                          fillHeight: true,
                          onClose: () => playbackQueueDockOpen.value = false,
                        ),
                      ),
                    ),
                ],
              );
            },
          ),
        ),
      ],
    );
    return ValueListenableBuilder<bool>(
      valueListenable: DesktopWindowController.compactMode,
      child: regularPlayer,
      builder: (context, compact, regularPlayer) {
        return compact ? const CompactPlayerWindow() : regularPlayer!;
      },
    );
  }
}

PlaybackMode _playbackModeFromState(PlaybackState state) {
  if (state.shuffleMode != AudioServiceShuffleMode.none) {
    return PlaybackMode.listShuffle;
  }
  if (state.repeatMode == AudioServiceRepeatMode.one) {
    return PlaybackMode.singleLoop;
  }
  return PlaybackMode.listLoop;
}

PlaybackMode _nextPlaybackMode(PlaybackMode mode) => switch (mode) {
  PlaybackMode.listLoop => PlaybackMode.singleLoop,
  PlaybackMode.singleLoop => PlaybackMode.listShuffle,
  PlaybackMode.listShuffle => PlaybackMode.listLoop,
};

String _playbackModeLabel(PlaybackMode mode) => switch (mode) {
  PlaybackMode.listLoop => '列表循环，点击切换单曲循环',
  PlaybackMode.singleLoop => '单曲循环，点击切换列表随机',
  PlaybackMode.listShuffle => '列表随机，点击切换列表循环',
};

IconData _playbackModeIcon(PlaybackMode mode) => switch (mode) {
  PlaybackMode.listLoop => Icons.repeat_rounded,
  PlaybackMode.singleLoop => Icons.repeat_one_rounded,
  PlaybackMode.listShuffle => Icons.shuffle_rounded,
};

// Kept for compatibility with older desktop labels.
// ignore: unused_element
String _repeatLabel(AudioServiceRepeatMode mode) => switch (mode) {
  AudioServiceRepeatMode.none => '列表循环已关闭',
  AudioServiceRepeatMode.all => '列表循环，点击切换单曲循环',
  AudioServiceRepeatMode.one => '单曲循环，点击关闭循环',
  AudioServiceRepeatMode.group => '分组循环，点击关闭循环',
};

class _LyricsPanel extends StatefulWidget {
  const _LyricsPanel({
    super.key,
    required this.lyrics,
    required this.positionStream,
    required this.initialPosition,
  });

  final String? lyrics;
  final Stream<Duration> positionStream;
  final Duration initialPosition;

  @override
  State<_LyricsPanel> createState() => _LyricsPanelState();
}

class _LyricsPanelState extends State<_LyricsPanel> {
  final List<GlobalKey> _lineKeys = <GlobalKey>[];
  final ScrollController _scrollController = ScrollController(
    keepScrollOffset: false,
  );
  int? _lastIndex;

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  @override
  void didUpdateWidget(covariant _LyricsPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.lyrics != widget.lyrics) {
      _lineKeys.clear();
      _lastIndex = null;
    }
  }

  @override
  Widget build(BuildContext context) {
    final lines = parseLrc(widget.lyrics);
    if (lines.isEmpty) {
      return const Center(key: ValueKey('lyrics-empty'), child: Text('暂无同步歌词'));
    }
    if (_lineKeys.length != lines.length) {
      _lineKeys
        ..clear()
        ..addAll(List<GlobalKey>.generate(lines.length, (_) => GlobalKey()));
    }
    return StreamBuilder<Duration>(
      key: const ValueKey('lyrics'),
      stream: widget.positionStream,
      initialData: widget.initialPosition,
      builder: (context, snapshot) {
        final current = lyricAt(lines, snapshot.data ?? Duration.zero);
        final currentIndex = current == null ? -1 : lines.indexOf(current);
        if (currentIndex >= 0 && currentIndex != _lastIndex) {
          _lastIndex = currentIndex;
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (!mounted || currentIndex >= _lineKeys.length) return;
            final lineContext = _lineKeys[currentIndex].currentContext;
            if (lineContext != null) {
              Scrollable.ensureVisible(
                lineContext,
                duration: const Duration(milliseconds: 260),
                curve: Curves.easeOutCubic,
                alignment: 0.5,
              );
            }
          });
        }
        // Build all lines so a distant current line has a context on the first
        // frame and can be centered immediately when the cover is switched.
        return ListView(
          controller: _scrollController,
          padding: const EdgeInsets.symmetric(vertical: 32),
          children: List<Widget>.generate(lines.length, (index) {
            final selected = index == currentIndex;
            return AnimatedDefaultTextStyle(
              key: _lineKeys[index],
              duration: const Duration(milliseconds: 180),
              style:
                  (selected
                          ? Theme.of(context).textTheme.titleLarge
                          : Theme.of(context).textTheme.bodyLarge)!
                      .copyWith(
                        color: selected
                            ? Theme.of(context).colorScheme.primary
                            : Theme.of(context).colorScheme.onSurfaceVariant,
                        fontWeight: selected
                            ? FontWeight.w500
                            : FontWeight.w400,
                        height: 1.8,
                      ),
              child: Text(lines[index].text, textAlign: TextAlign.center),
            );
          }),
        );
      },
    );
  }
}

String _format(Duration duration) {
  final minutes = duration.inMinutes;
  final seconds = duration.inSeconds.remainder(60).toString().padLeft(2, '0');
  return '$minutes:$seconds';
}
