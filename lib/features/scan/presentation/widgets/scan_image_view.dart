import 'package:flutter/material.dart';
import 'package:note_vision/features/scan/domain/scan_result.dart';

class ScanImageView extends StatelessWidget {
  final ScanResult result;

  const ScanImageView({super.key, required this.result});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Preprocessed Image',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 4),
          Text(
            '${result.preprocessed.width} x ${result.preprocessed.height}px',
            style: const TextStyle(fontSize: 12, color: Colors.grey),
          ),
          const SizedBox(height: 12),
          Expanded(
            child: InteractiveViewer(
              child: Center(
                child: Image.memory(result.preprocessed.bytes),
              ),
            ),
          ),
          // detection overlay will be added here later
        ],
      ),
    );
  }
}