/// The microphone and the camera, behind small interfaces.
///
/// The assistant sheet talks to a [VoiceRecorder] and a [ReceiptPicker], never to the plugins, so
/// widget tests swap in fakes and the plugins stay at the edge. The real implementations:
///
/// * [PluginVoiceRecorder] records AAC in an `.m4a` file in the temporary directory (small, and the
///   format the server expects), and deletes the file once its bytes are read. The sheet stops a
///   note at the plan's limit ([AssistantStatusDto.maxVoiceNote]) and sends what was said.
/// * [PluginReceiptPicker] takes a photo or picks one from the library, scaled to at most 2000 px
///   on the long side and re-compressed, which keeps a receipt legible and well under the server's
///   8 MB limit.
library;

import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:record/record.dart';

/// Used until the server's status arrives (and by older servers that do not send one).
const defaultMaxVoiceNote = Duration(seconds: 60);

/// Bytes plus their type, ready to upload.
class CapturedMedia {
  const CapturedMedia({required this.bytes, required this.contentType, required this.filename});

  final List<int> bytes;
  final String contentType;
  final String filename;
}

abstract class VoiceRecorder {
  /// Asks for the microphone the first time. False when the person said no.
  Future<bool> requestPermission();

  Future<void> start();

  /// Stop and hand back the recording, or null when nothing was captured.
  Future<CapturedMedia?> stop();

  /// Stop and throw the recording away.
  Future<void> cancel();

  Future<void> dispose();
}

enum ReceiptSource { camera, gallery }

abstract class ReceiptPicker {
  /// The chosen photo, or null when the person backed out.
  Future<CapturedMedia?> pick(ReceiptSource source);
}

class PluginVoiceRecorder implements VoiceRecorder {
  final AudioRecorder _recorder = AudioRecorder();
  String? _path;

  @override
  Future<bool> requestPermission() => _recorder.hasPermission();

  @override
  Future<void> start() async {
    final directory = await getTemporaryDirectory();
    final path = '${directory.path}/kise-voice-${DateTime.now().microsecondsSinceEpoch}.m4a';
    _path = path;
    // Mono, 16 kHz: speech, not music. Keeps a minute of audio around half a megabyte.
    await _recorder.start(
      const RecordConfig(encoder: AudioEncoder.aacLc, numChannels: 1, sampleRate: 16000),
      path: path,
    );
  }

  @override
  Future<CapturedMedia?> stop() async {
    final path = await _recorder.stop() ?? _path;
    _path = null;
    if (path == null) return null;
    final file = File(path);
    if (!await file.exists()) return null;
    final bytes = await file.readAsBytes();
    // The audio is not kept on the phone either.
    await file.delete().catchError((_) => file);
    if (bytes.isEmpty) return null;
    return CapturedMedia(bytes: bytes, contentType: 'audio/mp4', filename: 'voice.m4a');
  }

  @override
  Future<void> cancel() async {
    await _recorder.cancel();
    _path = null;
  }

  @override
  Future<void> dispose() => _recorder.dispose();
}

class PluginReceiptPicker implements ReceiptPicker {
  final ImagePicker _picker = ImagePicker();

  @override
  Future<CapturedMedia?> pick(ReceiptSource source) async {
    final file = await _picker.pickImage(
      source: source == ReceiptSource.camera ? ImageSource.camera : ImageSource.gallery,
      maxWidth: 2000,
      maxHeight: 2000,
      imageQuality: 85,
      requestFullMetadata: false,
    );
    if (file == null) return null;
    final bytes = await file.readAsBytes();
    final name = file.name.toLowerCase();
    final type =
        file.mimeType ??
        (name.endsWith('.png')
            ? 'image/png'
            : name.endsWith('.heic')
            ? 'image/heic'
            : name.endsWith('.webp')
            ? 'image/webp'
            : 'image/jpeg');
    return CapturedMedia(bytes: bytes, contentType: type, filename: file.name);
  }
}

/// A fresh recorder per sheet; the sheet disposes it.
final voiceRecorderProvider = Provider<VoiceRecorder Function()>((ref) => PluginVoiceRecorder.new);

final receiptPickerProvider = Provider<ReceiptPicker>((ref) => PluginReceiptPicker());
