import 'dart:io';

import 'package:flutter/foundation.dart'
    show defaultTargetPlatform, TargetPlatform;
import 'package:gal/gal.dart';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';

class PermissionDeniedException implements Exception {
  final String message;
  PermissionDeniedException(this.message);
  @override
  String toString() => message;
}

class SaveFileException implements Exception {
  final String message;
  SaveFileException(this.message);
  @override
  String toString() => message;
}

/// Save a file to a user-visible location.
/// Images / videos → device gallery.  Everything else → Downloads / Documents.
Future<String> saveFileToDevice(File file, String fileName) async {
  final ext = fileName.split('.').last.toLowerCase();
  final isImage = _imageExts.contains(ext);
  final isVideo = _videoExts.contains(ext);

  if (isImage || isVideo) {
    await _ensureGalleryPermission();
    try {
      if (isImage) {
        await Gal.putImage(file.path, album: 'NeoShare');
      } else {
        await Gal.putVideo(file.path, album: 'NeoShare');
      }
      return 'Gallery (NeoShare album)';
    } catch (e) {
      throw SaveFileException('Could not save to gallery: $e');
    }
  }

  // Non-media file → platform-specific location
  return _saveNonMedia(file, fileName);
}

Future<void> _ensureGalleryPermission() async {
  if (defaultTargetPlatform == TargetPlatform.iOS) {
    final status = await Permission.photosAddOnly.request();
    if (!status.isGranted) {
      throw PermissionDeniedException(
        'Gallery access denied. Please enable it in Settings → Privacy → Photos.',
      );
    }
  }
  // Android: Gal handles permissions via WRITE_EXTERNAL_STORAGE / MediaStore
}

Future<String> _saveNonMedia(File file, String fileName) async {
  if (defaultTargetPlatform == TargetPlatform.android) {
    final downloads = Directory('/storage/emulated/0/Download');
    if (await downloads.exists()) {
      final savePath = '${downloads.path}/$fileName';
      await file.copy(savePath);
      return savePath;
    }

    final extDir = await getExternalStorageDirectory();
    if (extDir != null) {
      final savePath = '${extDir.path}/$fileName';
      await file.copy(savePath);
      return savePath;
    }
  }

  // iOS or fallback: app-scoped Documents/NeoShare/
  final docsDir = await getApplicationDocumentsDirectory();
  final neoShareDir = Directory('${docsDir.path}/NeoShare');
  if (!await neoShareDir.exists()) {
    await neoShareDir.create(recursive: true);
  }
  final savePath = '${neoShareDir.path}/$fileName';
  await file.copy(savePath);
  return savePath;
}

const _imageExts = {'jpg', 'jpeg', 'png', 'gif', 'webp', 'bmp', 'heic'};
const _videoExts = {'mp4', 'mov', 'avi', 'mkv', 'webm', '3gp'};
