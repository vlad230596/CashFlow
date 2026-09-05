import 'dart:js_interop';

import 'package:flutter/widgets.dart';
import 'package:web/web.dart' as web;

class BrowserLoginForm extends StatefulWidget {
  const BrowserLoginForm({
    super.key,
    required this.submitting,
    required this.onSubmit,
  });

  final bool submitting;
  final Future<void> Function(String username, String password) onSubmit;

  @override
  State<BrowserLoginForm> createState() => _BrowserLoginFormState();
}

class _BrowserLoginFormState extends State<BrowserLoginForm> {
  late final web.HTMLFormElement _form;
  late final web.HTMLInputElement _username;
  late final web.HTMLInputElement _password;
  late final web.HTMLButtonElement _passwordVisibility;
  late final web.HTMLButtonElement _submitButton;
  late final JSExportedDartFunction _submitListener;
  late final JSExportedDartFunction _visibilityListener;

  @override
  void initState() {
    super.initState();

    _form = web.HTMLFormElement()
      ..id = 'cashflow-login-form'
      ..name = 'login'
      ..autocomplete = 'on'
      ..className = 'cashflow-native-login';
    _username = web.HTMLInputElement()
      ..id = 'cashflow-username'
      ..name = 'username'
      ..type = 'text'
      ..autocomplete = 'username'
      ..placeholder = 'Логин'
      ..required = true
      ..autocapitalize = 'none'
      ..spellcheck = false
      ..className = 'cashflow-native-input'
      ..setAttribute('aria-label', 'Логин');
    _password = web.HTMLInputElement()
      ..id = 'cashflow-password'
      ..name = 'password'
      ..type = 'password'
      ..autocomplete = 'current-password'
      ..placeholder = 'Пароль'
      ..required = true
      ..className = 'cashflow-native-input cashflow-password-input'
      ..setAttribute('aria-label', 'Пароль');
    _passwordVisibility = web.HTMLButtonElement()
      ..type = 'button'
      ..className = 'cashflow-password-visibility'
      ..textContent = 'Показать'
      ..setAttribute('aria-label', 'Показать пароль');
    _submitButton = web.HTMLButtonElement()
      ..type = 'submit'
      ..className = 'cashflow-native-submit';

    final passwordContainer = web.HTMLDivElement()
      ..className = 'cashflow-password-container';
    passwordContainer.append(_password);
    passwordContainer.append(_passwordVisibility);
    _form.append(_username);
    _form.append(passwordContainer);
    _form.append(_submitButton);

    _submitListener = ((web.Event event) {
      event.preventDefault();
      if (widget.submitting || !_form.reportValidity()) return;
      widget.onSubmit(_username.value.trim(), _password.value);
    }).toJS;
    _visibilityListener = ((web.Event event) {
      event.preventDefault();
      final showPassword = _password.type == 'password';
      _password.type = showPassword ? 'text' : 'password';
      _passwordVisibility.textContent = showPassword ? 'Скрыть' : 'Показать';
      _passwordVisibility.setAttribute(
        'aria-label',
        showPassword ? 'Скрыть пароль' : 'Показать пароль',
      );
    }).toJS;
    _form.addEventListener('submit', _submitListener);
    _passwordVisibility.addEventListener('click', _visibilityListener);
    _updateSubmittingState();
  }

  @override
  void didUpdateWidget(BrowserLoginForm oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.submitting != widget.submitting) {
      _updateSubmittingState();
    }
  }

  void _updateSubmittingState() {
    _username.disabled = widget.submitting;
    _password.disabled = widget.submitting;
    _passwordVisibility.disabled = widget.submitting;
    _submitButton.disabled = widget.submitting;
    _submitButton.textContent = widget.submitting ? 'Вход…' : 'Войти';
  }

  @override
  void dispose() {
    _form.removeEventListener('submit', _submitListener);
    _passwordVisibility.removeEventListener('click', _visibilityListener);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 184,
      child: HtmlElementView.fromTagName(
        tagName: 'div',
        onElementCreated: (element) {
          final host = element as web.HTMLDivElement;
          host.style.width = '100%';
          host.style.height = '100%';
          final styles = web.HTMLStyleElement()..textContent = _styles;
          host.append(styles);
          host.append(_form);
        },
      ),
    );
  }
}

const _styles = '''
.cashflow-native-login {
  display: grid;
  gap: 16px;
  width: 100%;
  font-family: Roboto, Arial, sans-serif;
}
.cashflow-native-input {
  box-sizing: border-box;
  width: 100%;
  height: 56px;
  padding: 0 16px;
  border: 1px solid #79747e;
  border-radius: 4px;
  outline: none;
  background: transparent;
  color: #1d1b20;
  font: inherit;
  font-size: 16px;
}
.cashflow-native-input:hover { border-color: #1d1b20; }
.cashflow-native-input:focus {
  border: 2px solid #6750a4;
  padding: 0 15px;
}
.cashflow-password-container { position: relative; }
.cashflow-password-input { padding-right: 88px; }
.cashflow-password-input:focus { padding-right: 87px; }
.cashflow-password-visibility {
  position: absolute;
  top: 0;
  right: 8px;
  height: 56px;
  border: 0;
  background: transparent;
  color: #49454f;
  cursor: pointer;
}
.cashflow-native-submit {
  width: 100%;
  height: 48px;
  border: 0;
  border-radius: 24px;
  background: #6750a4;
  color: white;
  font: inherit;
  font-weight: 500;
  cursor: pointer;
}
.cashflow-native-submit:hover { background: #5b4594; }
.cashflow-native-submit:disabled,
.cashflow-native-input:disabled,
.cashflow-password-visibility:disabled {
  cursor: default;
  opacity: .6;
}
''';
