import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../providers/data_provider.dart';
import '../../models/card_model.dart';

class CardEditScreen extends StatefulWidget {
  final CardModel? existingCard;

  const CardEditScreen({super.key, this.existingCard});

  @override
  State<CardEditScreen> createState() => _CardEditScreenState();
}

class _CardEditScreenState extends State<CardEditScreen> {
  final _formKey = GlobalKey<FormState>();
  late TextEditingController _paymentSystemController;
  late TextEditingController _cardTypeController;
  late TextEditingController _lastFourDigitsController;
  int? _selectedBankId;
  int? _selectedUserId;

  @override
  void initState() {
    super.initState();
    _paymentSystemController = TextEditingController(
      text: widget.existingCard?.paymentSystem ?? '',
    );
    _cardTypeController = TextEditingController(
      text: widget.existingCard?.cardType ?? '',
    );
    _lastFourDigitsController = TextEditingController(
      text: widget.existingCard?.lastFourDigits ?? '',
    );
    _selectedBankId = widget.existingCard?.bankId;
    _selectedUserId = widget.existingCard?.userId;
  }

  @override
  void dispose() {
    _paymentSystemController.dispose();
    _cardTypeController.dispose();
    _lastFourDigitsController.dispose();
    super.dispose();
  }

  Future<void> _saveCard() async {
    if (!_formKey.currentState!.validate()) return;
    if (_selectedBankId == null || _selectedUserId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please select both bank and user')),
      );
      return;
    }

    final dataProvider = Provider.of<DataProvider>(context, listen: false);
    final scaffoldMessenger = ScaffoldMessenger.of(context);

    try {
      if (widget.existingCard == null) {
        await dataProvider.addCard(
          _paymentSystemController.text,
          _cardTypeController.text,
          _lastFourDigitsController.text,
          _selectedBankId!,
          _selectedUserId!,
        );
        scaffoldMessenger.showSnackBar(
          const SnackBar(content: Text('Card added successfully')),
        );
      } else {
        await dataProvider.updateCard(
          widget.existingCard!.id!,
          _paymentSystemController.text,
          _cardTypeController.text,
          _lastFourDigitsController.text,
          _selectedBankId!,
          _selectedUserId!,
        );
        scaffoldMessenger.showSnackBar(
          const SnackBar(content: Text('Card updated successfully')),
        );
      }
      Navigator.of(context).pop();
    } catch (e) {
      scaffoldMessenger.showSnackBar(
        SnackBar(content: Text('Error: ${e.toString()}')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final dataProvider = Provider.of<DataProvider>(context);

    return Scaffold(
      appBar: AppBar(
        title: Text(
            widget.existingCard == null ? 'Add New Card' : 'Edit Card'),
        actions: [
          if (widget.existingCard != null)
            IconButton(
              icon: const Icon(Icons.delete),
              onPressed: () async {
                final shouldDelete = await showDialog<bool>(
                  context: context,
                  builder: (context) => AlertDialog(
                    title: const Text('Delete Card'),
                    content: const Text(
                        'Are you sure you want to delete this card?'),
                    actions: [
                      TextButton(
                        onPressed: () => Navigator.pop(context, false),
                        child: const Text('Cancel'),
                      ),
                      TextButton(
                        onPressed: () => Navigator.pop(context, true),
                        child: const Text('Delete'),
                      ),
                    ],
                  ),
                );

                if (shouldDelete == true) {
                  try {
                    await dataProvider.deleteCard(widget.existingCard!.id!);
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Card deleted successfully')),
                    );
                    Navigator.of(context).pop();
                  } catch (e) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text('Error: ${e.toString()}')),
                    );
                  }
                }
              },
            ),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Form(
          key: _formKey,
          child: ListView(
            children: [
              TextFormField(
                controller: _paymentSystemController,
                decoration: const InputDecoration(
                  labelText: 'Payment System (Visa/Mastercard/etc.)',
                  border: OutlineInputBorder(),
                ),
                validator: (value) {
                  if (value == null || value.isEmpty) {
                    return 'Please enter payment system';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _cardTypeController,
                decoration: const InputDecoration(
                  labelText: 'Card Type (Physical/Virtual)',
                  border: OutlineInputBorder(),
                ),
                validator: (value) {
                  if (value == null || value.isEmpty) {
                    return 'Please enter card type';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _lastFourDigitsController,
                decoration: const InputDecoration(
                  labelText: 'Last 4 Digits',
                  border: OutlineInputBorder(),
                ),
                keyboardType: TextInputType.number,
                maxLength: 4,
                validator: (value) {
                  if (value == null || value.isEmpty || value.length != 4) {
                    return 'Please enter 4 digits';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 16),
              DropdownButtonFormField<int>(
                value: _selectedBankId,
                decoration: const InputDecoration(
                  labelText: 'Bank',
                  border: OutlineInputBorder(),
                ),
                items: dataProvider.banks.map((bank) {
                  return DropdownMenuItem(
                    value: bank.id,
                    child: Text(bank.name!),
                  );
                }).toList(),
                onChanged: (value) {
                  setState(() {
                    _selectedBankId = value;
                  });
                },
                validator: (value) {
                  if (value == null) {
                    return 'Please select a bank';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 16),
              DropdownButtonFormField<int>(
                value: _selectedUserId,
                decoration: const InputDecoration(
                  labelText: 'User',
                  border: OutlineInputBorder(),
                ),
                items: dataProvider.users.map((user) {
                  return DropdownMenuItem(
                    value: user.id,
                    child: Text(user.name),
                  );
                }).toList(),
                onChanged: (value) {
                  setState(() {
                    _selectedUserId = value;
                  });
                },
                validator: (value) {
                  if (value == null) {
                    return 'Please select a user';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 24),
              ElevatedButton(
                onPressed: _saveCard,
                style: ElevatedButton.styleFrom(
                  minimumSize: const Size(double.infinity, 50),
                ),
                child: const Text('Save Card'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}