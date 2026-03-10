import 'package:flutter/material.dart';
import 'package:note_vision/features/scan/domain/scan_result.dart';
import 'detection_overlay.dart';

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
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                'Scan Result',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
              ),
              Text(
                '${result.symbols.length} symbol${result.symbols.length == 1 ? '' : 's'} detected',
                style: TextStyle(
                  fontSize: 12,
                  color: result.hasDetections ? Colors.green : Colors.orange,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
          Text(
            '${result.preprocessed.width} x ${result.preprocessed.height}px',
            style: const TextStyle(fontSize: 12, color: Colors.grey),
          ),
          const SizedBox(height: 12),
          Expanded(
            child: InteractiveViewer(
              child: Center(
                child: SizedBox(
                  width: result.preprocessed.width.toDouble(),
                  height: result.preprocessed.height.toDouble(),
                  child: Stack(
                    children: [
                      Positioned.fill(
                        child: Image.memory(
                          result.preprocessed.bytes,
                          fit: BoxFit.fill,
                        ),
                      ),
                      if (result.hasDetections)
                        Positioned.fill(
                          child: DetectionOverlay(symbols: result.symbols),
                        ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}