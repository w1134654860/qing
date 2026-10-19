import 'dart:typed_data';

import 'package:flutter/services.dart';

import 'legacy_dart_bridge.dart';

/// The same v1.30 POST bridge. Account cookies never cross into Dart or backups.
///
/// Android resolves through the native MethodChannel implementation
/// (`Wenku8Bridge.kt`). Platforms without the native plugin (iOS) fall back to
/// the pure-Dart port in [DartLegacyBridge], which reimplements the bridge and
/// the closed-source `libcpp.so` appver logic exactly.
abstract final class LegacyTransport {
  static const channel = MethodChannel('org.mewx.wenku8/legacy_api');

  static Future<T> _pick<T>(
    Future<T> Function() native,
    Future<T> Function() dart,
  ) async {
    try {
      return await native();
    } on MissingPluginException {
      try {
        return await dart();
      } on LegacyBridgeException catch (failure) {
        throw PlatformException(code: failure.code, message: failure.message);
      }
    }
  }

  static Future<void> setUpdatePriority(bool enabled) async {
    try {
      await channel.invokeMethod<void>('updatePriority', {'enabled': enabled});
    } on MissingPluginException {
      DartLegacyBridge.instance.updatePriority = enabled;
    }
  }

  static Future<String> request(String action) => _pick(
    () => _text('request', action),
    () => DartLegacyBridge.instance.request(action),
  );
  static Future<String> accountRequest(String action) => _pick(
    () => _text('accountRequest', action),
    () => DartLegacyBridge.instance.accountRequest(action),
  );

  /// Read-only routes which the service may gate behind a signed-in session.
  /// Public discovery/search remain independent from account cookies.
  static Future<String> sessionRead(String action) async =>
      await hasSession() ? accountRequest(action) : request(action);
  static Future<String> login(String action) => _pick(
    () => _text('login', action),
    () => DartLegacyBridge.instance.login(action),
  );
  static Future<Uint8List> accountAvatar() => _pick(() async {
    final bytes = await channel.invokeMethod<Uint8List>('accountAvatar');
    if (bytes == null || bytes.isEmpty) throw const FormatException('账号暂无头像');
    return bytes;
  }, () => DartLegacyBridge.instance.accountAvatar());

  static Future<String> _text(String method, String action) async {
    final text = await channel.invokeMethod<String>(method, {'action': action});
    if (text == null || text.trim().isEmpty) {
      throw const FormatException('接口返回空内容');
    }
    return text;
  }

  static Future<bool> hasSession() async {
    try {
      return await channel.invokeMethod<bool>('hasSession') ?? false;
    } on MissingPluginException {
      return DartLegacyBridge.instance.hasSession();
    }
  }

  static Future<void> clearSession() => _pick(
    () => channel.invokeMethod<void>('clearSession'),
    () => DartLegacyBridge.instance.clearSession(),
  );

  static Future<void> connectPublications(
    String username,
    String password,
  ) async {
    try {
      await _pick(
        () => channel.invokeMethod<void>('webLogin', {
          'username': username,
          'password': password,
        }),
        () => DartLegacyBridge.instance.webLogin(username, password),
      );
    } on PlatformException catch (failure) {
      if (failure.code.startsWith('WEB_')) {
        throw FormatException(failure.message ?? '分类连接未成功');
      }
      rethrow;
    }
  }

  static Future<String> publicationPage(int library, int page) => _pick(
    () async =>
        (await channel.invokeMethod<String>('publicationPage', {
          'library': library,
          'page': page,
        })) ??
        '',
    () => DartLegacyBridge.instance.publicationPage(library, page),
  );

  static Future<Uint8List> illustration(String url) => _pick(() async {
    final bytes = await channel.invokeMethod<Uint8List>('illustration', {
      'url': url,
    });
    if (bytes == null || bytes.isEmpty) throw const FormatException('插图内容为空');
    return bytes;
  }, () => DartLegacyBridge.instance.illustration(url));

  static Future<void> clearIllustrations() => _pick(
    () => channel.invokeMethod<void>('clearIllustrations'),
    () => DartLegacyBridge.instance.clearIllustrations(),
  );

  static Future<String> encodeReview(String text) async {
    try {
      return await _pick(() async {
        final encoded = await channel.invokeMethod<String>('encodeReview', {
          'text': text,
        });
        if (encoded == null || encoded.isEmpty) {
          throw const FormatException('书评编码返回空内容');
        }
        return encoded;
      }, () => DartLegacyBridge.instance.encodeReview(text));
    } on PlatformException catch (error) {
      if (error.code == 'REVIEW_ENCODING') {
        throw const FormatException('原版书评接口使用 GBK，请移除表情或特殊字符后重试；草稿仍保留');
      }
      rethrow;
    }
  }
}
