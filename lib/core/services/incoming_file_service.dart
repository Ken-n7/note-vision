import 'dart:async';

import 'package:flutter/services.dart';

class IncomingFileService {
  IncomingFileService._();
  static final IncomingFileService instance = IncomingFileService._();

  static const _channel = MethodChannel('com.notevision.app/incoming_file');

  final _controller = StreamController<String>.broadcast();

  Stream<String> get filePathStream => _controller.stream;

  void init() {
    _channel.setMethodCallHandler((call) async {
      if (call.method == 'onFileReceived') {
        final path = call.arguments as String?;
        if (path != null) _controller.add(path);
      }
    });
  }

  void dispose() => _controller.close();
}
