import 'dart:typed_data';

import 'package:flutter/services.dart' show rootBundle;
import 'package:onnxruntime/onnxruntime.dart';

/// Loads the three ONNX models "Hey Murthy" needs — see
/// `assets/murthy/onnx/README.md` for where they come from. None of them
/// can be produced by this codebase (two are generic openWakeWord release
/// assets, one is a custom-trained classifier), so this resolves what's
/// actually bundled and reports plainly when it isn't, rather than
/// pretending the feature works.
class MurthyWakewordModels {
  MurthyWakewordModels._({
    required this.melspectrogram,
    required this.embedding,
    required this.wakeword,
  });

  final OrtSession melspectrogram;
  final OrtSession embedding;
  final OrtSession wakeword;

  static const _melspecAsset = 'assets/murthy/onnx/melspectrogram.onnx';
  static const _embeddingAsset = 'assets/murthy/onnx/embedding_model.onnx';
  static const _wakewordAsset = 'assets/murthy/onnx/hey_murthy.onnx';

  /// Loads all three models, or returns `null` if any asset is missing.
  static Future<MurthyWakewordModels?> loadIfAvailable() async {
    final melspecBytes = await _tryLoadAsset(_melspecAsset);
    final embeddingBytes = await _tryLoadAsset(_embeddingAsset);
    final wakewordBytes = await _tryLoadAsset(_wakewordAsset);
    if (melspecBytes == null ||
        embeddingBytes == null ||
        wakewordBytes == null) {
      return null;
    }

    OrtEnv.instance.init();
    final options = OrtSessionOptions();
    return MurthyWakewordModels._(
      melspectrogram: OrtSession.fromBuffer(melspecBytes, options),
      embedding: OrtSession.fromBuffer(embeddingBytes, options),
      wakeword: OrtSession.fromBuffer(wakewordBytes, options),
    );
  }

  static Future<Uint8List?> _tryLoadAsset(String path) async {
    try {
      final data = await rootBundle.load(path);
      return data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes);
    } catch (_) {
      return null;
    }
  }

  void release() {
    melspectrogram.release();
    embedding.release();
    wakeword.release();
    OrtEnv.instance.release();
  }
}
