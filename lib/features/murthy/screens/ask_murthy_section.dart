import 'dart:async';

import 'package:daily_routine_sdk/daily_routine_sdk.dart' show QueryTranscribed, WakeDetected, WakeWordError;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers/murthy_assistant_providers.dart';

/// "Ask Murthy" — type a topic you've forgotten (or say "Hey Murthy" and
/// then the topic), get it explained and spoken aloud. Android runs its
/// own on-device model/voice; Linux desktop needs a local `murthy-voice`
/// clone configured via `MurthyAssistantConfig` (see its doc comment).
/// Only rendered where one of those is available (see
/// [murthyAssistantAvailableProvider]) — no iOS/macOS/Windows path yet.
class AskMurthySection extends ConsumerStatefulWidget {
  const AskMurthySection({super.key});

  @override
  ConsumerState<AskMurthySection> createState() => _AskMurthySectionState();
}

class _AskMurthySectionState extends ConsumerState<AskMurthySection> {
  final _controller = TextEditingController();
  String? _answer;
  String? _error;
  bool _busy = false;

  bool _listening = false;
  bool _heardWake = false;
  StreamSubscription<Object>? _wakeSubscription;

  @override
  void dispose() {
    _controller.dispose();
    unawaited(_wakeSubscription?.cancel());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('Ask Murthy', style: Theme.of(context).textTheme.titleMedium),
                IconButton(
                  icon: Icon(_listening ? Icons.mic : Icons.mic_none),
                  tooltip: _listening ? 'Stop listening for "Hey Murthy"' : 'Listen for "Hey Murthy"',
                  color: _listening ? Theme.of(context).colorScheme.primary : null,
                  onPressed: _toggleListening,
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              _listening
                  ? (_heardWake
                        ? 'Heard "Hey Murthy" — go ahead, ask your question…'
                        : 'Listening for "Hey Murthy"…')
                  : 'Type a topic you\'ve forgotten, or tap the mic and say '
                        '"Hey Murthy" — Murthy explains it and reads the '
                        'explanation aloud.',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _controller,
              maxLines: 2,
              enabled: !_busy,
              decoration: const InputDecoration(
                border: OutlineInputBorder(),
                hintText: 'e.g. what is a transformer neural network',
              ),
            ),
            const SizedBox(height: 8),
            Align(
              alignment: Alignment.centerRight,
              child: FilledButton(
                onPressed: _busy ? null : () => _ask(_controller.text),
                child: _busy
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Text('Explain'),
              ),
            ),
            if (_error != null) ...[
              const SizedBox(height: 8),
              Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
            ],
            if (_answer != null) ...[
              const SizedBox(height: 8),
              Text(_answer!),
            ],
          ],
        ),
      ),
    );
  }

  void _toggleListening() {
    final wakeWord = ref.read(wakeWordServiceProvider);
    if (_listening) {
      unawaited(_wakeSubscription?.cancel());
      _wakeSubscription = null;
      unawaited(wakeWord.stop());
      setState(() {
        _listening = false;
        _heardWake = false;
      });
      return;
    }

    _wakeSubscription = wakeWord.events.listen((event) {
      if (!mounted) return;
      switch (event) {
        case WakeDetected():
          setState(() => _heardWake = true);
        case QueryTranscribed(:final text):
          setState(() => _heardWake = false);
          unawaited(_ask(text));
        case WakeWordError(:final message):
          setState(() {
            _heardWake = false;
            _error = message;
          });
      }
    });
    unawaited(wakeWord.start());
    setState(() {
      _listening = true;
      _heardWake = false;
      _error = null;
    });
  }

  Future<void> _ask(String rawTopic) async {
    final topic = rawTopic.trim();
    if (topic.isEmpty) return;

    setState(() {
      _busy = true;
      _error = null;
      _answer = null;
      _controller.text = topic;
    });

    final assistant = ref.read(assistantServiceProvider);
    final explainResult = await assistant.explain(topic);

    await explainResult.fold(
      (text) async {
        if (!mounted) return;
        setState(() => _answer = text);
        final voice = ref.read(voiceServiceProvider);
        final speakResult = await voice.speak(
          text,
          languageCode: detectSpokenLanguage(text),
        );
        if (!mounted) return;
        speakResult.fold((_) {}, (error) => setState(() => _error = error.message));
      },
      (error) async {
        if (!mounted) return;
        setState(() => _error = error.message);
      },
    );

    if (mounted) setState(() => _busy = false);
  }
}
