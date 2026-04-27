import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/cashback_category_model.dart';
import '../providers/data_provider.dart';

class CashbackCategoryEditScreen extends StatefulWidget {
  final CashbackCategoryModel category;

  const CashbackCategoryEditScreen({
    super.key,
    required this.category,
  });

  @override
  State<CashbackCategoryEditScreen> createState() =>
      _CashbackCategoryEditScreenState();
}

class _CashbackCategoryEditScreenState
    extends State<CashbackCategoryEditScreen> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _nameController;
  late final TextEditingController _cashbackPercentController;
  late DateTime _startDate;
  late DateTime _endDate;
  late bool _isSelected;
  late int _cardId;
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(text: widget.category.name);
    _cashbackPercentController = TextEditingController(
      text: widget.category.cashbackPercent.toString(),
    );
    _startDate = DateUtils.dateOnly(widget.category.startDate);
    _endDate = DateUtils.dateOnly(widget.category.endDate);
    _isSelected = widget.category.isSelected;
    _cardId = widget.category.cardId;
  }

  @override
  void dispose() {
    _nameController.dispose();
    _cashbackPercentController.dispose();
    super.dispose();
  }

  Future<void> _pickDate({
    required DateTime initialDate,
    required ValueChanged<DateTime> onPicked,
  }) async {
    final picked = await showDatePicker(
      context: context,
      initialDate: initialDate,
      firstDate: DateTime(2020),
      lastDate: DateTime(2030),
    );

    if (picked != null) {
      onPicked(DateUtils.dateOnly(picked));
    }
  }

  DateTime _endOfDay(DateTime date) {
    return DateTime(date.year, date.month, date.day, 23, 59, 59, 999);
  }

  String _formatDate(DateTime date) {
    return '${date.day.toString().padLeft(2, '0')}.'
        '${date.month.toString().padLeft(2, '0')}.${date.year}';
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;

    if (_endDate.isBefore(_startDate)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Дата окончания раньше даты начала')),
      );
      return;
    }

    setState(() {
      _isSaving = true;
    });

    final dataProvider = Provider.of<DataProvider>(context, listen: false);
    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);

    try {
      await dataProvider.updateCashbackCategory(
        widget.category.copyWith(
          name: _nameController.text.trim(),
          cashbackPercent: double.parse(
            _cashbackPercentController.text.replaceAll(',', '.'),
          ),
          cardId: _cardId,
          startDate: _startDate,
          endDate: _endOfDay(_endDate),
          isSelected: _isSelected,
        ),
      );

      if (!mounted) return;
      messenger.showSnackBar(
        const SnackBar(content: Text('Категория кешбека обновлена')),
      );
      navigator.pop();
    } catch (e) {
      if (!mounted) return;
      messenger.showSnackBar(
        SnackBar(content: Text('Ошибка: ${e.toString()}')),
      );
      setState(() {
        _isSaving = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final dataProvider = Provider.of<DataProvider>(context);
    final cardItems = dataProvider.cards
        .where((card) => card.id != null)
        .map(
          (card) => DropdownMenuItem<int>(
            value: card.id,
            child: Text(
              '${dataProvider.getCardName(card.id!)} '
              '${card.lastFourDigits ?? '????'}',
            ),
          ),
        )
        .toList();

    return Scaffold(
      appBar: AppBar(
        title: const Text('Редактировать кешбек'),
      ),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            TextFormField(
              initialValue: widget.category.id.toString(),
              enabled: false,
              decoration: const InputDecoration(
                labelText: 'ID',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _nameController,
              decoration: const InputDecoration(
                labelText: 'Название',
                border: OutlineInputBorder(),
              ),
              validator: (value) {
                if (value == null || value.trim().isEmpty) {
                  return 'Введите название';
                }
                return null;
              },
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _cashbackPercentController,
              decoration: const InputDecoration(
                labelText: 'Процент кешбека',
                border: OutlineInputBorder(),
              ),
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              validator: (value) {
                final normalized = value?.replaceAll(',', '.');
                if (normalized == null ||
                    normalized.trim().isEmpty ||
                    double.tryParse(normalized) == null) {
                  return 'Введите число';
                }
                return null;
              },
            ),
            const SizedBox(height: 16),
            DropdownButtonFormField<int>(
              initialValue: cardItems.any((item) => item.value == _cardId)
                  ? _cardId
                  : null,
              decoration: const InputDecoration(
                labelText: 'Карта',
                border: OutlineInputBorder(),
              ),
              items: cardItems,
              onChanged: (value) {
                if (value == null) return;
                setState(() {
                  _cardId = value;
                });
              },
              validator: (value) {
                if (value == null) {
                  return 'Выберите карту';
                }
                return null;
              },
            ),
            const SizedBox(height: 16),
            SwitchListTile(
              title: const Text('Выбрана'),
              value: _isSelected,
              contentPadding: EdgeInsets.zero,
              onChanged: (value) {
                setState(() {
                  _isSelected = value;
                });
              },
            ),
            const SizedBox(height: 8),
            ListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Дата начала'),
              subtitle: Text(_formatDate(_startDate)),
              trailing: const Icon(Icons.calendar_today),
              onTap: () => _pickDate(
                initialDate: _startDate,
                onPicked: (date) {
                  setState(() {
                    _startDate = date;
                  });
                },
              ),
            ),
            const Divider(height: 1),
            ListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Дата окончания'),
              subtitle: Text(_formatDate(_endDate)),
              trailing: const Icon(Icons.calendar_today),
              onTap: () => _pickDate(
                initialDate: _endDate,
                onPicked: (date) {
                  setState(() {
                    _endDate = date;
                  });
                },
              ),
            ),
            const SizedBox(height: 24),
            ElevatedButton(
              onPressed: _isSaving ? null : _save,
              style: ElevatedButton.styleFrom(
                minimumSize: const Size(double.infinity, 48),
              ),
              child: _isSaving
                  ? const SizedBox(
                      height: 20,
                      width: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Text('Сохранить'),
            ),
          ],
        ),
      ),
    );
  }
}
