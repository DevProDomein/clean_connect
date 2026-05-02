Future<void> downloadStringAsFile({
  required String filename,
  required String content,
  String mimeType = 'application/octet-stream',
}) async {
  throw UnsupportedError('File download is only implemented for web right now.');
}

