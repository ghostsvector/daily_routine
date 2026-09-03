import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show Clipboard, ClipboardData;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../../auth/providers/auth_providers.dart';
import '../data/murthy_crypto_service.dart';
import '../models/daily_progress_entry.dart';
import '../models/daily_protocol.dart';
import '../providers/murthy_providers.dart';

/// "Murthy" — today's progress, a daily summary note, and the recurring
/// daily protocols you're holding yourself to. Everything here is
/// encrypted client-side (see `MurthyCryptoService`) before it's written to
/// Firestore, so it stays unreadable to anyone but this device.
class MurthyScreen extends ConsumerWidget {
  const MurthyScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final (completed, total) = ref.watch(todayRoutineStatsProvider);
    final protocolsAsync = ref.watch(dailyProtocolsProvider);
    final progressAsync = ref.watch(todayProgressProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Murthy'),
        actions: [
          IconButton(
            icon: const Icon(Icons.lock_outline),
            tooltip: 'Encrypted on this device',
            onPressed: () => _showEncryptionInfo(context),
          ),
          PopupMenuButton<void>(
            itemBuilder: (context) => [
              PopupMenuItem(
                onTap: () => _confirmExportKey(context),
                child: const Text('Export encryption key…'),
              ),
            ],
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _ProgressCard(completed: completed, total: total),
          const SizedBox(height: 16),
          _SummaryCard(progressAsync: progressAsync),
          const SizedBox(height: 16),
          _ProtocolsSection(protocolsAsync: protocolsAsync),
        ],
      ),
    );
  }

  void _showEncryptionInfo(BuildContext context) {
    showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Encrypted on this device'),
        content: const Text(
          'Your daily summary and protocols are encrypted with a key that '
          'never leaves this device\'s secure storage. Firestore only ever '
          'stores ciphertext — the plaintext content is never public, even '
          'though this app\'s source code is.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Got it'),
          ),
        ],
      ),
    );
  }

  Future<void> _confirmExportKey(BuildContext context) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Export encryption key?'),
        content: const Text(
          'This reveals the raw key that decrypts every Murthy document in '
          'your Firestore project — treat it exactly like a password. Only '
          "do this to set up a tool you run yourself (e.g. a local MCP "
          "server for your own data analysis). Anyone who gets this key can "
          'read and forge all of your Murthy data.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Show key'),
          ),
        ],
      ),
    );
    if (confirmed != true || !context.mounted) return;

    final key = await MurthyCryptoService().exportKeyBase64();
    if (!context.mounted) return;
    showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Your Murthy encryption key'),
        content: SelectableText(key),
        actions: [
          TextButton(
            onPressed: () {
              Clipboard.setData(ClipboardData(text: key));
              Navigator.pop(context);
            },
            child: const Text('Copy & close'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }
}

class _ProgressCard extends StatelessWidget {
  const _ProgressCard({required this.completed, required this.total});

  final int completed;
  final int total;

  @override
  Widget build(BuildContext context) {
    final fraction = total == 0 ? 0.0 : completed / total;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Today\'s progress',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 12),
            LinearProgressIndicator(value: fraction, minHeight: 8),
            const SizedBox(height: 8),
            Text('$completed of $total tasks completed'),
          ],
        ),
      ),
    );
  }
}

class _SummaryCard extends ConsumerStatefulWidget {
  const _SummaryCard({required this.progressAsync});

  final AsyncValue<DailyProgressEntry> progressAsync;

  @override
  ConsumerState<_SummaryCard> createState() => _SummaryCardState();
}

class _SummaryCardState extends ConsumerState<_SummaryCard> {
  final _controller = TextEditingController();
  String? _loadedForDate;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final entry = widget.progressAsync.valueOrNull;
    if (entry != null && _loadedForDate != entry.date) {
      _controller.text = entry.summary;
      _loadedForDate = entry.date;
    }

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Daily summary',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _controller,
              maxLines: 4,
              decoration: const InputDecoration(
                border: OutlineInputBorder(),
                hintText: 'How did today go?',
              ),
            ),
            const SizedBox(height: 8),
            Align(
              alignment: Alignment.centerRight,
              child: FilledButton(
                onPressed: () => _save(entry),
                child: const Text('Save summary'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _save(DailyProgressEntry? entry) async {
    final user = ref.read(currentUserProvider);
    if (user.isEmpty) return;
    final base = entry ?? DailyProgressEntry(date: todayKey());
    final updated = base.copyWith(summary: _controller.text);
    await ref.read(murthyRepositoryProvider).upsertProgress(user.uid, updated);
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('Summary saved')));
  }
}

class _ProtocolsSection extends ConsumerWidget {
  const _ProtocolsSection({required this.protocolsAsync});

  final AsyncValue<List<DailyProtocol>> protocolsAsync;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Daily protocols',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                IconButton(
                  icon: const Icon(Icons.add),
                  tooltip: 'Add protocol',
                  onPressed: () => _showEditDialog(context, ref),
                ),
              ],
            ),
            protocolsAsync.when(
              data: (protocols) {
                if (protocols.isEmpty) {
                  return const Padding(
                    padding: EdgeInsets.symmetric(vertical: 12),
                    child: Text(
                      'No protocols yet — add one you want to hold yourself to daily.',
                    ),
                  );
                }
                return Column(
                  children: protocols
                      .map((p) => _ProtocolTile(protocol: p))
                      .toList(growable: false),
                );
              },
              loading: () => const Padding(
                padding: EdgeInsets.symmetric(vertical: 16),
                child: Center(child: CircularProgressIndicator()),
              ),
              error: (error, stack) => Padding(
                padding: const EdgeInsets.symmetric(vertical: 12),
                child: Text('Couldn\'t load protocols: $error'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  static void _showEditDialog(
    BuildContext context,
    WidgetRef ref, {
    DailyProtocol? existing,
  }) {
    final titleController = TextEditingController(text: existing?.title ?? '');
    final descController = TextEditingController(
      text: existing?.description ?? '',
    );
    showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(existing == null ? 'New protocol' : 'Edit protocol'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: titleController,
              decoration: const InputDecoration(labelText: 'Title'),
              autofocus: true,
            ),
            TextField(
              controller: descController,
              decoration: const InputDecoration(
                labelText: 'Description (optional)',
              ),
              maxLines: 2,
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () async {
              final user = ref.read(currentUserProvider);
              if (user.isEmpty || titleController.text.trim().isEmpty) return;
              final protocol = DailyProtocol(
                id: existing?.id ?? const Uuid().v4(),
                title: titleController.text.trim(),
                description: descController.text.trim(),
                isActive: existing?.isActive ?? true,
                createdAt: existing?.createdAt,
              );
              await ref
                  .read(murthyRepositoryProvider)
                  .upsertProtocol(user.uid, protocol);
              if (dialogContext.mounted) Navigator.pop(dialogContext);
            },
            child: const Text('Save'),
          ),
        ],
      ),
    );
  }
}

class _ProtocolTile extends ConsumerWidget {
  const _ProtocolTile({required this.protocol});

  final DailyProtocol protocol;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: Checkbox(
        value: protocol.isActive,
        onChanged: (value) {
          final user = ref.read(currentUserProvider);
          if (user.isEmpty || value == null) return;
          ref
              .read(murthyRepositoryProvider)
              .upsertProtocol(user.uid, protocol.copyWith(isActive: value));
        },
      ),
      title: Text(protocol.title),
      subtitle: protocol.description.isEmpty
          ? null
          : Text(protocol.description),
      trailing: IconButton(
        icon: const Icon(Icons.delete_outline),
        tooltip: 'Delete',
        onPressed: () {
          final user = ref.read(currentUserProvider);
          if (user.isEmpty) return;
          ref
              .read(murthyRepositoryProvider)
              .deleteProtocol(user.uid, protocol.id);
        },
      ),
      onTap: () =>
          _ProtocolsSection._showEditDialog(context, ref, existing: protocol),
    );
  }
}
