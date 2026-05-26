import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:pdf/pdf.dart';
import 'package:printing/printing.dart';

import '../services/pdf_generator_service.dart';

/// Live concept-PDF preview met custom zwevende actiebalk.
class PdfPreviewScreen extends StatefulWidget {
  const PdfPreviewScreen({
    super.key,
    required this.offerteId,
    this.offerteNummer = 'Concept',
  });

  final String offerteId;
  final String offerteNummer;

  @override
  State<PdfPreviewScreen> createState() => _PdfPreviewScreenState();
}

class _PdfPreviewScreenState extends State<PdfPreviewScreen> {
  Uint8List? _gecachetePdfBytes;
  bool _isProcessing = false;
  String _statusMessage = '';

  Future<Uint8List> _generateAndCachePdf() async {
    _gecachetePdfBytes ??=
        await PdfGeneratorService.generateOffertePdf(widget.offerteId);
    return _gecachetePdfBytes!;
  }

  Future<void> _deelOfSlaOp() async {
    if (_gecachetePdfBytes == null) return;

    setState(() {
      _isProcessing = true;
      _statusMessage = 'PDF voorbereiden...';
    });

    try {
      await Future.delayed(const Duration(milliseconds: 300));
      await Printing.sharePdf(
        bytes: _gecachetePdfBytes!,
        filename: 'Offerte_CleanConnect_${widget.offerteNummer}.pdf',
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Fout bij delen: $e')),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isProcessing = false;
          _statusMessage = '';
        });
      }
    }
  }

  Future<void> _printPdf() async {
    if (_gecachetePdfBytes == null) return;
    await Printing.layoutPdf(
      onLayout: (PdfPageFormat format) async => _gecachetePdfBytes!,
      name: 'Offerte ${widget.offerteNummer}',
    );
  }

  Widget _buildModerneActiebalk() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.95),
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.1),
            blurRadius: 20,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: _isProcessing
          ? Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const SizedBox(
                  width: 24,
                  height: 24,
                  child: CircularProgressIndicator(strokeWidth: 3),
                ),
                const SizedBox(width: 16),
                Text(
                  _statusMessage,
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    color: Colors.blue,
                  ),
                ),
              ],
            )
          : Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                _buildActieKnop(
                  icon: Icons.ios_share,
                  label: 'Delen / Opslaan',
                  onTap: _deelOfSlaOp,
                  kleur: Colors.blue.shade700,
                ),
                Container(
                  width: 1,
                  height: 40,
                  color: Colors.grey.shade300,
                ),
                _buildActieKnop(
                  icon: Icons.print_outlined,
                  label: 'Afdrukken',
                  onTap: _printPdf,
                  kleur: Colors.grey.shade800,
                ),
              ],
            ),
    );
  }

  Widget _buildActieKnop({
    required IconData icon,
    required String label,
    required VoidCallback onTap,
    required Color kleur,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: kleur, size: 24),
            const SizedBox(height: 6),
            Text(
              label,
              style: TextStyle(
                color: kleur,
                fontSize: 12,
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF2F2F7),
      appBar: AppBar(
        title: Text(
          'Offerte Preview: ${widget.offerteNummer}',
          style: const TextStyle(fontWeight: FontWeight.bold),
        ),
        backgroundColor: Colors.white,
        elevation: 0,
        centerTitle: true,
      ),
      body: Stack(
        children: [
          PdfPreview(
            build: (format) => _generateAndCachePdf(),
            useActions: false,
            canChangeOrientation: false,
            canChangePageFormat: false,
            canDebug: false,
            loadingWidget: const Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  CircularProgressIndicator(),
                  SizedBox(height: 16),
                  Text(
                    'Document genereren...',
                    style: TextStyle(
                      color: Colors.grey,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
            ),
          ),
          Positioned(
            bottom: 40,
            left: MediaQuery.of(context).size.width > 600
                ? MediaQuery.of(context).size.width * 0.25
                : 20,
            right: MediaQuery.of(context).size.width > 600
                ? MediaQuery.of(context).size.width * 0.25
                : 20,
            child: _buildModerneActiebalk(),
          ),
        ],
      ),
    );
  }
}
