enum NowPlayingLayout { classic, split }

const nowPlayingLayoutSettingKey = 'player.now_playing.layout';

NowPlayingLayout parseNowPlayingLayout(String? value) => switch (value) {
  'split' => NowPlayingLayout.split,
  _ => NowPlayingLayout.classic,
};

String serializeNowPlayingLayout(NowPlayingLayout layout) => switch (layout) {
  NowPlayingLayout.classic => 'classic',
  NowPlayingLayout.split => 'split',
};
