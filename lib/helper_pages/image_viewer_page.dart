import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';

import 'security_service.dart';

class ImageViewerPage extends StatefulWidget {
  final List<String> imagePaths;
  final int initialIndex;

  const ImageViewerPage({
    super.key,
    required this.imagePaths,
    this.initialIndex = 0,
  });

  @override
  State<ImageViewerPage> createState() => _ImageViewerPageState();
}

class _ImageViewerPageState extends State<ImageViewerPage> {
  late final PageController _controller;
  late int _currentIndex;

  @override
  void initState() {
    super.initState();
    _currentIndex = widget.initialIndex;
    _controller = PageController(initialPage: widget.initialIndex);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        elevation: 0,
        title: Text('${_currentIndex + 1} / ${widget.imagePaths.length}'),
      ),
      body: PageView.builder(
        controller: _controller,
        itemCount: widget.imagePaths.length,
        onPageChanged: (i) => setState(() => _currentIndex = i),
        itemBuilder: (context, index) {
          final path = widget.imagePaths[index];
          return FutureBuilder<Uint8List>(
            future: SecurityService.instance.decryptFile(File(path)),
            builder: (context, snapshot) {
              if (snapshot.hasData) {
                return InteractiveViewer(
                  minScale: 1,
                  maxScale: 5,
                  child: Center(child: Image.memory(snapshot.data!)),
                );
              }
              if (snapshot.hasError) {
                return const Center(
                  child: Icon(Icons.broken_image, color: Colors.white54, size: 48),
                );
              }
              return const Center(child: CircularProgressIndicator());
            },
          );
        },
      ),
    );
  }
}
