import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers/murthy_assistant_providers.dart';

/// "Ask Murthy" — type a topic you've forgotten, get it explained and
/// spoken aloud. Android runs its own on-device model/voice; Linux desktop
/// needs a local `murthy-voice` clone configured via `MurthyAssistantConfig`
/// (see its doc comment). Only rendered where one of those is available
/// (see [murthyAssistantAvailableProvider]) — no iOS/macOS/Windows path yet.
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

  @override
  void dispose() {
    _controller.dispose();
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
            Text('Ask Murthy', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 4),
            Text(
              'Type a topic you\'ve forgotten — Murthy explains it and reads '
              'the explanation aloud.',
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
                onPressed: _busy ? null : _ask,
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

  Future<void> _ask() async {
    final topic = _controller.text.trim();
    if (topic.isEmpty) return;

    setState(() {
      _busy = true;
      _error = null;
      _answer = null;
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
