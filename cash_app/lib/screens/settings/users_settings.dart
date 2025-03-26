import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../providers/data_provider.dart';
import 'user_edit_screen.dart';

class UsersSettingsScreen extends StatelessWidget {
  const UsersSettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final dataProvider = Provider.of<DataProvider>(context);

    return Scaffold(
      appBar: AppBar(
        title: Text('Manage Users (${dataProvider.users.length})'),
        actions: [
          IconButton(
            icon: const Icon(Icons.add),
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => const UserEditScreen(),
                ),
              );
            },
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: () => dataProvider.fetchAllData(),
        child: ListView.builder(
          itemCount: dataProvider.users.length,
          itemBuilder: (context, index) {
            final user = dataProvider.users[index];
            return Card(
              margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              child: ListTile(
                leading: const Icon(Icons.person),
                title: Text(user.name),
                trailing: IconButton(
                  icon: const Icon(Icons.edit),
                  onPressed: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) => UserEditScreen(existingUser: user),
                      ),
                    );
                  },
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}