import 'package:flutter/material.dart';

class EmptyCollection extends StatelessWidget {
  final VoidCallback onAddPressed;

  const EmptyCollection({super.key, required this.onAddPressed});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Text(
            'No projects yet',
            style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          const Text(
            'Scan or import a music sheet to get started',
            style: TextStyle(color: Colors.grey),
          ),
          const SizedBox(height: 24),
          ElevatedButton(
            key: const ValueKey('addImageButton'),
            onPressed: onAddPressed,
            style: ElevatedButton.styleFrom(
              shape: const CircleBorder(),
              padding: const EdgeInsets.all(24),
              backgroundColor: Colors.white,
              side: const BorderSide(color: Colors.black12),
              elevation: 4,
            ),
            child: const Icon(Icons.add, size: 32, color: Colors.black),
          ),
          const SizedBox(height: 8),
          const Text('Add Image'),
        ],
      ),
    );
  }
}