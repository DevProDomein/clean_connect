import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../supabase_client.dart';

/// Picks an image and uploads it to Supabase Storage (default `public_assets`).
/// Reusable for company logos, avatars, etc.
class ImageUploadService {
  ImageUploadService._();

  static final ImagePicker _picker = ImagePicker();

  /// Lets the user choose camera or gallery, then uploads JPEG bytes to
  /// `{storageBucket}/{folderName}/{timestamp}.jpg` and returns the public URL.
  static Future<String?> pickAndUploadImage(
    BuildContext context,
    String folderName, {
    String storageBucket = 'public_assets',
  }) async {
    if (!context.mounted) return null;

    final source = await showModalBottomSheet<ImageSource>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.photo_camera_outlined),
              title: const Text('Camera'),
              onTap: () =>
                  Navigator.pop(ctx, ImageSource.camera),
            ),
            ListTile(
              leading: const Icon(Icons.photo_library_outlined),
              title: const Text('Galerij'),
              onTap: () =>
                  Navigator.pop(ctx, ImageSource.gallery),
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );

    if (!context.mounted || source == null) return null;

    final XFile? image = await _picker.pickImage(
      source: source,
      imageQuality: 70,
    );

    if (!context.mounted || image == null) return null;

    final messenger = ScaffoldMessenger.of(context);
    messenger.showSnackBar(
      const SnackBar(
        content: Text('Foto uploaden...'),
        duration: Duration(minutes: 1),
      ),
    );

    try {
      final bytes = await image.readAsBytes();
      if (bytes.isEmpty) {
        messenger.hideCurrentSnackBar();
        return null;
      }

      final fileName = '${DateTime.now().millisecondsSinceEpoch}.jpg';
      final path = '$folderName/$fileName';

      await AppSupabase.client.storage.from(storageBucket).uploadBinary(
            path,
            bytes,
            fileOptions: const FileOptions(
              upsert: true,
              contentType: 'image/jpeg',
            ),
          );

      final imageUrl = AppSupabase.client.storage
          .from(storageBucket)
          .getPublicUrl(path);

      if (context.mounted) {
        messenger.hideCurrentSnackBar();
      }
      return imageUrl;
    } catch (e, st) {
      debugPrint('ImageUploadService.pickAndUploadImage: $e\n$st');
      if (!context.mounted) return null;
      messenger.hideCurrentSnackBar();
      final errorString = e.toString().toLowerCase();
      if (errorString.contains('size') ||
          errorString.contains('exceeds') ||
          errorString.contains('large') ||
          errorString.contains('payload') ||
          errorString.contains('limit')) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Dit bestand is te groot. De maximale bestandsgrootte is 20MB.',
            ),
            backgroundColor: Colors.red,
          ),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Fout bij uploaden: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
      return null;
    }
  }
}
