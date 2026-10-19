import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'book_documents.dart';
import 'gbk_codec.dart';

/// iOS-only platform bridge (TrollStore 侧载版)。
///
/// Android 走 `org.mewx.wenku8/book_documents` 原生通道；iOS 没有对应原生
/// 实现，因此文件选择（UIDocumentPicker）、TXT 编码探测与解码、状态栏隐藏
/// 全部收口到本类 + `ios/Runner/AppDelegate.swift` 里的
/// `org.mewx.wenku8/ios_system` 通道。
abstract final class IosSystem {
  static const channel = MethodChannel('org.mewx.wenku8/ios_system');
  static bool get active =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.iOS;

  /// 文件选择（iOS 原生 UIDocumentPicker，asCopy 复制进沙盒）。
  static Future<List<BookDocumentSelection>> pickBooks() async {
    final values = await channel.invokeListMethod<dynamic>('pickBooks');
    return [
      for (final value in values ?? const [])
        BookDocumentSelection(
          name: value['name'] as String,
          path: value['path'] as String,
        ),
    ];
  }

  static Future<BookDocumentSelection?> pickFont() async {
    final value = await channel.invokeMapMethod<String, dynamic>('pickFont');
    return value == null
        ? null
        : BookDocumentSelection(
            name: value['name'] as String,
            path: value['path'] as String,
          );
  }

  /// 阅读页「隐藏系统状态栏」开关的真实生效点。
  static Future<void> setStatusBarHidden(bool hidden) async {
    try {
      await channel.invokeMethod<void>('setStatusBarHidden', {
        'hidden': hidden,
      });
    } catch (_) {
      /* 非致命：阅读页布局本身已按该设置折叠状态栏区域 */
    }
  }

  /// 语义对齐 Android 的 decodeTextFile：把解码后的全文写入临时文件并
  /// 返回文件路径，后续章节流式解析（importTextChapters）直接复用。
  static Future<String> decodeTextFile(
    String path, {
    String encoding = 'auto',
  }) async {
    final bytes = await File(path).readAsBytes();
    final text = await compute(_decodeBytes, _DecodeJob(bytes, encoding));
    final dir = await getTemporaryDirectory();
    final file = File(
      '${dir.path}/wenku8-decoded-${DateTime.now().microsecondsSinceEpoch}.txt',
    );
    await file.writeAsString(text, flush: true);
    return file.path;
  }

  /// iOS 无 SAF 与原生转码：非 TXT/EPUB 格式直接给出与 Android
  /// prepareBook 一致的错误项，避免 MissingPluginException 中断整批导入。
  static BookDocumentSelection unsupported(String name) =>
      BookDocumentSelection(name: name, error: '目前支持 TXT 与 EPUB 格式');
}

class _DecodeJob {
  const _DecodeJob(this.bytes, this.encoding);
  final Uint8List bytes;
  final String encoding;
}

/// Worker isolate 内执行：BOM → UTF-16 → 按指定编码 → auto 探测。
String _decodeBytes(_DecodeJob job) {
  final bytes = job.bytes;
  if (bytes.length >= 3 &&
      bytes[0] == 0xEF &&
      bytes[1] == 0xBB &&
      bytes[2] == 0xBF) {
    return utf8.decode(bytes.sublist(3));
  }
  if (bytes.length >= 2 && bytes[0] == 0xFF && bytes[1] == 0xFE) {
    return _decodeUtf16(bytes.sublist(2), false);
  }
  if (bytes.length >= 2 && bytes[0] == 0xFE && bytes[1] == 0xFF) {
    return _decodeUtf16(bytes.sublist(2), true);
  }
  switch (job.encoding) {
    case 'utf-8' || 'utf8':
      return utf8.decode(bytes);
    case 'utf-16' || 'utf16':
      return _decodeUtf16(bytes, false);
    case 'gbk':
      return GbkCodec.decode(bytes);
    case 'gb18030':
      return GbkCodec.decode(bytes);
    default:
      // auto：先按 UTF-8 严格解码（非法字节即失败），否则回退 GB18030。
      try {
        return utf8.decode(bytes, allowMalformed: false);
      } on FormatException {
        return GbkCodec.decode(bytes);
      }
  }
}

String _decodeUtf16(Uint8List bytes, bool bigEndian) {
  final units = <int>[];
  for (var i = 0; i + 1 < bytes.length; i += 2) {
    units.add(
      bigEndian
          ? (bytes[i] << 8) | bytes[i + 1]
          : (bytes[i + 1] << 8) | bytes[i],
    );
  }
  return String.fromCharCodes(units);
}
