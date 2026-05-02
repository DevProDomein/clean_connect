import 'dart:typed_data';
import 'dart:async';

import 'package:file_selector/file_selector.dart';
import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/supabase_client.dart';

class ExpenseUploadService {
  ExpenseUploadService({ImagePicker? picker}) : _picker = picker ?? ImagePicker();

  final ImagePicker _picker;

  /// Pick an image from camera or gallery, upload it to Storage (`inkoop_scans`),
  /// create a new `inkoopfacturen` row, and return the created invoice id.
  Future<String?> pickUploadAndCreateInvoice({
    required ImageSource source,
  }) async {
    final xfile = await _picker.pickImage(
      source: source,
      imageQuality: 92,
      maxWidth: 2200,
    );
    if (xfile == null) return null;

    final bytes = await xfile.readAsBytes();
    final ext = _guessExtension(xfile.name, fallback: 'jpg');
    return _createFromBytes(
      bytes: bytes,
      ext: ext,
      filenameHint: xfile.name,
    );
  }

  /// Pick any document (XML/PNG/JPG/PDF) and create an invoice.
  ///
  /// - If XML (UBL): mark as completed immediately (100% confidence).
  /// - Else: upload, insert with OCR status 'pending', then invoke edge function
  ///   fire-and-forget.
  Future<String?> pickUploadAndCreateInvoiceFromFilePicker() async {
    final file = await openFile(
      acceptedTypeGroups: const [
        XTypeGroup(
          label: 'Documenten',
          extensions: ['jpg', 'jpeg', 'png', 'webp', 'pdf', 'xml'],
        ),
      ],
    );
    if (file == null) return null;

    final bytes = await file.readAsBytes();
    final ext = _guessExtension(file.name, fallback: 'jpg');
    return _createFromBytes(
      bytes: bytes,
      ext: ext,
      filenameHint: file.name,
    );
  }

  Future<String?> _createFromBytes({
    required Uint8List bytes,
    required String ext,
    required String filenameHint,
  }) async {
    final normalizedExt = ext.toLowerCase().trim();

    // UBL/XML interception.
    if (normalizedExt == 'xml') {
      final inserted = await AppSupabase.client
          .from('inkoopfacturen')
          .insert({
            'status': 'in_behandeling',
            'is_ubl_xml': true,
            'ocr_verwerkings_status': 'completed',
            'ocr_confidence_scores': <String, dynamic>{
              'leverancier': 100.0,
              'factuur_nummer_leverancier': 100.0,
              'factuur_datum': 100.0,
              'totaal_inc_btw': 100.0,
            },
            'ocr_raw_data': <String, dynamic>{
              'provider': 'ubl_xml_simulated',
              'filename': filenameHint,
            },
          })
          .select('id')
          .maybeSingle();

      return inserted?['id']?.toString();
    }

    final path = '${DateTime.now().millisecondsSinceEpoch}.$normalizedExt';
    final url = await _uploadToStorageAndGetPublicUrl(
      path: path,
      bytes: bytes,
      contentType: _contentTypeForExt(normalizedExt),
    );

    final inserted = await AppSupabase.client
        .from('inkoopfacturen')
        .insert({
          'status': 'in_behandeling',
          'is_ubl_xml': false,
          'ocr_verwerkings_status': 'pending',
          'pdf_url': url,
        })
        .select('id')
        .maybeSingle();

    final id = inserted?['id']?.toString();
    if (id == null || id.isEmpty) return id;

    // Fire-and-forget OCR processing.
    unawaited(
      AppSupabase.client.functions.invoke(
        'process_expense_ocr',
        body: {'invoice_id': id, 'file_url': url},
      ),
    );

    return id;
  }

  Future<String> _uploadToStorageAndGetPublicUrl({
    required String path,
    required Uint8List bytes,
    required String contentType,
  }) async {
    await AppSupabase.client.storage.from('inkoop_scans').uploadBinary(
          path,
          bytes,
          fileOptions: FileOptions(
            contentType: contentType,
            upsert: false,
          ),
        );

    return AppSupabase.client.storage.from('inkoop_scans').getPublicUrl(path);
  }

  String _guessExtension(String filename, {required String fallback}) {
    final lower = filename.trim().toLowerCase();
    final i = lower.lastIndexOf('.');
    if (i < 0 || i == lower.length - 1) return fallback;
    final ext = lower.substring(i + 1);
    if (ext.length > 6) return fallback;
    return ext;
  }

  String _contentTypeForExt(String ext) {
    switch (ext.toLowerCase()) {
      case 'png':
        return 'image/png';
      case 'webp':
        return 'image/webp';
      case 'pdf':
        return 'application/pdf';
      case 'xml':
        return 'application/xml';
      case 'jpeg':
      case 'jpg':
      default:
        return 'image/jpeg';
    }
  }
}

