import 'dart:typed_data';

import 'package:flutter/material.dart';

enum WallpaperFit { cropToFill, fitEntireImage }

enum RotationOrder { sequential, shuffle }

enum PhotoSource { askEveryTime, photos, files }

class WallpaperAlbum {
  const WallpaperAlbum({required this.id, required this.name});

  final String id;
  final String name;
}

class Wallpaper {
  const Wallpaper({
    required this.id,
    required this.name,
    required this.palette,
    required this.style,
    this.uri,
    this.thumbnail,
    this.mainPreview,
    this.preview,
    this.imageWidth,
    this.imageHeight,
    this.crop = const WallpaperCrop(),
    this.albumIds = const {},
  });

  final String id;
  final String name;
  final List<Color> palette;
  final int style;
  final String? uri;
  final Uint8List? thumbnail;
  final Uint8List? mainPreview;
  final Uint8List? preview;
  final int? imageWidth;
  final int? imageHeight;
  final WallpaperCrop crop;
  final Set<String> albumIds;

  bool get isUserImage => uri != null;

  Wallpaper copyWith({
    WallpaperCrop? crop,
    Uint8List? thumbnail,
    Uint8List? mainPreview,
    Uint8List? preview,
    Set<String>? albumIds,
  }) => Wallpaper(
    id: id,
    name: name,
    palette: palette,
    style: style,
    uri: uri,
    thumbnail: thumbnail ?? this.thumbnail,
    mainPreview: mainPreview ?? this.mainPreview,
    preview: preview ?? this.preview,
    imageWidth: imageWidth,
    imageHeight: imageHeight,
    crop: crop ?? this.crop,
    albumIds: albumIds ?? this.albumIds,
  );
}

class WallpaperCrop {
  const WallpaperCrop({this.scale = 1, this.offsetX = 0, this.offsetY = 0});

  final double scale;
  final double offsetX;
  final double offsetY;

  bool get isDefault => scale == 1 && offsetX == 0 && offsetY == 0;
}

const bundledWallpapers = <Wallpaper>[
  Wallpaper(
    id: 'tidal',
    name: 'Tidal',
    palette: [Color(0xFF061210), Color(0xFF123E3D), Color(0xFF8AE4DC)],
    style: 0,
  ),
  Wallpaper(
    id: 'silver',
    name: 'Silver',
    palette: [Color(0xFF080B0B), Color(0xFF3C4543), Color(0xFFCDD5D2)],
    style: 1,
  ),
  Wallpaper(
    id: 'depth',
    name: 'Depth',
    palette: [Color(0xFF040D0B), Color(0xFF102622), Color(0xFF34756E)],
    style: 2,
  ),
  Wallpaper(
    id: 'slate',
    name: 'Slate',
    palette: [Color(0xFF0B1010), Color(0xFF28312F), Color(0xFF71807C)],
    style: 3,
  ),
];
