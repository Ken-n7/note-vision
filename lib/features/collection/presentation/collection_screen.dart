import 'package:flutter/material.dart';
import 'package:note_vision/core/widgets/drawer.dart';
import 'package:note_vision/core/services/image_storage_service.dart';
import 'package:note_vision/features/capture/presentation/capture_screen.dart';
import 'widgets/empty_collection.dart';
import 'widgets/score_card.dart';

class CollectionScreen extends StatefulWidget {
  final ImageStorageService? imageStorageService;

  const CollectionScreen({
    super.key,
    this.imageStorageService,
  });

  @override
  State<CollectionScreen> createState() => _CollectionScreenState();
}

class _CollectionScreenState extends State<CollectionScreen> {
  int _currentIndex = 0;
  List<String> _imagePaths = [];
  bool _isLoading = true;

  late final ImageStorageService _service;

  @override
  void initState() {
    super.initState();
    _service = widget.imageStorageService ?? ImageStorageService();
    _loadImages();
  }

  Future<void> _loadImages() async {
    final paths = await _service.getSavedImages();
    if (mounted) {
      setState(() {
        _imagePaths = paths;
        _isLoading = false;
      });
    }
  }

  void _goToCapture() {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (context) => const CaptureScreen()),
    ).then((_) => _loadImages());
  }

  Widget _buildBody() {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_imagePaths.isEmpty) {
      return EmptyCollection(onAddPressed: _goToCapture);
    }

    return Padding(
      padding: const EdgeInsets.all(12),
      child: GridView.builder(
        itemCount: _imagePaths.length,
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 2,
          crossAxisSpacing: 10,
          mainAxisSpacing: 10,
        ),
        itemBuilder: (context, index) {
          return ScoreCard(imagePath: _imagePaths[index]);
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      endDrawer: const CollectionDrawer(),
      appBar: AppBar(
        key: const ValueKey('collectionAppBar'),
        backgroundColor: Colors.black,
        iconTheme: const IconThemeData(color: Colors.white),
        title: const Text(
          'My Files',
          style: TextStyle(color: Colors.white),
        ),
        centerTitle: true,
      ),
      body: _buildBody(),
      bottomNavigationBar: Theme(
        data: Theme.of(context).copyWith(
          splashFactory: NoSplash.splashFactory,
          highlightColor: Colors.transparent,
        ),
        child: BottomNavigationBar(
          key: const ValueKey('mainBottomNav'),
          backgroundColor: Colors.black,
          currentIndex: _currentIndex,
          onTap: (i) {
            setState(() => _currentIndex = i);
            if (i == 0) _goToCapture();
          },
          selectedItemColor: Colors.white,
          unselectedItemColor: Colors.white70,
          type: BottomNavigationBarType.fixed,
          enableFeedback: false,
          items: const [
            BottomNavigationBarItem(icon: Icon(Icons.add), label: 'Add Files'),
            BottomNavigationBarItem(icon: Icon(Icons.info), label: 'Info'),
            BottomNavigationBarItem(icon: Icon(Icons.edit), label: 'Edit'),
            BottomNavigationBarItem(icon: Icon(Icons.check), label: 'Result'),
          ],
        ),
      ),
    );
  }
}