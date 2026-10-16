import 'package:flutter/material.dart';

/// Back dismisses a visible IME before changing navigation state.
/// Focus alone is not enough: Android can keep a field focused after hiding IME.
bool dismissKeyboardIfVisible(BuildContext context) {
  if (View.of(context).viewInsets.bottom <= 0) return false;
  FocusScope.of(context).unfocus();
  return true;
}

/// Keeps the route (and any PopScope guards) intact on the first Back with IME.
class KeyboardFirstBackButton extends StatelessWidget {
  const KeyboardFirstBackButton({super.key});

  @override
  Widget build(BuildContext context) => BackButton(
        onPressed: () {
          if (!dismissKeyboardIfVisible(context)) Navigator.maybePop(context);
        },
      );
}
