import 'package:flutter/material.dart';
import '../theme/app_theme.dart';

/// A TextField for passwords/PINs with a show/hide (eye) icon in the
/// suffix, so the person can reveal what they typed to check it before
/// submitting. Used everywhere a password or 4-digit PIN is entered
/// (auth flow, wallet/checkout password-confirm dialogs).
class PasswordField extends StatefulWidget {
  final TextEditingController controller;
  final String labelText;
  final FloatingLabelBehavior? floatingLabelBehavior;
  final int? maxLength;
  final bool autofocus;
  final bool enabled;
  final String? counterText;
  final ValueChanged<String>? onChanged;

  const PasswordField({
    super.key,
    required this.controller,
    required this.labelText,
    this.floatingLabelBehavior,
    this.maxLength = 4,
    this.autofocus = false,
    this.enabled = true,
    this.counterText,
    this.onChanged,
  });

  @override
  State<PasswordField> createState() => _PasswordFieldState();
}

class _PasswordFieldState extends State<PasswordField> {
  bool _obscure = true;

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: widget.controller,
      keyboardType: TextInputType.number,
      maxLength: widget.maxLength,
      obscureText: _obscure,
      autofocus: widget.autofocus,
      enabled: widget.enabled,
      onChanged: widget.onChanged,
      decoration: InputDecoration(
        labelText: widget.labelText,
        floatingLabelBehavior: widget.floatingLabelBehavior,
        counterText: widget.counterText,
        border: const OutlineInputBorder(),
        suffixIcon: IconButton(
          icon: Icon(
            _obscure ? Icons.visibility_off : Icons.visibility,
            color: AppTheme.textMuted(context),
            size: 20,
          ),
          onPressed: () => setState(() => _obscure = !_obscure),
        ),
      ),
    );
  }
}
