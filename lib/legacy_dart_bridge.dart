import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:path_provider/path_provider.dart';

import 'gbk_codec.dart';

/// A machine-readable failure code, surfaced to Dart callers as a
/// [PlatformException] by [LegacyTransport].
class LegacyBridgeException implements Exception {
  const LegacyBridgeException(this.code, this.message);
  final String code;
  final String message;
  @override
  String toString() => message;
}

/// Relay-scoped cookie jar (mirrors `ApiSessionCookies.kt` semantics).
class ApiJar {
  ApiJar(this._values);
  final Map<String, String> _values;

  static final _sessionId = RegExp(r'^[A-Za-z0-9,-]{8,256}$');
  static final _cookieName = RegExp(r"^[!#$%&'*+.^_`|~A-Za-z0-9-]+$");
  static final _combined = RegExp(r",\s*(?=[!#$%&'*+.^_`|~A-Za-z0-9-]+=)");

  static ApiJar empty() => ApiJar(const {});

  bool get hasSession => _sessionId.hasMatch(_values['PHPSESSID'] ?? '');
  bool get hasWebLogin => (_values['jieqiUserInfo'] ?? '').isNotEmpty;
  String header() =>
      _values.entries.map((e) => '${e.key}=${e.value}').join('; ');

  /// Only the site's CMS session transfers to the official website.
  ApiJar websiteSession() => ApiJar({
    for (final e in _values.entries)
      if (e.key == 'PHPSESSID' || e.key.startsWith('jieqi')) e.key: e.value,
  });

  ApiJar merge(List<String> headers) {
    final next = Map<String, String>.of(_values);
    for (final header in headers) {
      for (final field in header.split(_combined)) {
        final pair = field.split(';').first;
        final eq = pair.indexOf('=');
        if (eq <= 0) continue;
        final name = pair.substring(0, eq).trim();
        final value = pair.substring(eq + 1).trim();
        if (!_cookieName.hasMatch(name)) continue;
        if (_expired(field) || value.isEmpty) {
          next.remove(name);
        } else {
          next[name] = value;
        }
      }
    }
    final jar = ApiJar(next);
    if (next.length > 32) {
      throw const LegacyBridgeException(
        'LEGACY_API_ERROR',
        'Request or local storage failed',
      );
    }
    if (jar.header().length > 16384) {
      throw const LegacyBridgeException(
        'LEGACY_API_ERROR',
        'Request or local storage failed',
      );
    }
    return jar;
  }

  static bool _expired(String field) {
    final maxAge = RegExp(
      r'Max-Age\s*=\s*(-?\d+)',
      caseSensitive: false,
    ).firstMatch(field);
    if (maxAge != null && int.parse(maxAge.group(1)!) <= 0) return true;
    final expires = RegExp(
      r'Expires\s*=\s*(.+?)(?:;|$)',
      caseSensitive: false,
    ).firstMatch(field);
    if (expires != null) {
      try {
        if (!HttpDate.parse(expires.group(1)!.trim()).isAfter(DateTime.now())) {
          return true;
        }
      } catch (_) {
        /* Unparseable date treated as a live cookie. */
      }
    }
    return false;
  }

  @override
  bool operator ==(Object other) =>
      other is ApiJar && _sameMap(_values, other._values);
  @override
  int get hashCode =>
      Object.hashAll(_values.entries.expand((e) => [e.key, e.value]));

  static bool _sameMap(Map<String, String> a, Map<String, String> b) {
    if (a.length != b.length) return false;
    for (final e in a.entries) {
      if (b[e.key] != e.value) return false;
    }
    return true;
  }
}

class _Reply {
  const _Reply(this.bytes, this.setCookies);
  final Uint8List bytes;
  final List<String> setCookies;
}

class _WebPage {
  const _WebPage(this.html, this.cookies);
  final String html;
  final ApiJar cookies;
}

/// Pure-Dart reimplementation of the Android v1.30 legacy API bridge
/// (`Wenku8Bridge.kt` + `TokenManager`), used when the native MethodChannel
/// plugin is absent (iOS). Request/appver logic mirrors the closed-source
/// `libcpp.so` exactly.
final class DartLegacyBridge {
  DartLegacyBridge._();
  static final instance = DartLegacyBridge._();

  static const _relayEndpoint = 'https://wenku8-relay.mewx.org/';
  static const _webOrigin = 'https://www.wenku8.net';
  static const _gateway = 'https://app.3952039.xyz';
  static const _cookiePrefix = 'cookies-v2:';
  static const _accountFile = 'wenku_account_session';
  static const _webFile = 'wenku_web_session';
  static const _illustrationDirName = 'wenku8-illustrations-v1';
  static const _maxRelayBytes = 8 * 1024 * 1024;
  static const _maxImageBytes = 8 * 1024 * 1024;
  static const _maxWebBytes = 2 * 1024 * 1024;

  ApiJar? _account;
  ApiJar? _web;
  bool _loaded = false;
  bool _webOnly = false;
  ApiJar? _observed;
  bool updatePriority = false;
  int _bypassUntil = 0;
  Future<Directory>? _support;

  // ---------------------------------------------------------------------
  // Public API, invoked by LegacyTransport on platforms without the plugin.
  // ---------------------------------------------------------------------

  Future<String> request(String action) async {
    final bytes = await _requestBytes(action, null, allowPublicFallback: true);
    return utf8.decode(bytes);
  }

  Future<Uint8List> cover(int aid) async {
    if (aid <= 0) throw ArgumentError('Invalid cover ID');
    final bytes = await _requestBytes(
      'action=book&do=cover&aid=$aid',
      null,
      allowPublicFallback: true,
    );
    _validateImage(bytes);
    return bytes;
  }

  Future<String> accountRequest(String action) async {
    final account = await _accountOrNull();
    if (account == null) return '4';
    final reply = await _relay(action, account);
    final text = utf8.decode(reply.bytes);
    final next = account.merge(reply.setCookies);
    if (next != account && text.trim() != '4') {
      _account = next.hasSession ? next : null;
      await _saveAccount();
    }
    return text;
  }

  Future<String> login(String action) async {
    if (!action.startsWith('action=login&') &&
        !action.startsWith('action=loginemail&')) {
      throw ArgumentError('Not a login action');
    }
    final reply = await _relay(action, null);
    final text = utf8.decode(reply.bytes);
    if (text.trim() == '1') {
      final cookie = ApiJar.empty().merge(reply.setCookies);
      if (!cookie.hasSession) {
        throw const LegacyBridgeException(
          'LEGACY_API_ERROR',
          'Request or local storage failed',
        );
      }
      _account = cookie;
      _web = null;
      _webOnly = false;
      _observed = null;
      await _saveAccount();
      await _saveWeb();
    }
    return text;
  }

  Future<bool> hasSession() async =>
      (await _accountOrNull())?.hasSession ?? false;

  Future<void> clearSession() async {
    _account = null;
    _web = null;
    _webOnly = false;
    _observed = null;
    await _saveAccount();
    await _saveWeb();
  }

  Future<Uint8List> accountAvatar() async {
    final account = await _accountOrNull();
    if (account == null) {
      throw const LegacyBridgeException(
        'LEGACY_API_ERROR',
        'Request or local storage failed',
      );
    }
    final reply = await _relay('action=avatar', account);
    if (reply.bytes.length > 2 * 1024 * 1024) {
      throw const LegacyBridgeException(
        'LEGACY_API_ERROR',
        'Request or local storage failed',
      );
    }
    _validateImage(reply.bytes);
    return reply.bytes;
  }

  Future<void> webLogin(String username, String password) async {
    final account = await _accountOrNull();
    if (account == null ||
        username.isEmpty ||
        username.length > 254 ||
        password.isEmpty ||
        password.length > 30) {
      throw const LegacyBridgeException(
        'LEGACY_API_ERROR',
        'Request or local storage failed',
      );
    }
    if (!GbkCodec.canEncode(username) || !GbkCodec.canEncode(password)) {
      throw const LegacyBridgeException(
        'WEB_LOGIN_FAILED',
        '官网账号使用 GBK 编码，无法提交这些字符',
      );
    }
    final body =
        'username=${_gbkUrlEncode(username)}&password=${_gbkUrlEncode(password)}'
        '&action=login&usecookie=315360000';
    final seed = await _webRequest(
      Uri.parse('$_webOrigin/login.php'),
      account.websiteSession(),
      null,
    );
    final reply = await _webRequest(
      Uri.parse('$_webOrigin/login.php?do=submit'),
      seed.cookies,
      body,
    );
    if (!reply.cookies.hasWebLogin) {
      final message = reply.html.contains('验证码')
          ? '官网要求额外验证，暂时无法连接分类'
          : '官网未接受本次账号登录，当前文库账号仍保持登录';
      throw LegacyBridgeException('WEB_LOGIN_FAILED', message);
    }
    _web = reply.cookies;
    await _saveWeb();
  }

  Future<String> publicationPage(int library, int page) async {
    if (library < 1 || library > 10000 || page < 1 || page > 100000) {
      throw const LegacyBridgeException(
        'LEGACY_API_ERROR',
        'Request or local storage failed',
      );
    }
    final account = await _accountOrNull();
    if (account == null) {
      throw const LegacyBridgeException('WEB_LOGIN_REQUIRED', '请先登录文库账号');
    }
    if (_observed != account) {
      _webOnly = false;
      _observed = account;
    }
    if (!_webOnly) {
      final reply = await _relay(
        'action=novellist&sort=$library&page=$page&t=0',
        account,
      );
      var body = utf8.decode(reply.bytes).trim();
      if (body.startsWith('\uFEFF')) {
        body = body.substring(1).trimLeft();
      }
      final next = account.merge(reply.setCookies);
      if (next != account) {
        _account = next.hasSession ? next : null;
        await _saveAccount();
      }
      if (RegExp(r'^(?:<\?xml[^>]*>\s*)?<result(?:\s|/|>)').hasMatch(body)) {
        return body;
      }
      if (body != '4') {
        throw const LegacyBridgeException('WEB_RESPONSE', '出版分类返回格式有误，请稍后重试');
      }
      _webOnly = true;
    }
    final web = _web ?? account.websiteSession();
    final reply = await _webRequest(
      Uri.parse(
        '$_webOrigin/modules/article/articlelist.php?class=$library&sort=lastupdate&page=$page',
      ),
      web,
      null,
    );
    if (_web != null || reply.cookies.hasWebLogin) {
      if (reply.cookies != web) {
        _web = reply.cookies.hasWebLogin ? reply.cookies : null;
        await _saveWeb();
      }
    }
    return reply.html;
  }

  Future<String> encodeReview(String text) async {
    if (text.length > 10000) {
      throw const LegacyBridgeException(
        'LEGACY_API_ERROR',
        'Request or local storage failed',
      );
    }
    if (!GbkCodec.canEncode(text)) {
      throw const LegacyBridgeException(
        'REVIEW_ENCODING',
        'Characters outside the review encoding',
      );
    }
    return base64Encode(utf8.encode(_gbkUrlEncode(text)));
  }

  Future<Uint8List> illustration(String url) async {
    final uri = _parseIllustration(url);
    final name = sha256.convert(utf8.encode(url)).toString();
    final dir = await _illustrationDir();
    final file = File('${dir.path}${Platform.pathSeparator}$name');
    if (await file.exists()) {
      try {
        final length = await file.length();
        if (length < 1 || length > _maxImageBytes) {
          throw const LegacyBridgeException(
            'LEGACY_API_ERROR',
            'Request or local storage failed',
          );
        }
        final cached = await file.readAsBytes();
        _validateImage(cached);
        await file.setLastModified(DateTime.now());
        return cached;
      } catch (_) {
        try {
          await file.delete();
        } catch (_) {}
      }
    }
    Uint8List bytes;
    try {
      bytes = await _downloadOriginal(uri);
    } on Exception {
      final gateway = await _gatewayImage(uri);
      if (gateway == null) rethrow;
      bytes = gateway;
    }
    try {
      await dir.create(recursive: true);
      final temporary = File('${dir.path}${Platform.pathSeparator}$name.part');
      await temporary.writeAsBytes(bytes, flush: true);
      if (await file.exists()) {
        await file.delete();
      }
      await temporary.rename(file.path);
      var size = 0;
      final entries = <(File, DateTime, int)>[];
      await for (final entry in dir.list()) {
        if (entry is! File || entry.path.endsWith('.part')) continue;
        try {
          final stat = await entry.stat();
          size += stat.size;
          entries.add((entry, stat.modified, stat.size));
        } catch (_) {}
      }
      entries.sort((a, b) => a.$2.compareTo(b.$2));
      for (final (entry, _, length) in entries) {
        if (size <= 256 * 1024 * 1024) break;
        if (entry.path != file.path) {
          try {
            await entry.delete();
            size -= length;
          } catch (_) {}
        }
      }
    } catch (_) {
      /* An online illustration survives a cache write error. */
    }
    return bytes;
  }

  Future<void> clearIllustrations() async {
    try {
      final dir = await _illustrationDir();
      if (await dir.exists()) {
        await dir.delete(recursive: true);
      }
    } catch (_) {}
  }

  // ---------------------------------------------------------------------
  // Relay transport.
  // ---------------------------------------------------------------------

  Future<Uint8List> _requestBytes(
    String action,
    ApiJar? cookie, {
    bool allowPublicFallback = false,
  }) async {
    try {
      return (await _relay(action, cookie)).bytes;
    } on Exception {
      if (cookie == null && allowPublicFallback) {
        final cover = _coverFallbackUrl(action);
        if (cover != null) {
          final bytes = await _download(Uri.parse(cover));
          _validateImage(bytes);
          return bytes;
        }
      }
      rethrow;
    }
  }

  Future<_Reply> _relay(String action, ApiJar? cookie) async {
    if (action.isEmpty || action.length > 60000) {
      throw const LegacyBridgeException(
        'LEGACY_API_ERROR',
        'Request or local storage failed',
      );
    }
    final version = magicVersion('1.30');
    final encoded = base64Encode(utf8.encode(action));
    final body =
        '&appver=$version&request=$encoded&timetoken=${DateTime.now().millisecondsSinceEpoch}';
    final client = HttpClient();
    try {
      final request = await client.postUrl(Uri.parse(_relayEndpoint));
      request.headers.contentType = ContentType(
        'application',
        'x-www-form-urlencoded',
        charset: 'utf-8',
      );
      request.headers.set(HttpHeaders.acceptEncodingHeader, 'gzip');
      final header = cookie?.header() ?? '';
      if (header.isNotEmpty) {
        request.headers.set(HttpHeaders.cookieHeader, header);
      }
      request.add(utf8.encode(body));
      final response = await request.close();
      final status = response.statusCode;
      final cookies =
          response.headers[HttpHeaders.setCookieHeader] ?? const <String>[];
      final bytes = await _readBounded(response, _maxRelayBytes);
      if (status < 200 || status > 299) {
        throw const LegacyBridgeException(
          'LEGACY_API_ERROR',
          'Request or local storage failed',
        );
      }
      return _Reply(bytes, cookies);
    } finally {
      client.close(force: true);
    }
  }

  // ---------------------------------------------------------------------
  // Official website (wenku8.net) transport.
  // ---------------------------------------------------------------------

  Future<_WebPage> _webRequest(Uri start, ApiJar initial, String? form) async {
    var url = start;
    var cookies = initial;
    var body = form;
    for (var hop = 0; hop < 4; hop++) {
      final client = HttpClient();
      try {
        final request = body != null
            ? await client.postUrl(url)
            : await client.getUrl(url);
        request.followRedirects = false;
        request.headers.set(HttpHeaders.acceptEncodingHeader, 'gzip');
        request.headers.set(
          HttpHeaders.acceptHeader,
          'text/html,application/xhtml+xml',
        );
        final header = cookies.header();
        if (header.isNotEmpty) {
          request.headers.set(HttpHeaders.cookieHeader, header);
        }
        if (body != null) {
          request.headers.contentType = ContentType(
            'application',
            'x-www-form-urlencoded',
            charset: 'GBK',
          );
          request.headers.set(
            HttpHeaders.refererHeader,
            '$_webOrigin/login.php',
          );
          request.add(ascii.encode(body));
        }
        final response = await request.close();
        final setCookies =
            response.headers[HttpHeaders.setCookieHeader] ?? const <String>[];
        cookies = cookies.merge(setCookies);
        final status = response.statusCode;
        if (status == 301 ||
            status == 302 ||
            status == 303 ||
            status == 307 ||
            status == 308) {
          final location = response.headers.value(HttpHeaders.locationHeader);
          if (location == null || location.isEmpty) {
            throw const LegacyBridgeException('WEB_RESPONSE', '分类跳转地址无效');
          }
          final next = url.resolve(location);
          final port = next.hasPort ? next.port : -1;
          if (hop == 3 ||
              next.scheme != 'https' ||
              next.host != 'www.wenku8.net' ||
              port != -1 && port != 443 ||
              next.userInfo.isNotEmpty) {
            throw const LegacyBridgeException(
              'WEB_RESPONSE',
              '分类连接地址发生变化，请稍后重试',
            );
          }
          url = next;
          if (status != 307 && status != 308) body = null;
          continue;
        }
        if (status == 403 || status == 429) {
          throw const LegacyBridgeException(
            'WEB_UNAVAILABLE',
            '官网暂时拒绝分类请求，请稍后重试；当前账号仍保持登录',
          );
        }
        if (status < 200 || status > 299) {
          throw const LegacyBridgeException(
            'WEB_UNAVAILABLE',
            '官网分类暂时不可用，请稍后重试',
          );
        }
        final bytes = await _readBounded(response, _maxWebBytes);
        final charset = response.headers.contentType?.charset?.toLowerCase();
        final isUtf8 = charset == 'utf-8' || _declaresUtf8(bytes);
        final html = isUtf8
            ? utf8.decode(bytes, allowMalformed: true)
            : GbkCodec.decode(bytes);
        return _WebPage(html, cookies);
      } finally {
        client.close(force: true);
      }
    }
    throw const LegacyBridgeException('WEB_RESPONSE', '分类跳转次数过多');
  }

  static bool _declaresUtf8(Uint8List bytes) {
    final head = latin1.decode(
      Uint8List.sublistView(
        bytes,
        0,
        bytes.length > 2048 ? 2048 : bytes.length,
      ),
      allowInvalid: true,
    );
    return RegExp(
      "charset\\s*=\\s*[\"']?utf-8",
      caseSensitive: false,
    ).hasMatch(head);
  }

  // ---------------------------------------------------------------------
  // Images.
  // ---------------------------------------------------------------------

  Future<Uint8List> _downloadOriginal(Uri source) async {
    var url = source;
    for (var hop = 0; hop < 4; hop++) {
      final client = HttpClient();
      try {
        final request = await client.getUrl(url);
        request.followRedirects = false;
        final response = await request.close();
        final status = response.statusCode;
        if (status == 301 ||
            status == 302 ||
            status == 303 ||
            status == 307 ||
            status == 308) {
          if (hop >= 3) {
            throw const LegacyBridgeException(
              'LEGACY_API_ERROR',
              'Request or local storage failed',
            );
          }
          final location = response.headers.value(HttpHeaders.locationHeader);
          if (location == null || location.isEmpty) {
            throw const LegacyBridgeException(
              'LEGACY_API_ERROR',
              'Request or local storage failed',
            );
          }
          url = _redirect(url, location);
        } else {
          if (status < 200 || status > 299) {
            throw const LegacyBridgeException(
              'LEGACY_API_ERROR',
              'Request or local storage failed',
            );
          }
          final bytes = await _readBounded(response, _maxImageBytes);
          _validateImage(bytes);
          return bytes;
        }
      } finally {
        client.close(force: true);
      }
    }
    throw const LegacyBridgeException(
      'LEGACY_API_ERROR',
      'Request or local storage failed',
    );
  }

  /// Direct fetch with no host policy (public cover fallback).
  Future<Uint8List> _download(Uri source) async {
    final client = HttpClient();
    try {
      final request = await client.getUrl(source);
      request.followRedirects = false;
      final response = await request.close();
      if (response.statusCode < 200 || response.statusCode > 299) {
        throw const LegacyBridgeException(
          'LEGACY_API_ERROR',
          'Request or local storage failed',
        );
      }
      return await _readBounded(response, _maxImageBytes);
    } finally {
      client.close(force: true);
    }
  }

  Uri _redirect(Uri from, String location) {
    final next = from.resolve(location);
    if (next.scheme != 'http' && next.scheme != 'https') {
      throw const LegacyBridgeException(
        'LEGACY_API_ERROR',
        'Request or local storage failed',
      );
    }
    final port = next.hasPort ? next.port : -1;
    if (port != -1 && port != 80 && port != 443) {
      throw const LegacyBridgeException(
        'LEGACY_API_ERROR',
        'Request or local storage failed',
      );
    }
    final authority = next.hasPort && next.port == 80
        ? next.authority.replaceFirst(RegExp(r':80$'), '')
        : next.authority;
    final secure =
        'https://$authority${next.path}'
        '${next.hasQuery ? '?${next.query}' : ''}'
        '${next.hasFragment ? '#${next.fragment}' : ''}';
    return _parseIllustration(secure);
  }

  Future<Uint8List?> _gatewayImage(Uri source) async {
    if (!_policyImage(source) ||
        updatePriority ||
        DateTime.now().millisecondsSinceEpoch < _bypassUntil) {
      return null;
    }
    final path = base64Url
        .encode(utf8.encode(source.toString()))
        .replaceAll('=', '');
    final client = HttpClient();
    try {
      final request = await client.getUrl(Uri.parse('$_gateway/image/$path'));
      request.headers.set(HttpHeaders.acceptEncodingHeader, 'gzip');
      request.headers.set(HttpHeaders.userAgentHeader, 'Wenku8-Flutter');
      final response = await request.close();
      if (response.statusCode != 200) {
        final retry = response.headers.value('retry-after');
        final seconds =
            int.tryParse(retry ?? '')?.clamp(60, 86400).toInt() ?? 60;
        _bypassUntil = DateTime.now().millisecondsSinceEpoch + seconds * 1000;
        return null;
      }
      final bytes = await _readBounded(response, _maxImageBytes);
      if (bytes.isEmpty) return null;
      return bytes;
    } on Exception {
      _bypassUntil = DateTime.now().millisecondsSinceEpoch + 60 * 1000;
      return null;
    } finally {
      client.close(force: true);
    }
  }

  Uri _parseIllustration(String raw) {
    final uri = Uri.tryParse(raw);
    if (uri == null) {
      throw const LegacyBridgeException(
        'LEGACY_API_ERROR',
        'Request or local storage failed',
      );
    }
    final port = uri.hasPort ? uri.port : -1;
    final host = uri.host.toLowerCase();
    final allowed = port == -1 || port == 443;
    final hostOk =
        host == 'wenku8.com' ||
        host.endsWith('.wenku8.com') ||
        host == 'wenku8.net' ||
        host.endsWith('.wenku8.net') ||
        host == 'wenku8.cn' ||
        host.endsWith('.wenku8.cn') ||
        host == 'pic.777743.xyz';
    if (uri.scheme != 'https' ||
        uri.userInfo.isNotEmpty ||
        !allowed ||
        !hostOk) {
      throw const LegacyBridgeException(
        'LEGACY_API_ERROR',
        'Request or local storage failed',
      );
    }
    return uri;
  }

  static bool _policyImage(Uri uri) {
    if (uri.scheme != 'https' ||
        uri.userInfo.isNotEmpty ||
        (uri.hasPort && uri.port != -1 && uri.port != 443) ||
        uri.hasQuery ||
        uri.hasFragment) {
      return false;
    }
    final host = uri.host.toLowerCase();
    if (!{
      'img.wenku8.com',
      'pic.wenku8.com',
      'pic.wenku8.cn',
      'pic.wenku8.net',
      'pic.777743.xyz',
    }.contains(host)) {
      return false;
    }
    return RegExp(
      r'/(?:image|pictures|\d+)/[a-zA-Z0-9_/-]+\.(?:jpe?g|png|gif|webp)',
      caseSensitive: false,
    ).hasMatch(uri.path);
  }

  static String? _coverFallbackUrl(String action) {
    final match = RegExp(
      r'action=book&do=cover&aid=([1-9]\d{0,7})(?:&t=0)?',
    ).firstMatch(action);
    if (match == null) return null;
    final aid = int.tryParse(match.group(1)!);
    if (aid == null || aid <= 0) return null;
    return 'https://img.wenku8.com/image/${aid ~/ 1000}/$aid/${aid}s.jpg';
  }

  static void _validateImage(Uint8List bytes) {
    if (bytes.isEmpty || bytes.length > _maxImageBytes) {
      throw const LegacyBridgeException(
        'LEGACY_API_ERROR',
        'Request or local storage failed',
      );
    }
    final ok =
        _isJpeg(bytes) || _isPng(bytes) || _isGif(bytes) || _isWebp(bytes);
    if (!ok) {
      throw const LegacyBridgeException(
        'LEGACY_API_ERROR',
        'Request or local storage failed',
      );
    }
    final size = _imageSize(bytes);
    if (size != null &&
        (size.$1 <= 0 ||
            size.$2 <= 0 ||
            size.$1 * size.$2 > 50 * 1000 * 1000)) {
      throw const LegacyBridgeException(
        'LEGACY_API_ERROR',
        'Request or local storage failed',
      );
    }
  }

  static bool _isJpeg(Uint8List b) =>
      b.length >= 3 && b[0] == 0xFF && b[1] == 0xD8 && b[2] == 0xFF;
  static bool _isPng(Uint8List b) =>
      b.length >= 8 &&
      b[0] == 0x89 &&
      b[1] == 0x50 &&
      b[2] == 0x4E &&
      b[3] == 0x47 &&
      b[4] == 0x0D &&
      b[5] == 0x0A &&
      b[6] == 0x1A &&
      b[7] == 0x0A;
  static bool _isGif(Uint8List b) =>
      b.length >= 6 &&
      b[0] == 0x47 &&
      b[1] == 0x49 &&
      b[2] == 0x46 &&
      b[3] == 0x38 &&
      (b[4] == 0x37 || b[4] == 0x39) &&
      b[5] == 0x61;
  static bool _isWebp(Uint8List b) =>
      b.length >= 12 &&
      b[0] == 0x52 &&
      b[1] == 0x49 &&
      b[2] == 0x46 &&
      b[3] == 0x46 &&
      b[8] == 0x57 &&
      b[9] == 0x45 &&
      b[10] == 0x42 &&
      b[11] == 0x50;

  /// Best-effort width/height; null when the layout cannot be parsed.
  static (int, int)? _imageSize(Uint8List b) {
    if (_isJpeg(b)) {
      var i = 2;
      while (i + 9 < b.length) {
        if (b[i] != 0xFF) {
          i++;
          continue;
        }
        final marker = b[i + 1];
        if (marker >= 0xC0 &&
            marker <= 0xCF &&
            marker != 0xC4 &&
            marker != 0xC8 &&
            marker != 0xCC) {
          final height = (b[i + 5] << 8) | b[i + 6];
          final width = (b[i + 7] << 8) | b[i + 8];
          return (width, height);
        }
        if (marker == 0xD8 || marker == 0xD9 || marker == 0x01) {
          i += 2;
        } else {
          final length = (b[i + 2] << 8) | b[i + 3];
          i += 2 + length;
        }
      }
      return null;
    }
    if (_isPng(b) && b.length >= 24) {
      final width = (b[16] << 24) | (b[17] << 16) | (b[18] << 8) | b[19];
      final height = (b[20] << 24) | (b[21] << 16) | (b[22] << 8) | b[23];
      return (width, height);
    }
    if (_isGif(b) && b.length >= 10) {
      return ((b[6] | (b[7] << 8)), (b[8] | (b[9] << 8)));
    }
    return null;
  }

  // ---------------------------------------------------------------------
  // Sessions and storage.
  // ---------------------------------------------------------------------

  Future<ApiJar?> _accountOrNull() async {
    await _ensureLoaded();
    return _account;
  }

  Future<void> _ensureLoaded() async {
    if (_loaded) return;
    _loaded = true;
    try {
      final dir = await _supportDir();
      final accountFile = File(
        '${dir.path}${Platform.pathSeparator}$_accountFile',
      );
      if (await accountFile.exists()) {
        final jar = _parseStored(await accountFile.readAsString(), true);
        if (jar != null) _account = jar;
      }
      final webFile = File('${dir.path}${Platform.pathSeparator}$_webFile');
      if (await webFile.exists()) {
        final jar = _parseStored(await webFile.readAsString(), false);
        if (jar != null) _web = jar;
      }
    } catch (_) {
      _account = null;
      _web = null;
    }
  }

  ApiJar? _parseStored(String value, bool requireSession) {
    if (RegExp(r'^[A-Za-z0-9,-]{8,256}$').hasMatch(value)) {
      return ApiJar({'PHPSESSID': value});
    }
    if (!value.startsWith(_cookiePrefix)) return null;
    final pairs = <String, String>{};
    for (final part in value.substring(_cookiePrefix.length).split('; ')) {
      final eq = part.indexOf('=');
      if (eq <= 0) return null;
      pairs[part.substring(0, eq)] = part.substring(eq + 1);
    }
    final jar = ApiJar(pairs);
    if (requireSession && !jar.hasSession) return null;
    return jar;
  }

  Future<void> _saveAccount() async {
    try {
      final file = File(
        '${(await _supportDir()).path}${Platform.pathSeparator}$_accountFile',
      );
      final jar = _account;
      if (jar == null) {
        if (await file.exists()) await file.delete();
      } else {
        await file.create(recursive: true);
        await file.writeAsString('$_cookiePrefix${jar.header()}', flush: true);
      }
    } catch (_) {
      /* A failed session write is not fatal. */
    }
  }

  Future<void> _saveWeb() async {
    try {
      final file = File(
        '${(await _supportDir()).path}${Platform.pathSeparator}$_webFile',
      );
      final jar = _web;
      if (jar == null) {
        if (await file.exists()) await file.delete();
      } else {
        await file.create(recursive: true);
        await file.writeAsString('$_cookiePrefix${jar.header()}', flush: true);
      }
    } catch (_) {}
  }

  Future<Directory> _supportDir() =>
      _support ??= getApplicationSupportDirectory();

  Future<Directory> _illustrationDir() async {
    final dir = Directory(
      '${(await _supportDir()).path}${Platform.pathSeparator}$_illustrationDirName',
    );
    await dir.create(recursive: true);
    return dir;
  }

  // ---------------------------------------------------------------------
  // v1.30 magic version (exact port of the closed-source libcpp.so logic).
  // ---------------------------------------------------------------------

  static String magicVersion(String rawVersion) {
    final key = switch (rawVersion) {
      '1.30' => 'digital-bento',
      '1.23' => 'nano-mexw',
      _ => 'unknown',
    };
    final minutes = DateTime.now().millisecondsSinceEpoch ~/ 60000;
    final digest = Hmac(
      sha256,
      utf8.encode(key),
    ).convert(utf8.encode('$rawVersion|$key|$minutes')).toString();
    return '$rawVersion-$key-${digest.substring(12, 20)}';
  }

  static String _gbkUrlEncode(String text) {
    final bytes = GbkCodec.encodeBytes(text);
    final out = StringBuffer();
    for (final b in bytes) {
      if ((b >= 0x30 && b <= 0x39) ||
          (b >= 0x41 && b <= 0x5A) ||
          (b >= 0x61 && b <= 0x7A) ||
          b == 0x2E ||
          b == 0x2D ||
          b == 0x2A ||
          b == 0x5F) {
        out.writeCharCode(b);
      } else if (b == 0x20) {
        out.write('+');
      } else {
        out.write('%${b.toRadixString(16).toUpperCase().padLeft(2, '0')}');
      }
    }
    return out.toString();
  }

  Future<Uint8List> _readBounded(HttpClientResponse response, int limit) async {
    final builder = BytesBuilder(copy: false);
    await for (final chunk in response) {
      if (builder.length + chunk.length > limit) {
        throw const LegacyBridgeException(
          'LEGACY_API_ERROR',
          'Request or local storage failed',
        );
      }
      builder.add(chunk);
    }
    return builder.toBytes();
  }
}
