import 'dart:io';
import 'package:flutter/material.dart';
import 'package:posture_detector/image_viewer.dart';
import 'package:posture_detector/success_screen.dart';

class ReviewScreen extends StatelessWidget {
  final List<String> photoPaths;
  const ReviewScreen({super.key, required this.photoPaths});

  @override
  Widget build(BuildContext context) {
    final tileWidth = (MediaQuery.of(context).size.width - 24 - 12) / 2;

    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 24, 24, 4),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  'Captured Photos',
                  style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ),
            const Padding(
              padding: EdgeInsets.fromLTRB(24, 0, 24, 12),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  'Tap a photo to view it full screen.',
                  style: TextStyle(color: Colors.grey),
                ),
              ),
            ),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                child: Wrap(
                  spacing: 12,
                  runSpacing: 12,
                  children: photoPaths.asMap().entries.map((entry) {
                    final int index = entry.key;
                    final String path = entry.value;

                    return ClipRRect(
                      borderRadius: BorderRadius.circular(8),
                      child: InkWell(
                        onTap: () {
                          Navigator.of(context).push(
                            MaterialPageRoute(
                              builder: (_) {
                                return GalleryImageViewer(
                                  images: photoPaths
                                      .map((p) => FileImage(File(p)))
                                      .toList(),
                                  initial_index: index,
                                  show_counter: true,
                                );
                              },
                            ),
                          );
                        },
                        child: Image.file(
                          File(path),
                          width: tileWidth,
                          fit: BoxFit.fitWidth,
                        ),
                      ),
                    );
                  }).toList(),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(24),
              child: SizedBox(
                width: double.infinity,
                height: 52,
                child: FilledButton(
                  onPressed: () => Navigator.of(context).pushReplacement(
                    MaterialPageRoute(builder: (_) => const SuccessScreen()),
                  ),
                  child: const Text('Continue', style: TextStyle(fontSize: 17)),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}