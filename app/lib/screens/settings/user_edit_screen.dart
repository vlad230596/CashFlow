import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../providers/data_provider.dart';
import '../widgets/versioned_app_bar_title.dart';
import '../widgets/keyboard_first_back.dart';
import '../../models/user_model.dart';
import '../../utils/identity_icons.dart';
import 'emoji_picker_screen.dart';

class UserEditScreen extends StatefulWidget {
  final UserModel? existingUser;

  const UserEditScreen({super.key, this.existingUser});

  @override
  State<UserEditScreen> createState() => _UserEditScreenState();
}

class _UserEditScreenState extends State<UserEditScreen> {
  final _formKey = GlobalKey<FormState>();
  late TextEditingController _nameController;
  late String _iconKey;

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(
      text: widget.existingUser?.name ?? '',
    );
    _iconKey = widget.existingUser?.iconKey ?? 'emoji:🙂';
  }

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  Future<void> _saveUser() async {
    if (!_formKey.currentState!.validate()) return;

    final dataProvider = Provider.of<DataProvider>(context, listen: false);
    final scaffoldMessenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);

    try {
      if (widget.existingUser == null) {
        await dataProvider.addUser(
          _nameController.text,
          iconKey: _iconKey,
        );
        if (!mounted) return;
        scaffoldMessenger.showSnackBar(
          const SnackBar(content: Text('Пользователь добавлен')),
        );
      } else {
        await dataProvider.updateUser(
          widget.existingUser!.id,
          _nameController.text,
          iconKey: _iconKey,
        );
        if (!mounted) return;
        scaffoldMessenger.showSnackBar(
          const SnackBar(content: Text('Пользователь сохранён')),
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
        leading: const KeyboardFirstBackButton(),
        title: VersionedAppBarTitle(
          title: widget.existingUser == null
              ? 'Новый пользователь'
              : 'Пользователь',
        ),
        actions: [
          if (widget.existingUser != null)
            IconButton(
              icon: const Icon(Icons.delete),
              onPressed: () async {
                final shouldDelete = await showDialog<bool>(
                  context: context,
                  builder: (context) => AlertDialog(
                    title: const Text('Delete User'),
                    content: const Text(
                        'Are you sure you want to delete this user?'),
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
                        .deleteUser(widget.existingUser!.id);
                    if (!context.mounted) return;
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                          content: Text('User deleted successfully')),
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
        child: Align(
          alignment: Alignment.topCenter,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 600),
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Form(
                key: _formKey,
                child: Column(
                  children: [
                    TextFormField(
                      controller: _nameController,
                      decoration: const InputDecoration(
                        labelText: 'Имя',
                        border: OutlineInputBorder(),
                      ),
                      validator: (value) {
                        if (value == null || value.isEmpty) {
                          return 'Введите имя';
                        }
                        return null;
                      },
                    ),
                    const SizedBox(height: 16),
                    ListTile(
                      key: const ValueKey('choose-user-emoji'),
                      contentPadding: EdgeInsets.zero,
                      leading: UserIconBadge(
                        iconKey: _iconKey,
                        userName: _nameController.text,
                        size: 44,
                      ),
                      title: const Text('Эмодзи пользователя'),
                      trailing: const Icon(Icons.chevron_right),
                      onTap: () async {
                        final selected = await Navigator.push<String>(
                          context,
                          MaterialPageRoute(
                            builder: (_) =>
                                EmojiPickerScreen(selectedIconKey: _iconKey),
                          ),
                        );
                        if (mounted && selected != null) {
                          setState(() => _iconKey = selected);
                        }
                      },
                    ),
                    const SizedBox(height: 24),
                    ElevatedButton(
                      onPressed: _saveUser,
                      style: ElevatedButton.styleFrom(
                        minimumSize: const Size(double.infinity, 50),
                      ),
                      child: const Text('Сохранить'),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
