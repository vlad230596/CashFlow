import 'package:flutter/material.dart';

import '../../models/mcc_lookup_model.dart';
import '../../models/mcc_rule_model.dart';

typedef OfferMccRulesLoader = Future<OfferMccRulesModel?> Function();

/// MCC codes of the bank category behind a card offer, with a filter, the
/// category's own exclusions and the program-wide exclusions.
class OfferMccRulesSection extends StatefulWidget {
  const OfferMccRulesSection({super.key, required this.load});

  final OfferMccRulesLoader load;

  @override
  State<OfferMccRulesSection> createState() => _OfferMccRulesSectionState();
}

class _OfferMccRulesSectionState extends State<OfferMccRulesSection> {
  static const _collapsedCount = 12;

  late Future<OfferMccRulesModel?> _rules;
  final _filter = TextEditingController();
  bool _showAll = false;

  @override
  void initState() {
    super.initState();
    _rules = widget.load();
    _filter.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _filter.dispose();
    super.dispose();
  }

  bool _matches(String code, String? title) {
    final query = _filter.text.trim().toLowerCase();
    if (query.isEmpty) return true;
    return code.startsWith(query) ||
        (title?.toLowerCase().contains(query) ?? false);
  }

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    return Column(
      key: const Key('offer-mcc-rules'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text('MCC-коды', style: textTheme.titleLarge),
        const SizedBox(height: 8),
        FutureBuilder<OfferMccRulesModel?>(
          future: _rules,
          builder: (context, snapshot) {
            if (snapshot.connectionState != ConnectionState.done) {
              return const Padding(
                padding: EdgeInsets.symmetric(vertical: 12),
                child: LinearProgressIndicator(),
              );
            }
            if (snapshot.hasError) {
              return _Message(
                text: 'Не удалось загрузить MCC-коды.',
                actionLabel: 'Повторить',
                onAction: () => setState(() => _rules = widget.load()),
              );
            }
            final rules = snapshot.data;
            if (rules == null) {
              return const _Message(
                text: 'Банк не опубликовал список MCC для этой категории. '
                    'Ориентируйтесь на описание условий.',
              );
            }
            return _buildRules(context, rules);
          },
        ),
      ],
    );
  }

  Widget _buildRules(BuildContext context, OfferMccRulesModel rules) {
    final colors = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final included = rules.included
        .where((item) => _matches(item.code, item.title))
        .toList();
    final excluded = rules.excluded
        .where((item) => _matches(item.code, item.title))
        .toList();
    final exclusions = rules.exclusions
        .where((item) => _matches(item.mcc, item.title))
        .toList();
    final filtering = _filter.text.trim().isNotEmpty;
    final shown = filtering || _showAll
        ? included
        : included.take(_collapsedCount).toList();
    final total = rules.included.length;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          [
            rules.programName,
            if (rules.categoryName.isNotEmpty) '«${rules.categoryName}»',
            '$total ${_codesWord(total)}',
          ].join(' · '),
          style: textTheme.bodySmall,
        ),
        if (rules.kind == 'all_purchases') ...[
          const SizedBox(height: 8),
          const _Message(
            text: 'Категория на все покупки: начисляется за любой код, '
                'кроме исключений программы.',
          ),
        ] else if (rules.completeness != 'exact_mcc') ...[
          const SizedBox(height: 8),
          const _Message(
            text: 'Банк описал категорию текстом — список кодов может быть '
                'неполным.',
          ),
        ],
        if (total + rules.excluded.length + rules.exclusions.length > 6) ...[
          const SizedBox(height: 10),
          TextField(
            key: const Key('offer-mcc-filter'),
            controller: _filter,
            keyboardType: TextInputType.text,
            decoration: InputDecoration(
              isDense: true,
              prefixIcon: const Icon(Icons.search_outlined),
              hintText: 'Код или название',
              border: const OutlineInputBorder(),
              suffixIcon: filtering
                  ? IconButton(
                      tooltip: 'Очистить',
                      onPressed: _filter.clear,
                      icon: const Icon(Icons.close),
                    )
                  : null,
            ),
          ),
        ],
        const SizedBox(height: 8),
        if (total == 0 && rules.kind != 'all_purchases')
          const _Message(text: 'Коды в категории не перечислены.'),
        for (final item in shown) _CodeRow(code: item.code, title: item.title),
        if (!filtering && !_showAll && included.length > shown.length)
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton(
              onPressed: () => setState(() => _showAll = true),
              child: Text('Показать все $total'),
            ),
          ),
        if (filtering &&
            included.isEmpty &&
            excluded.isEmpty &&
            exclusions.isEmpty)
          _Message(
            text: 'Код «${_filter.text.trim()}» в категорию не входит и '
                'в исключениях не указан.',
          ),
        if (excluded.isNotEmpty) ...[
          const SizedBox(height: 12),
          Text('Исключены из категории', style: textTheme.titleSmall),
          const SizedBox(height: 4),
          for (final item in excluded)
            _CodeRow(
              code: item.code,
              title: item.title,
              color: colors.error,
            ),
        ],
        if (exclusions.isNotEmpty)
          Theme(
            data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
            child: ExpansionTile(
              key: ValueKey('program-exclusions-$filtering'),
              initiallyExpanded: filtering,
              tilePadding: EdgeInsets.zero,
              childrenPadding: EdgeInsets.zero,
              title: Text(
                'Исключения программы · ${exclusions.length}',
                style: textTheme.titleSmall,
              ),
              subtitle: const Text('Действуют для всех категорий банка'),
              children: [
                for (final item in exclusions) _ExclusionRow(exclusion: item),
              ],
            ),
          ),
      ],
    );
  }
}

class _CodeRow extends StatelessWidget {
  const _CodeRow({required this.code, this.title, this.color});

  final String code;
  final String? title;
  final Color? color;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            MccCodeBadge(code: code, color: color),
            const SizedBox(width: 10),
            Expanded(child: Text(title ?? 'Нет в справочнике MCC')),
          ],
        ),
      );
}

class _ExclusionRow extends StatelessWidget {
  const _ExclusionRow({required this.exclusion});

  final MccExclusionModel exclusion;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final always = exclusion.kind == 'always';
    final reason = exclusion.reason?.trim();
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          MccCodeBadge(
            code: exclusion.mcc,
            color: always ? colors.error : colors.tertiary,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(exclusion.title ?? 'Нет в справочнике MCC'),
                Text(
                  [
                    mccExclusionKindLabel(exclusion.kind),
                    if (reason != null && reason.isNotEmpty) reason,
                  ].join(' · '),
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: always ? colors.error : null,
                      ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Four-digit MCC in a monospace pill.
class MccCodeBadge extends StatelessWidget {
  const MccCodeBadge({super.key, required this.code, this.color});

  final String code;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final foreground = color ?? Theme.of(context).colorScheme.primary;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: foreground.withValues(alpha: .1),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        code,
        style: TextStyle(
          color: foreground,
          fontWeight: FontWeight.w800,
          fontFeatures: const [FontFeature.tabularFigures()],
        ),
      ),
    );
  }
}

class _Message extends StatelessWidget {
  const _Message({required this.text, this.actionLabel, this.onAction});

  final String text;
  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.all(11),
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(10),
        ),
        child: Row(
          children: [
            Expanded(
              child: Text(text, style: Theme.of(context).textTheme.bodySmall),
            ),
            if (actionLabel != null)
              TextButton(onPressed: onAction, child: Text(actionLabel!)),
          ],
        ),
      );
}

String _codesWord(int count) {
  final mod100 = count % 100;
  final mod10 = count % 10;
  if (mod100 >= 11 && mod100 <= 14) return 'кодов';
  if (mod10 == 1) return 'код';
  if (mod10 >= 2 && mod10 <= 4) return 'кода';
  return 'кодов';
}
