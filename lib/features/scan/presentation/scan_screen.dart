import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:note_vision/features/scan/presentation/scan_viewmodel.dart';
import 'package:note_vision/features/preprocessing/data/basic_image_preprocessor.dart';
import 'widgets/scan_actions.dart';
import 'widgets/scan_image_view.dart';

class ScanScreen extends StatefulWidget {
  final Uint8List imageBytes;

  const ScanScreen({super.key, required this.imageBytes});

  @override
  State<ScanScreen> createState() => _ScanScreenState();
}

class _ScanScreenState extends State<ScanScreen> {
  @override
  void initState() {
    super.initState();
    // run pipeline as soon as screen opens
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<ScanViewModel>().run(widget.imageBytes);
    });
  }

  @override
  Widget build(BuildContext context) {
    final vm = context.watch<ScanViewModel>();

    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.black,
        iconTheme: const IconThemeData(color: Colors.white),
        title: const Text(
          'Scan Result',
          style: TextStyle(color: Colors.white),
        ),
        centerTitle: true,
      ),
      body: switch (vm.state) {
        ScanState.idle => const SizedBox(),
        ScanState.preprocessing => const Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                CircularProgressIndicator(),
                SizedBox(height: 16),
                Text('Preprocessing image...'),
              ],
            ),
          ),
        ScanState.done => Column(
            children: [
              Expanded(
                child: ScanImageView(result: vm.result!),
              ),
              ScanActions(
                onRedo: () => Navigator.pop(context),
                onContinue: () {
                  // navigate to editor — coming soon
                },
              ),
            ],
          ),
        ScanState.error => Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.error_outline, size: 48, color: Colors.red),
                  const SizedBox(height: 16),
                  Text(
                    'Something went wrong:\n${vm.errorMessage}',
                    textAlign: TextAlign.center,
                    style: const TextStyle(color: Colors.red),
                  ),
                  const SizedBox(height: 24),
                  ElevatedButton(
                    onPressed: () => Navigator.pop(context),
                    child: const Text('Go Back'),
                  ),
                ],
              ),
            ),
          ),
      },
    );
  }
}

// convenience wrapper that injects the viewmodel
class ScanScreenProvider extends StatelessWidget {
  final Uint8List imageBytes;

  const ScanScreenProvider({super.key, required this.imageBytes});

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider(
      create: (_) => ScanViewModel(BasicImagePreprocessor()),
      child: ScanScreen(imageBytes: imageBytes),
    );
  }
}