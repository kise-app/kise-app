/// Change the account password: the current one, the new one, and the new one again.
///
/// The server checks the current password (a wrong one comes back as `current_password_incorrect`
/// and is shown under that field) and refuses a new password equal to the old. Tokens already issued
/// stay valid, so this device stays signed in.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../platform/api/api.dart';
import '../../../platform/settings.dart';

class ChangePasswordDialog extends ConsumerStatefulWidget {
  const ChangePasswordDialog({super.key});

  @override
  ConsumerState<ChangePasswordDialog> createState() => _ChangePasswordDialogState();
}

class _ChangePasswordDialogState extends ConsumerState<ChangePasswordDialog> {
  final _formKey = GlobalKey<FormState>();
  final _current = TextEditingController();
  final _next = TextEditingController();
  final _confirm = TextEditingController();
  bool _saving = false;
  String? _currentError;
  String? _error;

  @override
  void dispose() {
    _current.dispose();
    _next.dispose();
    _confirm.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    setState(() {
      _currentError = null;
      _error = null;
    });
    if (!_formKey.currentState!.validate()) return;
    final settings = ref.read(settingsProvider);
    setState(() => _saving = true);
    try {
      await ref
          .read(authApiProvider)
          .changePassword(currentPassword: _current.text, newPassword: _next.text);
      if (!mounted) return;
      final messenger = ScaffoldMessenger.maybeOf(context);
      Navigator.of(context).pop();
      messenger?.showSnackBar(
        SnackBar(content: Text(settings.say('የይለፍ ቃል ተቀይሯል', 'Password changed'))),
      );
    } on ApiException catch (error) {
      setState(() {
        if (error.code == 'current_password_incorrect') {
          _currentError = settings.say(
            'የአሁኑ የይለፍ ቃል ትክክል አይደለም',
            'That is not your current password',
          );
        } else {
          _error = error.message;
        }
      });
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final settings = ref.watch(settingsProvider);
    final theme = Theme.of(context);
    return AlertDialog(
      title: Text(settings.say('የይለፍ ቃል ቀይር', 'Change password')),
      content: Form(
        key: _formKey,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextFormField(
                key: const Key('password-current'),
                controller: _current,
                obscureText: true,
                autofillHints: const [AutofillHints.password],
                decoration: InputDecoration(
                  labelText: settings.say('የአሁኑ የይለፍ ቃል', 'Current password'),
                  errorText: _currentError,
                ),
                validator: (v) =>
                    (v == null || v.isEmpty) ? settings.say('ያስፈልጋል', 'Required') : null,
              ),
              const SizedBox(height: 12),
              TextFormField(
                key: const Key('password-new'),
                controller: _next,
                obscureText: true,
                autofillHints: const [AutofillHints.newPassword],
                decoration: InputDecoration(labelText: settings.say('አዲስ የይለፍ ቃል', 'New password')),
                validator: (v) => (v == null || v.length < 8)
                    ? settings.say('ቢያንስ 8 ፊደላት', 'At least 8 characters')
                    : null,
              ),
              const SizedBox(height: 12),
              TextFormField(
                key: const Key('password-confirm'),
                controller: _confirm,
                obscureText: true,
                decoration: InputDecoration(
                  labelText: settings.say('አዲሱን ይድገሙ', 'Repeat the new password'),
                ),
                validator: (v) =>
                    v != _next.text ? settings.say('አይመሳሰሉም', 'The passwords do not match') : null,
                onFieldSubmitted: (_) => _submit(),
              ),
              if (_error != null) ...[
                const SizedBox(height: 12),
                Text(_error!, style: TextStyle(color: theme.colorScheme.error)),
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _saving ? null : () => Navigator.of(context).pop(),
          child: Text(settings.say('ተመለስ', 'Cancel')),
        ),
        FilledButton(
          key: const Key('password-submit'),
          style: FilledButton.styleFrom(minimumSize: const Size(0, 44)),
          onPressed: _saving ? null : _submit,
          child: _saving
              ? const SizedBox.square(
                  dimension: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : Text(settings.say('ቀይር', 'Change')),
        ),
      ],
    );
  }
}
