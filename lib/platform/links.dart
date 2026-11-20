/// Opening links outside the app: Telegram, the phone dialler, the mail app.
///
/// Behind a provider so widget tests can see what would have been opened without a plugin.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

/// Opens [uri] in the app that handles it. Returns false when nothing could.
typedef LinkOpener = Future<bool> Function(Uri uri);

final linkOpenerProvider = Provider<LinkOpener>(
  (ref) => (uri) async {
    try {
      return await launchUrl(uri, mode: LaunchMode.externalApplication);
    } on Exception {
      return false;
    }
  },
);
