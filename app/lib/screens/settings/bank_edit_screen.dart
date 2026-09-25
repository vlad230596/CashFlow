import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../providers/data_provider.dart';
import '../widgets/versioned_app_bar_title.dart';
import '../../models/bank_model.dart';
import '../../utils/identity_icons.dart';

class BankEditScreen extends StatefulWidget {
  final BankModel? existingBank;

  const BankEditScreen({super.key, this.existingBank});

  @override
  State<BankEditScreen> createState() => _BankEditScreenState();
}

class _BankEditScreenState extends State<BankEditScreen> {
  final _formKey = GlobalKey<FormState>();
  late TextEditingController _nameController;
  late TextEditingController _descriptionController;
  late String _iconKey;

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(
      text: widget.existingBank?.name ?? '',
    );
    _descriptionController = TextEditingController(
      text: widget.existingBank?.description ?? '',
    );
    _iconKey = widget.existingBank?.iconKey ??
        defaultBankIconKey(widget.existingBank?.name);
  }

  @override
  void dispose() {
    _nameController.dispose();
    _descriptionController.dispose();
    super.dispose();
  }

  Future<void> _saveBank() async {
    if (!_formKey.currentState!.validate()) return;

    final dataProvider = Provider.of<DataProvider>(context, listen: false);
    final scaffoldMessenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);

    try {
      if (widget.existingBank == null) {
        await dataProvider.addBank(
          _nameController.text,
          _descriptionController.text, // Still pass the value, even if empty
          iconKey: _iconKey,
        );
        if (!mounted) return;
        scaffoldMessenger.showSnackBar(
          const SnackBar(content: Text('Bank added successfully')),
        );
      } else {
        await dataProvider.updateBank(
          widget.existingBank!.id!,
          _nameController.text,
          _descriptionController.text, // Still pass the value, even if empty
          iconKey: _iconKey,
        );
        if (!mounted) return;
        scaffoldMessenger.showSnackBar(
          const SnackBar(content: Text('Bank updated successfully')),
        );
      }
      navigator.pop();
    } catch (e) {
      if (!mounted) return;
      scaffoldMessenger.showSnackBar(
        SnackBar(content: Text('Error: ${e.toString()}')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: VersionedAppBarTitle(
          title: widget.existingBank == null ? 'Add New Bank' : 'Edit Bank',
        ),
        actions: [
          if (widget.existingBank != null)
            IconButton(
              icon: const Icon(Icons.delete),
              onPressed: () async {
                final shouldDelete = await showDialog<bool>(
                  context: context,
                  builder: (context) => AlertDialog(
                    title: const Text('Delete Bank'),
                    content: const Text(
                        'Are you sure you want to delete this bank?'),
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
                if (!context.mounted) return;

                if (shouldDelete == true) {
                  try {
                    await Provider.of<DataProvider>(context, listen: false)
                        .deleteBank(widget.existingBank!.id!);
                    if (!context.mounted) return;
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                          content: Text('Bank deleted successfully')),
                    );
                    Navigator.of(context).pop();
                  } catch (e) {
                    if (!context.mounted) return;
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text('Error: ${e.toString()}')),
                    );
                  }
                }
              },
            ),
        ],
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Form(
            key: _formKey,
            child: Column(
              children: [
                TextFormField(
                  controller: _nameController,
                  decoration: const InputDecoration(
                    labelText: 'Bank Name',
                    border: OutlineInputBorder(),
                  ),
                  validator: (value) {
                    if (value == null || value.isEmpty) {
                      return 'Please enter a bank name';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 16),
                Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    'Иконка банка',
                    style: Theme.of(context).textTheme.titleSmall,
                  ),
                ),
                const SizedBox(height: 8),
                Align(
                  alignment: Alignment.centerLeft,
                  child: Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      for (final option in bankIconOptions)
                        ChoiceChip(
                          key: ValueKey('bank-icon-${option.key}'),
                          selected: _iconKey == option.key,
                          onSelected: (_) =>
                              setState(() => _iconKey = option.key),
                          avatar: BankIconBadge(
                            iconKey: option.key,
                            bankName: option.label,
                            size: 28,
                          ),
                          label: Text(option.label),
                        ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: _descriptionController,
                  decoration: const InputDecoration(
                    labelText: 'Description (optional)',
                    border: OutlineInputBorder(),
                  ),
                  maxLines: 3,
                  // Remove the validator completely
                ),
                const SizedBox(height: 24),
                ElevatedButton(
                  onPressed: _saveBank,
                  style: ElevatedButton.styleFrom(
                    minimumSize: const Size(double.infinity, 50),
                  ),
                  child: const Text('Save Bank'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
