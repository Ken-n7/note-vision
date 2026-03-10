import 'dart:io';
import 'package:flutter/material.dart';

class ScoreCard extends StatelessWidget {
  final String imagePath;
  final ImageProvider? imageProvider;

  const ScoreCard({
    super.key,
    required this.imagePath,
    this.imageProvider,
  });

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(10),
      child: Image(
        image: imageProvider ?? FileImage(File(imagePath)),
        fit: BoxFit.cover,
        errorBuilder: (_, __, ___) => Container(
          color: Colors.grey.shade200,
          child: const Icon(Icons.broken_image, color: Colors.grey),
        ),
      ),
    );
  }
}