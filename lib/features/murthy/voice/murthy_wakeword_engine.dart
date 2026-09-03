import 'dart:typed_data';

import 'package:onnxruntime/onnxruntime.dart';

import 'murthy_wakeword_models.dart';

/// Re-implements openWakeWord's streaming preprocessing/inference pipeline
/// (see https://github.com/dscripka/openWakeWord) against three ONNX
/// models: raw audio → mel-spectrogram → speech embedding → wake-word
/// score. The exact chunk sizes, window sizes, and scaling below are taken
/// from openWakeWord's own source (`openwakeword/utils.py`,
/// `AudioFeatures._streaming_melspectrogram` / `_get_melspectrogram`, and
/// `openwakeword/model.py`'s prediction loop) — this is a port of that
/// math, not an independent design.
///
/// Input must be mono 16kHz PCM16 samples, fed via [pushAudio] in whatever
/// chunk sizes the microphone delivers — internally accumulated and
/// processed in fixed 1280-sample (80ms) steps.
class MurthyWakewordEngine {
  MurthyWakewordEngine(this._models, {this.detectionThreshold = 0.5});

  final MurthyWakewordModels _models;
  final double detectionThreshold;

  static const _chunkSamples = 1280;
  // Left-context fed to the melspec model alongside each new chunk, so its
  // STFT window has enough history at the boundary (openWakeWord uses
  // 160 * 3 samples here).
  static const _contextSamples = 480;
  static const _minSamplesForMelspec = 400;
  static const _melBins = 32;
  static const _embeddingWindowFrames = 76;
  // openWakeWord's default custom-model training config uses a 16-embedding
  // input sequence; the ONNX Runtime Dart binding doesn't expose a model's
  // declared input shape ahead of a run, so this can't be read back from
  // hey_murthy.onnx itself — if a model trained with a different sequence
  // length is dropped in, detection will silently never fire, since the
  // input tensor shape would then mismatch what that model expects.
  static const _embeddingSequenceLength = 16;
  static const _maxMelFrames = 200;
  static const _maxEmbeddings = 120;

  final List<double> _rawAudio = <double>[];
  int _consumedSamples = 0;
  final List<List<double>> _melFrames = <List<double>>[];
  final List<List<double>> _embeddings = <List<double>>[];
  bool _busy = false;

  /// Feeds newly captured audio. Returns the wake-word score for each 80ms
  /// chunk that completed as a result (usually 0 or 1 entries) — compare
  /// against [detectionThreshold] to decide whether it's a wake.
  Future<List<double>> pushAudio(Int16List samples) async {
    if (_busy) return const [];
    _busy = true;
    try {
      _rawAudio.addAll(samples.map((s) => s.toDouble()));
      const maxRawSamples = 16000 * 4;
      if (_rawAudio.length > maxRawSamples) {
        final drop = _rawAudio.length - maxRawSamples;
        _rawAudio.removeRange(0, drop);
        _consumedSamples -= drop;
      }

      final scores = <double>[];
      while (_rawAudio.length - _consumedSamples >= _chunkSamples) {
        _consumedSamples += _chunkSamples;
        final score = await _processChunk();
        if (score != null) scores.add(score);
      }
      return scores;
    } finally {
      _busy = false;
    }
  }

  Future<double?> _processChunk() async {
    final end = _consumedSamples;
    final start = (end - _chunkSamples - _contextSamples).clamp(0, end);
    final slice = _rawAudio.sublist(start, end);
    if (slice.length < _minSamplesForMelspec) return null;

    final newFrames = await _runMelspectrogram(slice);
    _melFrames.addAll(newFrames);
    if (_melFrames.length > _maxMelFrames) {
      _melFrames.removeRange(0, _melFrames.length - _maxMelFrames);
    }
    if (_melFrames.length < _embeddingWindowFrames) return null;

    final window = _melFrames.sublist(
      _melFrames.length - _embeddingWindowFrames,
    );
    final embedding = await _runEmbedding(window);
    _embeddings.add(embedding);
    if (_embeddings.length > _maxEmbeddings) {
      _embeddings.removeRange(0, _embeddings.length - _maxEmbeddings);
    }
    if (_embeddings.length < _embeddingSequenceLength) return null;

    final sequence = _embeddings.sublist(
      _embeddings.length - _embeddingSequenceLength,
    );
    return _runWakeword(sequence);
  }

  Future<List<List<double>>> _runMelspectrogram(List<double> rawSamples) async {
    final input = OrtValueTensor.createTensorWithDataList(
      Float32List.fromList(rawSamples),
      [1, rawSamples.length],
    );
    final runOptions = OrtRunOptions();
    final outputs = await _models.melspectrogram.runAsync(runOptions, {
      _models.melspectrogram.inputNames.first: input,
    });
    input.release();
    runOptions.release();

    final flat = _flatten(outputs?.first?.value);
    for (final o in outputs ?? const []) {
      o?.release();
    }
    // openWakeWord: melspec_transform(x) = x/10 + 2, applied to the raw
    // model output before it's used anywhere else.
    final transformed = flat.map((v) => v / 10 + 2).toList();
    return _chunked(transformed, _melBins);
  }

  Future<List<double>> _runEmbedding(List<List<double>> window) async {
    final flatWindow = <double>[for (final frame in window) ...frame];
    final input = OrtValueTensor.createTensorWithDataList(
      Float32List.fromList(flatWindow),
      [1, _embeddingWindowFrames, _melBins, 1],
    );
    final runOptions = OrtRunOptions();
    final outputs = await _models.embedding.runAsync(runOptions, {
      _models.embedding.inputNames.first: input,
    });
    input.release();
    runOptions.release();

    final flat = _flatten(outputs?.first?.value);
    for (final o in outputs ?? const []) {
      o?.release();
    }
    return flat;
  }

  Future<double> _runWakeword(List<List<double>> sequence) async {
    final flatSequence = <double>[
      for (final embedding in sequence) ...embedding,
    ];
    final input = OrtValueTensor.createTensorWithDataList(
      Float32List.fromList(flatSequence),
      [1, _embeddingSequenceLength, sequence.first.length],
    );
    final runOptions = OrtRunOptions();
    final outputs = await _models.wakeword.runAsync(runOptions, {
      _models.wakeword.inputNames.first: input,
    });
    input.release();
    runOptions.release();

    final flat = _flatten(outputs?.first?.value);
    for (final o in outputs ?? const []) {
      o?.release();
    }
    // Standard custom openWakeWord models export a single detection score;
    // if a multi-class model is ever dropped in instead, this takes its
    // last output value rather than failing outright.
    return flat.isEmpty ? 0.0 : flat.last;
  }

  static List<double> _flatten(dynamic nested) {
    final out = <double>[];
    void visit(dynamic node) {
      if (node is List) {
        for (final child in node) {
          visit(child);
        }
      } else if (node is num) {
        out.add(node.toDouble());
      }
    }

    visit(nested);
    return out;
  }

  static List<List<double>> _chunked(List<double> flat, int rowLength) {
    final rows = <List<double>>[];
    for (var i = 0; i + rowLength <= flat.length; i += rowLength) {
      rows.add(flat.sublist(i, i + rowLength));
    }
    return rows;
  }
}
