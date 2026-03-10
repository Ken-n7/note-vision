import 'package:flutter/material.dart';

class CollectionDrawer extends StatelessWidget {
  const CollectionDrawer({super.key});

  Widget _buildDrawerItem({
    required IconData icon,
    required String title,
    required VoidCallback onTap,
  }) {
    return ListTile(
      leading: Icon(icon, color: Colors.black),
      title: Text(title),
      onTap: onTap,
      splashColor: Colors.transparent,
      hoverColor: Colors.transparent,
      // iconColor: Colors.white,   ← usually has no effect here (removed)
    );
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 200,
      child: Drawer(
        backgroundColor: Colors.white,
          child: ListView(
          padding: EdgeInsets.zero,
          children: [
            // Header
            Container(
              color: const Color.fromARGB(31, 0, 0, 0),
              height: 100,
              alignment: Alignment.centerLeft,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Padding(
                padding: const EdgeInsets.only(top: 50), // ← control top spacing here
                child: const Text(
                  'Menu',
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ),

            // Menu items
            _buildDrawerItem(
              icon: Icons.edit,
              title: 'Digital Writing',
              onTap: () {
                // TODO: Add real navigation or action
                Navigator.pop(context); // close drawer
              },
            ),
            _buildDrawerItem(
              icon: Icons.school,
              title: 'Instruction',
              onTap: () {
                // TODO: implement
                Navigator.pop(context);
              },
            ),
            _buildDrawerItem(
              icon: Icons.info,
              title: 'About',
              onTap: () {
                // TODO: implement
                Navigator.pop(context);
              },
            ),
          ],
        ),
      ),
    );
  }
}