import 'package:flutter/material.dart';

class AdminLoadingState extends StatelessWidget {
  const AdminLoadingState({super.key, this.longRunning = false});

  final bool longRunning;

  @override
  Widget build(BuildContext context) {
    final color = Theme.of(context).colorScheme.surfaceContainerHighest;
    return Semantics(
      label: longRunning ? 'Загружаем данные' : 'Загрузка',
      liveRegion: longRunning,
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (longRunning) ...[
              const LinearProgressIndicator(),
              const SizedBox(height: 16),
              Text(
                'Загружаем данные',
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: 16),
            ],
            for (final width in const [1.0, .72, .88]) ...[
              FractionallySizedBox(
                alignment: Alignment.centerLeft,
                widthFactor: width,
                child: Container(
                  height: 52,
                  decoration: BoxDecoration(
                    color: color,
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
              ),
              const SizedBox(height: 12),
            ],
          ],
        ),
      ),
    );
  }
}

class AdminErrorState extends StatelessWidget {
  const AdminErrorState({
    super.key,
    required this.message,
    required this.onRetry,
  });

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) => _CenteredState(
        icon: Icons.error_outline,
        title: 'Не удалось загрузить данные',
        message: message,
        actionLabel: 'Повторить',
        onAction: onRetry,
      );
}

class AdminEmptyState extends StatelessWidget {
  const AdminEmptyState({
    super.key,
    required this.title,
    required this.message,
    this.actionLabel,
    this.onAction,
  });

  final String title;
  final String message;
  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) => _CenteredState(
        icon: Icons.inbox_outlined,
        title: title,
        message: message,
        actionLabel: actionLabel,
        onAction: onAction,
      );
}

class AdminAccessDeniedState extends StatelessWidget {
  const AdminAccessDeniedState({super.key, required this.onReturn});

  final VoidCallback onReturn;

  @override
  Widget build(BuildContext context) => _CenteredState(
        icon: Icons.shield_outlined,
        title: 'Недостаточно прав',
        message: 'Правила и справочники доступны администратору. '
            'Вы вошли с другой ролью.',
        actionLabel: 'Вернуться в Выгоду',
        onAction: onReturn,
        secondaryLabel: 'О доступе',
        onSecondaryAction: () => showDialog<void>(
          context: context,
          builder: (dialogContext) => AlertDialog(
            title: const Text('Доступ к управлению'),
            content: const Text(
              'Изменять банки, участников, карты и правила MCC может только '
              'администратор. За изменением роли обратитесь к администратору.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogContext),
                child: const Text('Понятно'),
              ),
            ],
          ),
        ),
      );
}

class AdminOfflineBanner extends StatelessWidget {
  const AdminOfflineBanner({
    super.key,
    this.lastUpdated,
    required this.onRefresh,
  });

  final String? lastUpdated;
  final VoidCallback onRefresh;

  @override
  Widget build(BuildContext context) {
    return MaterialBanner(
      leading: const Icon(Icons.cloud_off_outlined),
      content: Text(
        lastUpdated == null
            ? 'Работаем офлайн. Показаны сохранённые данные.'
            : 'Работаем офлайн. Последнее обновление: $lastUpdated',
      ),
      actions: [
        TextButton(onPressed: onRefresh, child: const Text('Обновить')),
      ],
    );
  }
}

class _CenteredState extends StatelessWidget {
  const _CenteredState({
    required this.icon,
    required this.title,
    required this.message,
    this.actionLabel,
    this.onAction,
    this.secondaryLabel,
    this.onSecondaryAction,
  });

  final IconData icon;
  final String title;
  final String message;
  final String? actionLabel;
  final VoidCallback? onAction;
  final String? secondaryLabel;
  final VoidCallback? onSecondaryAction;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 480),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                icon,
                size: 48,
                color: Theme.of(context).colorScheme.primary,
              ),
              const SizedBox(height: 16),
              Text(
                title,
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.headlineSmall,
              ),
              const SizedBox(height: 8),
              Text(message, textAlign: TextAlign.center),
              if (actionLabel != null && onAction != null) ...[
                const SizedBox(height: 24),
                FilledButton(onPressed: onAction, child: Text(actionLabel!)),
              ],
              if (secondaryLabel != null && onSecondaryAction != null) ...[
                const SizedBox(height: 8),
                TextButton(
                  onPressed: onSecondaryAction,
                  child: Text(secondaryLabel!),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
