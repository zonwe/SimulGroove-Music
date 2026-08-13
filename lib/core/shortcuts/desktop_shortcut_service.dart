import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:hotkey_manager/hotkey_manager.dart';

import '../database/app_database.dart';
import '../player/music_audio_handler.dart';
import '../window/desktop_window_controller.dart';

enum DesktopShortcutAction {
  togglePlay,
  previous,
  next,
  showWindow,
  toggleWindow,
  quit,
}

extension DesktopShortcutActionLabel on DesktopShortcutAction {
  String get storageKey => name;

  String get label => switch (this) {
    DesktopShortcutAction.togglePlay => '播放 / 暂停',
    DesktopShortcutAction.previous => '上一首',
    DesktopShortcutAction.next => '下一首',
    DesktopShortcutAction.showWindow => '显示主窗口',
    DesktopShortcutAction.toggleWindow => '切换小窗',
    DesktopShortcutAction.quit => '退出应用',
  };
}

/// Owns the app's global and in-app desktop shortcuts.
///
/// Bindings are kept separately for each scope so the settings page can show
/// and edit the two kinds of shortcuts side by side.
class DesktopShortcutService {
  DesktopShortcutService._();

  static final instance = DesktopShortcutService._();

  static const settingsKey = 'desktop.shortcuts';

  final ValueNotifier<String?> lastError = ValueNotifier<String?>(null);
  final ValueNotifier<int> revision = ValueNotifier<int>(0);
  // Kept for compatibility with older settings widgets. New UI edits both
  // scopes explicitly and does not rely on this selector.
  final ValueNotifier<HotKeyScope> scope = ValueNotifier(HotKeyScope.system);
  final Map<DesktopShortcutAction, Map<HotKeyScope, HotKey>> _hotKeys = {};

  AppDatabase? _database;
  MusicAudioHandler? _handler;

  bool get isSupported =>
      !kIsWeb &&
      (defaultTargetPlatform == TargetPlatform.windows ||
          defaultTargetPlatform == TargetPlatform.linux);

  HotKey? hotKeyFor(
    DesktopShortcutAction action, [
    HotKeyScope? bindingScope,
  ]) => _hotKeys[action]?[bindingScope ?? scope.value];

  Future<void> setScope(HotKeyScope value) async {
    scope.value = value;
    if (isSupported) {
      await hotKeyManager.unregisterAll();
      await _registerAll();
    }
  }

  Future<void> initialize({
    required AppDatabase database,
    required MusicAudioHandler handler,
  }) async {
    _database = database;
    _handler = handler;
    _hotKeys
      ..clear()
      ..addAll(await _readHotKeys(database));
    if (isSupported) {
      // This also clears registrations left behind by a previous hot reload.
      await hotKeyManager.unregisterAll();
      await _registerAll();
    }
    _notifyChanged();
  }

  Future<String?> update(
    DesktopShortcutAction action,
    Object scopeOrRecorded, [
    HotKey? recordedArgument,
  ]) async {
    final bindingScope = scopeOrRecorded is HotKeyScope
        ? scopeOrRecorded
        : scope.value;
    final recorded = scopeOrRecorded is HotKey
        ? scopeOrRecorded
        : recordedArgument;
    if (recorded == null) return '未录制快捷键';
    final hotKey = HotKey(
      identifier: _identifier(action, bindingScope),
      key: recorded.key,
      modifiers: recorded.modifiers,
      scope: bindingScope,
    );
    final duplicate = _hotKeys.entries.any((entry) {
      final existing = entry.value[bindingScope];
      return entry.key != action &&
          existing != null &&
          _sameHotKey(existing, hotKey);
    });
    if (duplicate) {
      const message = '该快捷键已被本作用域的其他操作使用';
      lastError.value = message;
      return message;
    }

    final previous = _hotKeys[action]?[bindingScope];
    if (isSupported && previous != null) {
      await hotKeyManager.unregister(previous);
    }
    try {
      if (isSupported) {
        await hotKeyManager.register(
          hotKey,
          keyDownHandler: (_) => unawaited(_run(action)),
        );
      }
      (_hotKeys[action] ??= {})[bindingScope] = hotKey;
      await _saveHotKeys();
      lastError.value = null;
      _notifyChanged();
      return null;
    } catch (error) {
      if (previous != null && isSupported) {
        await hotKeyManager.register(
          previous,
          keyDownHandler: (_) => unawaited(_run(action)),
        );
      }
      final message = '注册失败，可能已被其他应用或系统占用：$error';
      lastError.value = message;
      return message;
    }
  }

  Future<void> remove(DesktopShortcutAction action, HotKeyScope scope) async {
    final previous = _hotKeys[action]?.remove(scope);
    if (isSupported && previous != null) {
      await hotKeyManager.unregister(previous);
    }
    if (_hotKeys[action]?.isEmpty ?? false) _hotKeys.remove(action);
    await _saveHotKeys();
    lastError.value = null;
    _notifyChanged();
  }

  Future<void> clearAll() async {
    if (isSupported) await hotKeyManager.unregisterAll();
    _hotKeys.clear();
    await _saveHotKeys();
    lastError.value = null;
    _notifyChanged();
  }

  Future<void> _registerAll() async {
    if (!isSupported) return;
    lastError.value = null;
    for (final entry in _hotKeys.entries) {
      for (final binding in entry.value.entries) {
        final action = entry.key;
        final scope = binding.key;
        final hotKey = HotKey(
          identifier: _identifier(action, scope),
          key: binding.value.key,
          modifiers: binding.value.modifiers,
          scope: scope,
        );
        try {
          await hotKeyManager.register(
            hotKey,
            keyDownHandler: (_) => unawaited(_run(action)),
          );
          entry.value[scope] = hotKey;
        } catch (error) {
          lastError.value = '${action.label} 注册失败，可能已被其他应用或系统占用：$error';
        }
      }
    }
  }

  Future<void> _run(DesktopShortcutAction action) async {
    final handler = _handler;
    if (handler == null) return;
    try {
      switch (action) {
        case DesktopShortcutAction.togglePlay:
          if (handler.mediaItem.value == null) return;
          if (handler.playbackState.value.playing) {
            await handler.pause();
          } else {
            await handler.play();
          }
        case DesktopShortcutAction.previous:
          await handler.skipToPrevious();
        case DesktopShortcutAction.next:
          await handler.skipToNext();
        case DesktopShortcutAction.showWindow:
          await DesktopWindowController.show();
        case DesktopShortcutAction.toggleWindow:
          await DesktopWindowController.toggleCompact();
        case DesktopShortcutAction.quit:
          await DesktopWindowController.quit();
      }
    } catch (error) {
      lastError.value = '快捷键操作失败：$error';
    }
  }

  Future<Map<DesktopShortcutAction, Map<HotKeyScope, HotKey>>> _readHotKeys(
    AppDatabase database,
  ) async {
    final raw = await database.readSetting(settingsKey);
    if (raw == null || raw.isEmpty) return {};
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map || decoded['version'] != 2) {
        // The previous format contained one binding per action. It is
        // intentionally discarded so old defaults cannot reappear.
        await database.setSetting(settingsKey, _emptyJson());
        return {};
      }
      final bindings = decoded['bindings'];
      if (bindings is! Map) return {};
      final result = <DesktopShortcutAction, Map<HotKeyScope, HotKey>>{};
      for (final action in DesktopShortcutAction.values) {
        final actionJson = bindings[action.storageKey];
        if (actionJson is! Map) continue;
        final actionBindings = <HotKeyScope, HotKey>{};
        for (final scope in HotKeyScope.values) {
          final value = actionJson[scope.name];
          if (value is Map) {
            actionBindings[scope] = HotKey.fromJson(
              Map<String, dynamic>.from(value),
            );
          }
        }
        if (actionBindings.isNotEmpty) result[action] = actionBindings;
      }
      return result;
    } catch (_) {
      await database.setSetting(settingsKey, _emptyJson());
      return {};
    }
  }

  Future<void> _saveHotKeys() async {
    final encoded = <String, dynamic>{
      'version': 2,
      'bindings': {
        for (final entry in _hotKeys.entries)
          entry.key.storageKey: {
            for (final binding in entry.value.entries)
              binding.key.name: binding.value.toJson(),
          },
      },
    };
    await _database?.setSetting(settingsKey, jsonEncode(encoded));
  }

  String _identifier(DesktopShortcutAction action, HotKeyScope scope) =>
      '${action.storageKey}.${scope.name}';

  String _emptyJson() => jsonEncode(const {'version': 2, 'bindings': {}});

  bool _sameHotKey(HotKey left, HotKey right) {
    final leftModifiers = (left.modifiers ?? const <HotKeyModifier>[])
        .map((modifier) => modifier.name)
        .toSet();
    final rightModifiers = (right.modifiers ?? const <HotKeyModifier>[])
        .map((modifier) => modifier.name)
        .toSet();
    return left.physicalKey.debugName == right.physicalKey.debugName &&
        setEquals(leftModifiers, rightModifiers);
  }

  void _notifyChanged() => revision.value++;
}
