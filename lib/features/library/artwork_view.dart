import 'dart:typed_data';

import 'package:flutter/material.dart';

class ArtworkView extends StatelessWidget {
  const ArtworkView({
    super.key,
    required this.bytes,
    this.size = 48,
    this.borderRadius = 8,
  });

  final Uint8List? bytes;
  final double size;
  final double borderRadius;

  @override
  Widget build(BuildContext context) => ClipRRect(
    borderRadius: BorderRadius.circular(borderRadius),
    child: SizedBox.square(
      dimension: size,
      child: bytes == null || bytes!.isEmpty
          ? ColoredBox(
              color: Theme.of(context).colorScheme.primaryContainer,
              child: Icon(Icons.music_note_rounded, size: size * 0.42),
            )
          : Image.memory(bytes!, fit: BoxFit.cover, gaplessPlayback: true),
    ),
  );
}
