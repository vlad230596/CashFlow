import 'package:flutter/widgets.dart';

class BrowserLoginForm extends StatelessWidget {
  const BrowserLoginForm({
    super.key,
    required this.submitting,
    required this.onSubmit,
  });

  final bool submitting;
  final Future<void> Function(String username, String password) onSubmit;

  @override
  Widget build(BuildContext context) => const SizedBox.shrink();
}
