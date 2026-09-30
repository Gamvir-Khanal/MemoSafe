import 'package:flutter/material.dart';

import 'biometric_service.dart';
import 'db_helper.dart';
import 'firestore_service.dart';
import 'note_card.dart';
import 'note_detail_page.dart';
import 'note_type.dart';
import 'pin_entry_dialog.dart';
import 'pin_service.dart';

/// Shown when the user taps "Vault" in the side menu.
/// Handles first-time PIN setup and PIN verification, then hands off
/// to [VaultContentPage] once unlocked.
class VaultGatePage extends StatefulWidget {
  const VaultGatePage({super.key});

  @override
  State<VaultGatePage> createState() => _VaultGatePageState();
}

class _VaultGatePageState extends State<VaultGatePage> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _handleAccess());
  }

  Future<void> _handleAccess() async {
    final isSet = await PinService.isPinSet();
    if (!mounted) return;

    if (!isSet) {
      await _setupNewPin();
    } else {
      await _verifyExistingPin();
    }
  }

  Future<void> _setupNewPin() async {
    final pin1 = await promptForPin(
      context,
      title: 'Create a Vault PIN',
      subtitle: 'Choose a 4-digit PIN to protect your Vault',
    );
    if (pin1 == null) {
      if (mounted) Navigator.of(context).pop();
      return;
    }
    if (!mounted) return;
    final pin2 = await promptForPin(context, title: 'Confirm your PIN');
    if (pin2 == null) {
      if (mounted) Navigator.of(context).pop();
      return;
    }
    if (pin1 != pin2) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('PINs did not match. Try again.')),
        );
      }
      return _setupNewPin();
    }
    await PinService.setPin(pin1);
    _enterVault();
  }

  Future<void> _verifyExistingPin() async {
    if (await _tryBiometricUnlock()) {
      _enterVault();
      return;
    }
    if (!mounted) return;

    final pin = await promptForPin(
      context,
      title: 'Enter Vault PIN',
      onForgotPin: _handleForgotPin,
    );
    if (pin == null) {
      if (mounted) Navigator.of(context).pop();
      return;
    }
    final ok = await PinService.verifyPin(pin);
    if (ok) {
      _enterVault();
    } else {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Incorrect PIN. Try again.')),
        );
      }
      return _verifyExistingPin();
    }
  }

  /// Attempts biometric unlock if the device supports it and the user
  /// hasn't turned it off. Returns false (never throws) for any reason —
  /// unavailable hardware, disabled preference, cancelled prompt, failed
  /// match — and the caller falls through to the PIN dialog as normal.
  Future<bool> _tryBiometricUnlock() async {
    final enabled = await BiometricService.isEnabled();
    if (!enabled) return false;
    final available = await BiometricService.isAvailable();
    if (!available) return false;
    return BiometricService.authenticate();
  }

  /// Confirms with the user, then permanently deletes every note currently
  /// in the Vault and clears the stored PIN. Returns `true` only if the
  /// reset actually happened (so the PIN dialog knows to close itself);
  /// returns `false` if the user backed out of the confirmation.
  ///
  /// There is deliberately no "recover the PIN" path — a forgotten PIN
  /// can only be resolved by wiping the Vault's contents, since the PIN
  /// is stored only as a one-way hash and the notes aren't recoverable
  /// without it.
  Future<bool> _handleForgotPin() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Reset Vault?'),
        content: const Text(
          'Forgetting your PIN means the notes inside the Vault can\'t be '
          'recovered. Continuing will permanently delete every note '
          'currently in the Vault and let you set a new PIN. This cannot '
          'be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(context).colorScheme.error,
              foregroundColor: Theme.of(context).colorScheme.onError,
            ),
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Delete Vault & Reset'),
          ),
        ],
      ),
    );

    if (confirmed != true) return false;

    final vaultNotes = await DBHelper.instance.getNotesByStatus(
      NoteStatus.vault,
    );
    for (final note in vaultNotes) {
      if (note.sNo != null) {
        await DBHelper.instance.deleteNote(note.sNo!);
        await FirestoreService.instance.deleteNote(note.sNo!);
      }
    }
    await PinService.resetPin();

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Vault reset. All Vault notes were deleted — set a new PIN '
            'next time you open it.',
          ),
        ),
      );
    }
    return true;
  }

  void _enterVault() {
    if (!mounted) return;
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(builder: (_) => const VaultContentPage()),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Vault')),
      body: const Center(child: CircularProgressIndicator()),
    );
  }
}

/// The actual vault contents, only reachable after PIN verification.
class VaultContentPage extends StatefulWidget {
  const VaultContentPage({super.key});

  @override
  State<VaultContentPage> createState() => _VaultContentPageState();
}

class _VaultContentPageState extends State<VaultContentPage> {
  List<NoteModel> _notes = [];
  bool _loading = true;

  bool _biometricAvailable = false;
  bool _biometricEnabled = true;

  @override
  void initState() {
    super.initState();
    _load();
    _loadBiometricPref();
  }

  Future<void> _loadBiometricPref() async {
    final available = await BiometricService.isAvailable();
    final enabled = await BiometricService.isEnabled();
    if (!mounted) return;
    setState(() {
      _biometricAvailable = available;
      _biometricEnabled = enabled;
    });
  }

  Future<void> _toggleBiometric() async {
    final next = !_biometricEnabled;
    await BiometricService.setEnabled(next);
    if (!mounted) return;
    setState(() => _biometricEnabled = next);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          next
              ? 'Biometric unlock enabled.'
              : 'Biometric unlock disabled — PIN only.',
        ),
      ),
    );
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final notes = await DBHelper.instance.getNotesByStatus(NoteStatus.vault);
    setState(() {
      _notes = notes;
      _loading = false;
    });
  }

  Future<void> _deleteNote(int sNo) async {
    await DBHelper.instance.deleteNote(sNo);
    await FirestoreService.instance.deleteNote(sNo);
    _load();
  }

  Future<void> _togglePin(NoteModel note) async {
    await DBHelper.instance.updatePinned(note.sNo!, !note.isPinned);
    _load();
  }

  Future<void> _openNote(NoteModel note) async {
    await Navigator.of(
      context,
    ).push(MaterialPageRoute(builder: (_) => NoteDetailPage(note: note)));
    _load();
  }

  Future<void> _changePin() async {
    final oldPin = await promptForPin(context, title: 'Enter current PIN');
    if (oldPin == null) return;
    if (!mounted) return;
    final newPin1 = await promptForPin(context, title: 'Enter new PIN');
    if (newPin1 == null) return;
    if (!mounted) return;
    final newPin2 = await promptForPin(context, title: 'Confirm new PIN');
    if (newPin2 == null) return;

    if (newPin1 != newPin2) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('New PINs did not match.')),
        );
      }
      return;
    }

    final ok = await PinService.changePin(oldPin, newPin1);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(ok ? 'PIN updated.' : 'Current PIN was incorrect.'),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        centerTitle: true,
        title: const Text('Vault'),
        actions: [
          if (_biometricAvailable)
            IconButton(
              icon: Icon(
                Icons.fingerprint,
                color: _biometricEnabled
                    ? Theme.of(context).colorScheme.primary
                    : Theme.of(context).disabledColor,
              ),
              tooltip: _biometricEnabled
                  ? 'Biometric unlock is on — tap to disable'
                  : 'Biometric unlock is off — tap to enable',
              onPressed: _toggleBiometric,
            ),
          IconButton(
            icon: const Icon(Icons.password_rounded),
            tooltip: 'Change PIN',
            onPressed: _changePin,
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _notes.isEmpty
          ? const Center(child: Text('Vault is empty.'))
          : RefreshIndicator(
              onRefresh: _load,
              child: ListView.builder(
                padding: const EdgeInsets.symmetric(vertical: 8),
                itemCount: _notes.length,
                itemBuilder: (context, index) {
                  final note = _notes[index];
                  return NoteCard(
                    note: note,
                    colorIndex: index,
                    onTap: () => _openNote(note),
                    onDelete: () => _deleteNote(note.sNo!),
                    onTogglePin: () => _togglePin(note),
                  );
                },
              ),
            ),
    );
  }
}
