import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Shows a modal dialog asking the user to type a 4-digit PIN.
/// Returns the entered 4-digit string, or null if the user cancelled.
///
/// If [onForgotPin] is provided, a "Forgot PIN?" link is shown below the
/// field. It should show its own confirmation flow and return `true` only
/// if the PIN was actually reset (e.g. after wiping the Vault) — in that
/// case this dialog closes itself and resolves with `null`, same as a
/// cancel, so the caller can route back out normally.
Future<String?> promptForPin(
  BuildContext context, {
  required String title,
  String? subtitle,
  Future<bool> Function()? onForgotPin,
}) {
  return showDialog<String>(
    context: context,
    builder: (context) =>
        _PinDialog(title: title, subtitle: subtitle, onForgotPin: onForgotPin),
  );
}

class _PinDialog extends StatefulWidget {
  final String title;
  final String? subtitle;
  final Future<bool> Function()? onForgotPin;
  const _PinDialog({required this.title, this.subtitle, this.onForgotPin});

  @override
  State<_PinDialog> createState() => _PinDialogState();
}

class _PinDialogState extends State<_PinDialog> {
  final _controller = TextEditingController();
  String? _error;
  bool _handlingForgotPin = false;

  void _submit() {
    final value = _controller.text.trim();
    if (value.length != 4) {
      setState(() => _error = 'Enter all 4 digits');
      return;
    }
    Navigator.of(context).pop(value);
  }

  Future<void> _handleForgotPin() async {
    final callback = widget.onForgotPin;
    if (callback == null || _handlingForgotPin) return;
    setState(() => _handlingForgotPin = true);
    final resetHappened = await callback();
    if (!mounted) return;
    if (resetHappened) {
      // Vault was wiped and PIN cleared — close this dialog as if
      // cancelled so the caller routes back out (e.g. to Home).
      Navigator.of(context).pop(null);
    } else {
      setState(() => _handlingForgotPin = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.title),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (widget.subtitle != null) ...[
            Text(
              widget.subtitle!,
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: 12),
          ],
          TextField(
            controller: _controller,
            autofocus: true,
            keyboardType: TextInputType.number,
            obscureText: true,
            maxLength: 4,
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 24, letterSpacing: 12),
            inputFormatters: [
              FilteringTextInputFormatter.digitsOnly,
              LengthLimitingTextInputFormatter(4),
            ],
            decoration: InputDecoration(
              counterText: '',
              errorText: _error,
              border: const OutlineInputBorder(),
            ),
            onSubmitted: (_) => _submit(),
          ),
          if (widget.onForgotPin != null)
            Align(
              alignment: Alignment.centerRight,
              child: TextButton(
                onPressed: _handlingForgotPin ? null : _handleForgotPin,
                child: _handlingForgotPin
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Text('Forgot PIN?'),
              ),
            ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(null),
          child: const Text('Cancel'),
        ),
        FilledButton(onPressed: _submit, child: const Text('Confirm')),
      ],
    );
  }
}
