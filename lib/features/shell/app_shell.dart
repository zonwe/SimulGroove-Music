import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../core/database/app_database.dart';
import '../../core/window/desktop_window_controller.dart';
import '../account/account_page.dart';
import '../library/library_page.dart';
import '../library/favorites_page.dart';
import '../placeholders/recognition_page.dart';
import '../placeholders/settings_page.dart';
import '../online_search/online_search_page.dart';
import '../player/compact_player.dart';
import '../player/mini_player_bar.dart';
import '../player/queue_sheet.dart';
import '../playlists/playlist_detail_page.dart';
import '../playlists/playlists_page.dart';
import 'app_destination.dart';
import 'windows_title_bar.dart';

class AppShell extends StatefulWidget {
  const AppShell({super.key});

  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> {
  AppDestination _destination = AppDestination.playlists;
  Playlist? _selectedPlaylist;

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop:
          _destination == AppDestination.playlists && _selectedPlaylist == null,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _navigateBack();
      },
      child: ValueListenableBuilder<bool>(
        valueListenable: DesktopWindowController.compactMode,
        builder: (context, compact, _) {
          if (compact) {
            return const CompactPlayerWindow();
          }
          return LayoutBuilder(
            builder: (context, constraints) {
              final wide = constraints.maxWidth >= 900;
              return Scaffold(
                appBar:
                    !wide &&
                        !WindowsTitleBar.isVisible &&
                        _selectedPlaylist == null
                    ? AppBar(
                        title: Text(_destination.label),
                        leading: _destination == AppDestination.playlists
                            ? null
                            : BackButton(onPressed: _goToPlaylists),
                      )
                    : null,
                drawer: wide
                    ? null
                    : Drawer(
                        child: SafeArea(
                          child: _DrawerNavigation(onSelect: _select),
                        ),
                      ),
                body: Column(
                  children: [
                    const WindowsTitleBar(),
                    Expanded(
                      child: Row(
                        children: [
                          if (wide)
                            _DesktopNavigation(
                              selected: _destination,
                              onSelect: _select,
                            ),
                          Expanded(
                            child: ValueListenableBuilder<bool>(
                              valueListenable: playbackQueueDockOpen,
                              builder: (context, queueOpen, _) {
                                final docked = wide && queueOpen;
                                return Row(
                                  crossAxisAlignment:
                                      CrossAxisAlignment.stretch,
                                  children: [
                                    Expanded(child: _pageFor(_destination)),
                                    if (docked)
                                      const SizedBox(
                                        width: 336,
                                        child: _QueueDockPanel(),
                                      ),
                                  ],
                                );
                              },
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                bottomNavigationBar: MiniPlayerBar(onReturn: _goToPlaylists),
              );
            },
          );
        },
      ),
    );
  }

  void _goToPlaylists() {
    setState(() {
      _destination = AppDestination.playlists;
      _selectedPlaylist = null;
    });
  }

  void _navigateBack() {
    if (_selectedPlaylist != null) {
      setState(() => _selectedPlaylist = null);
    } else {
      _goToPlaylists();
    }
  }

  void _openPlaylist(Playlist playlist) {
    setState(() {
      _destination = AppDestination.playlists;
      _selectedPlaylist = playlist;
    });
  }

  void _select(AppDestination value) {
    setState(() {
      _destination = value;
      _selectedPlaylist = null;
    });
    if (Scaffold.maybeOf(context)?.isDrawerOpen ?? false) {
      Navigator.of(context).pop();
    }
  }

  Widget _pageFor(AppDestination destination) => switch (destination) {
    AppDestination.library => const LibraryPage(),
    AppDestination.favorites => const FavoritesPage(),
    AppDestination.playlists =>
      _selectedPlaylist == null
          ? PlaylistsPage(onOpenPlaylist: _openPlaylist)
          : PlaylistDetailPage(
              playlist: _selectedPlaylist!,
              onBack: _navigateBack,
            ),
    AppDestination.onlineSearch => const OnlineSearchPage(),
    AppDestination.recognition => const RecognitionPage(),
    AppDestination.account => const AccountPage(),
    AppDestination.settings => const SettingsPage(),
  };
}

class _DesktopNavigation extends StatelessWidget {
  const _DesktopNavigation({required this.selected, required this.onSelect});

  final AppDestination selected;
  final ValueChanged<AppDestination> onSelect;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 224,
      child: Material(
        color: Theme.of(context).colorScheme.surfaceContainerLow,
        shape: Border(
          right: BorderSide(
            color: Theme.of(context).colorScheme.outlineVariant,
          ),
        ),
        child: SafeArea(
          top: !WindowsTitleBar.isVisible,
          child: Column(
            children: [
              if (!WindowsTitleBar.isVisible)
                const Padding(
                  padding: EdgeInsets.fromLTRB(20, 20, 20, 14),
                  child: Row(
                    children: [
                      Icon(Icons.music_note_rounded),
                      SizedBox(width: 10),
                      Text(
                        'Flutter Music',
                        style: TextStyle(fontWeight: FontWeight.w700),
                      ),
                    ],
                  ),
                ),
              const SizedBox(height: 10),
              for (final destination in AppDestination.values)
                Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 2,
                  ),
                  child: ListTile(
                    minTileHeight: 48,
                    selected: selected == destination,
                    selectedTileColor: Theme.of(
                      context,
                    ).colorScheme.secondaryContainer,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                    leading: Icon(
                      selected == destination
                          ? destination.selectedIcon
                          : destination.icon,
                    ),
                    title: Text(destination.label),
                    onTap: () => onSelect(destination),
                  ),
                ),
              const Spacer(),
              // if (!kIsWeb && defaultTargetPlatform == TargetPlatform.windows)
              //   Padding(
              //     padding: const EdgeInsets.all(16),
              //     child: Builder(
              //       builder: (context) => Text(
              //         'Windows 本地模式',
              //         style: TextStyle(
              //           color: Theme.of(context).colorScheme.onSurfaceVariant,
              //           fontSize: 12,
              //         ),
              //       ),
              //     ),
              //   ),
            ],
          ),
        ),
      ),
    );
  }
}

class _DrawerNavigation extends StatelessWidget {
  const _DrawerNavigation({required this.onSelect});

  final ValueChanged<AppDestination> onSelect;

  @override
  Widget build(BuildContext context) => ListView(
    padding: const EdgeInsets.all(12),
    children: [
      const ListTile(
        leading: Icon(Icons.music_note_rounded),
        title: Text(
          'Flutter Music',
          style: TextStyle(fontWeight: FontWeight.w700),
        ),
      ),
      const Divider(),
      for (final destination in AppDestination.values)
        ListTile(
          minTileHeight: 48,
          leading: Icon(destination.icon),
          title: Text(destination.label),
          onTap: () {
            Navigator.of(context).pop();
            onSelect(destination);
          },
        ),
    ],
  );
}

class _QueueDockPanel extends ConsumerWidget {
  const _QueueDockPanel();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerLow,
        border: Border(
          left: BorderSide(color: Theme.of(context).colorScheme.outlineVariant),
        ),
      ),
      child: PlaybackQueuePanel(
        handler: ref.watch(audioHandlerProvider),
        fillHeight: true,
        onClose: () => playbackQueueDockOpen.value = false,
      ),
    );
  }
}
