import 'dart:async';

import 'package:audio_service/audio_service.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../core/format/duration_text.dart';
import '../../core/player/lyrics_settings.dart';
import '../../core/player/now_playing_layout.dart';
import '../../core/window/desktop_window_controller.dart';
import '../shell/windows_title_bar.dart';
import 'compact_player.dart';
import 'now_playing_artwork_lyrics_pager.dart';
import 'now_playing_controls_row.dart';
import 'now_playing_split_view.dart';
import 'now_playing_track_header.dart';
import 'queue_sheet.dart';

// 拆分后保留原有导入路径的公共 API，调用方与测试无需修改。
export 'now_playing_playback_mode.dart'
    show
        playbackModeFromState,
        nextPlaybackMode,
        playbackModeLabel,
        playbackModeIcon;
export 'now_playing_split_view.dart'
    show NowPlayingSplitArtworkLyrics, shouldUseSplitNowPlayingLayout;
export 'now_playing_track_header.dart'
    show
        NowPlayingArtistLinks,
        NowPlayingTrackTitleRow,
        onlineTrackFromMediaItem,
        openNowPlayingArtist;

@visibleForTesting
bool shouldShowNowPlayingTrackInfoButton(
  TargetPlatform platform, {
  required bool isWeb,
}) =>
    !isWeb &&
    (platform == TargetPlatform.android ||
        platform == TargetPlatform.windows ||
        platform == TargetPlatform.linux);

class NowPlayingPage extends ConsumerStatefulWidget {
  const NowPlayingPage({super.key});

  @override
  ConsumerState<NowPlayingPage> createState() => _NowPlayingPageState();
}

class _NowPlayingPageState extends ConsumerState<NowPlayingPage> {
  @override
  Widget build(BuildContext context) {
    final handler = ref.watch(audioHandlerProvider);
    final configuredLayout =
        ref.watch(nowPlayingLayoutProvider).value ?? NowPlayingLayout.classic;
    final lyricsTapToSeekEnabled =
        ref.watch(lyricsTapToSeekEnabledProvider).value ??
        lyricsTapToSeekEnabledByDefault;
    final lyricsTapToSeekConfirm =
        ref.watch(lyricsTapToSeekConfirmProvider).value ??
        lyricsTapToSeekConfirmByDefault;
    // 只有启用时才把 onSeek 传进歌词面板；null 表示歌词行不可点击。
    final seekFromLyrics = lyricsTapToSeekEnabled
        ? (Duration position) => unawaited(handler.seek(position))
        : null;
    final isAndroid =
        !kIsWeb && defaultTargetPlatform == TargetPlatform.android;
    final isDesktop =
        !kIsWeb &&
        (defaultTargetPlatform == TargetPlatform.windows ||
            defaultTargetPlatform == TargetPlatform.linux);
    final showTrackInfoButton = shouldShowNowPlayingTrackInfoButton(
      defaultTargetPlatform,
      isWeb: kIsWeb,
    );
    final regularPlayer = Column(
      children: [
        const WindowsTitleBar(),
        Expanded(
          child: ValueListenableBuilder<bool>(
            valueListenable: playbackQueueDockOpen,
            builder: (context, queueOpen, _) {
              final docked =
                  isDesktop &&
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
                          final availableWidth =
                              MediaQuery.sizeOf(context).width -
                              (docked ? 336 : 0);
                          final splitLayout = shouldUseSplitNowPlayingLayout(
                            layout: configuredLayout,
                            platform: defaultTargetPlatform,
                            isWeb: kIsWeb,
                            availableWidth: availableWidth,
                          );
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
                                    child: splitLayout
                                        ? NowPlayingSplitArtworkLyrics(
                                            item: item,
                                            positionStream:
                                                handler.positionStream,
                                            initialPosition: handler
                                                .playbackState
                                                .value
                                                .position,
                                            onSeek: seekFromLyrics,
                                            confirmSeek: lyricsTapToSeekConfirm,
                                          )
                                        : NowPlayingArtworkLyricsPager(
                                            item: item,
                                            positionStream:
                                                handler.positionStream,
                                            initialPosition: handler
                                                .playbackState
                                                .value
                                                .position,
                                            onSeek: seekFromLyrics,
                                            confirmSeek: lyricsTapToSeekConfirm,
                                          ),
                                  ),
                                  const SizedBox(height: 16),
                                  NowPlayingTrackTitleRow(item: item),
                                  const SizedBox(height: 4),
                                  NowPlayingArtistLinks(
                                    artistTag: item.artist ?? '未知艺术家',
                                    album: item.album ?? '未知专辑',
                                    onArtistTap: (artist) =>
                                        openNowPlayingArtist(
                                          context,
                                          ref,
                                          item,
                                          artist,
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
                                              Text(
                                                formatPlaybackDuration(
                                                  position,
                                                ),
                                              ),
                                              Text(
                                                formatPlaybackDuration(
                                                  duration,
                                                ),
                                              ),
                                            ],
                                          ),
                                        ],
                                      );
                                    },
                                  ),
                                  NowPlayingControlsRow(
                                    handler: handler,
                                    item: item,
                                    isAndroid: isAndroid,
                                    isDesktop: isDesktop,
                                    docked: docked,
                                    showTrackInfoButton: showTrackInfoButton,
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
