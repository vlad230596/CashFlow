import 'package:flutter/foundation.dart';

enum AppSessionType {
  web,
  android,
  windows,
  ios,
  macos,
  linux,
  other;

  bool get canImportCashbackFile => this == AppSessionType.windows;

  bool get canLaunchCashbackBrowser => this == AppSessionType.windows;
}

AppSessionType detectAppSessionType() {
  if (kIsWeb) return AppSessionType.web;

  return switch (defaultTargetPlatform) {
    TargetPlatform.android => AppSessionType.android,
    TargetPlatform.windows => AppSessionType.windows,
    TargetPlatform.iOS => AppSessionType.ios,
    TargetPlatform.macOS => AppSessionType.macos,
    TargetPlatform.linux => AppSessionType.linux,
    TargetPlatform.fuchsia => AppSessionType.other,
  };
}
