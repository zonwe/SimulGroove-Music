const onlineSearchShowArtworkSettingKey = 'online_music.search.show_artwork';

bool onlineSearchShowArtworkFromSettings(Map<String, String> settings) =>
    settings[onlineSearchShowArtworkSettingKey] != 'false';
