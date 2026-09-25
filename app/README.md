# CashFlow App

The Flutter client for CashFlow, a family cashback assistant. It helps family
members with shared access to several bank cards compare active cashback,
coordinate monthly category selections, and review personal partner offers.

The client targets mobile, web, and desktop layouts. Product scope and redesign
requirements are documented in [`../docs/product-design-brief.md`](../docs/product-design-brief.md).
The recommended workflow for checking mobile layouts at fixed viewport sizes is
documented in [`../docs/mobile-ui-validation.md`](../docs/mobile-ui-validation.md).

## Getting Started

Run Flutter commands through the repository helper so the same SDK configured
in VS Code is used:

```powershell
.\scripts\setup_vscode_flutter_env.ps1 -Run "flutter pub get"
.\scripts\setup_vscode_flutter_env.ps1 -Run "flutter analyze"
.\scripts\setup_vscode_flutter_env.ps1 -Run "flutter test"
```

A few Flutter resources:

- [Lab: Write your first Flutter app](https://docs.flutter.dev/get-started/codelab)
- [Cookbook: Useful Flutter samples](https://docs.flutter.dev/cookbook)

For help getting started with Flutter development, view the
[online documentation](https://docs.flutter.dev/), which offers tutorials,
samples, guidance on mobile development, and a full API reference.
