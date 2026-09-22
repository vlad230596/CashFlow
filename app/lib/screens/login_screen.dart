import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../providers/data_provider.dart';
import 'widgets/browser_login_form.dart';
import 'widgets/versioned_app_bar_title.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _formKey = GlobalKey<FormState>();
  final _usernameController = TextEditingController();
  final _passwordController = TextEditingController();
  final _errorSummaryFocusNode = FocusNode();
  bool _submitting = false;
  bool _obscurePassword = true;
  String? _validationSummary;

  @override
  void dispose() {
    _usernameController.dispose();
    _passwordController.dispose();
    _errorSummaryFocusNode.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) {
      setState(() => _validationSummary = 'Проверьте логин и пароль');
      _errorSummaryFocusNode.requestFocus();
      return;
    }
    setState(() => _validationSummary = null);
    await _authenticate(
      _usernameController.text.trim(),
      _passwordController.text,
    );
  }

  Future<void> _authenticate(String username, String password) async {
    if (_submitting) return;
    setState(() {
      _submitting = true;
      _validationSummary = null;
    });
    final provider = context.read<DataProvider>();
    final loggedIn = await provider.login(username, password);
    if (loggedIn) TextInput.finishAutofillContext();
    if (mounted) setState(() => _submitting = false);
  }

  String _localizedAuthError(String error) {
    final normalized = error.toLowerCase();
    if (normalized.contains('invalid username or password') ||
        normalized.contains('unauthorized') ||
        normalized.contains('неверн')) {
      return 'Неверный логин или пароль';
    }
    if (normalized.contains('too many login attempts') ||
        normalized.contains('429') ||
        normalized.contains('слишком много')) {
      return 'Слишком много попыток. Повторите через 15 минут';
    }
    if (normalized.contains('сервер недоступен') ||
        normalized.contains('network') ||
        normalized.contains('socket')) {
      return 'Нет связи с сервером. Проверьте подключение и повторите попытку.';
    }
    return error;
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<DataProvider>();
    final authError = provider.authError == null
        ? null
        : _localizedAuthError(provider.authError!);
    final isOfflineError = authError?.startsWith('Нет связи') ?? false;

    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 440),
              child: Card(
                clipBehavior: Clip.antiAlias,
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Form(
                    key: _formKey,
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        ExcludeSemantics(
                          child: Icon(
                            Icons.account_balance_wallet_rounded,
                            size: 52,
                            color: Theme.of(context).colorScheme.primary,
                          ),
                        ),
                        const SizedBox(height: 12),
                        Text(
                          'CashFlow',
                          textAlign: TextAlign.center,
                          style: Theme.of(context).textTheme.headlineMedium,
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'Карты и кешбэк доступны только участникам с выданным доступом.',
                          textAlign: TextAlign.center,
                          style: Theme.of(context).textTheme.bodyMedium,
                        ),
                        if (_validationSummary != null) ...[
                          const SizedBox(height: 20),
                          _LoginErrorSummary(
                            message: _validationSummary!,
                            focusNode: _errorSummaryFocusNode,
                          ),
                        ],
                        if (authError != null) ...[
                          const SizedBox(height: 20),
                          _LoginErrorSummary(message: authError),
                        ],
                        const SizedBox(height: 24),
                        if (kIsWeb)
                          BrowserLoginForm(
                            submitting: _submitting,
                            onSubmit: _authenticate,
                          )
                        else
                          AutofillGroup(
                            child: Column(
                              children: [
                                TextFormField(
                                  controller: _usernameController,
                                  autofocus: true,
                                  enabled: !_submitting,
                                  autofillHints: const [AutofillHints.username],
                                  textInputAction: TextInputAction.next,
                                  autocorrect: false,
                                  decoration: const InputDecoration(
                                    labelText: 'Логин',
                                    border: OutlineInputBorder(),
                                  ),
                                  validator: (value) =>
                                      value == null || value.trim().isEmpty
                                          ? 'Введите логин'
                                          : null,
                                ),
                                const SizedBox(height: 16),
                                TextFormField(
                                  controller: _passwordController,
                                  enabled: !_submitting,
                                  obscureText: _obscurePassword,
                                  autofillHints: const [
                                    AutofillHints.password,
                                  ],
                                  textInputAction: TextInputAction.done,
                                  onFieldSubmitted: (_) {
                                    if (!_submitting) _submit();
                                  },
                                  decoration: InputDecoration(
                                    labelText: 'Пароль',
                                    border: const OutlineInputBorder(),
                                    suffixIcon: IconButton(
                                      tooltip: _obscurePassword
                                          ? 'Показать пароль'
                                          : 'Скрыть пароль',
                                      onPressed: _submitting
                                          ? null
                                          : () => setState(
                                                () => _obscurePassword =
                                                    !_obscurePassword,
                                              ),
                                      icon: Icon(
                                        _obscurePassword
                                            ? Icons.visibility_outlined
                                            : Icons.visibility_off_outlined,
                                      ),
                                    ),
                                  ),
                                  validator: (value) =>
                                      value == null || value.isEmpty
                                          ? 'Введите пароль'
                                          : null,
                                ),
                              ],
                            ),
                          ),
                        if (!kIsWeb) ...[
                          const SizedBox(height: 20),
                          FilledButton(
                            onPressed: _submitting ? null : _submit,
                            child: _submitting
                                ? const SizedBox.square(
                                    dimension: 20,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                    ),
                                  )
                                : Text(isOfflineError ? 'Повторить' : 'Войти'),
                          ),
                        ],
                        const SizedBox(height: 16),
                        Text(
                          'Доступ выдаёт администратор',
                          textAlign: TextAlign.center,
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                        const SizedBox(height: 8),
                        const AppVersionText(),
                        const SizedBox(height: 4),
                        ExpansionTile(
                          tilePadding: EdgeInsets.zero,
                          childrenPadding: const EdgeInsets.only(bottom: 8),
                          title: const Text('Технические детали'),
                          children: [
                            SelectableText(
                              provider.serverIp,
                              textAlign: TextAlign.center,
                              style: Theme.of(context).textTheme.bodySmall,
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _LoginErrorSummary extends StatelessWidget {
  const _LoginErrorSummary({required this.message, this.focusNode});

  final String message;
  final FocusNode? focusNode;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Semantics(
      liveRegion: true,
      container: true,
      child: Focus(
        focusNode: focusNode,
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: colors.errorContainer,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(Icons.error_outline, color: colors.onErrorContainer),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    message,
                    style: TextStyle(color: colors.onErrorContainer),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
