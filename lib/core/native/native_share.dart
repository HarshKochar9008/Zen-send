import 'package:flutter/services.dart';

class NativeShareService {
  static const MethodChannel _channel = MethodChannel('zensend/native_share');

  static Future<void> shareText(String text, {String? subject}) async {
    await _channel.invokeMethod<void>('shareText', {
      'text': text,
      'subject': subject ?? 'ZenSend code',
    });
  }
}
