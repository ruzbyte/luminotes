import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:pdfrx/pdfrx.dart';

/// One rasterized PDF page ready to be embedded as a canvas-page background.
class RasterizedPdfPage {
  RasterizedPdfPage({
    required this.png,
    required this.width,
    required this.height,
  });

  /// PNG-encoded pixels of the rendered page.
  final Uint8List png;

  /// Page size in PDF points (used to derive the canvas page aspect ratio).
  final double width;
  final double height;
}

/// Rasterizes PDF files into PNG page images using pdfrx (pdfium).
class PdfImportService {
  /// Renders every page of [filePath] to PNG at roughly [targetDpi].
  ///
  /// PDF points are 1/72 inch, so the pixel scale is `targetDpi / 72`.
  static Future<List<RasterizedPdfPage>> rasterize(
    String filePath, {
    double targetDpi = 150,
  }) async {
    final scale = targetDpi / 72.0;
    final document = await PdfDocument.openFile(filePath);
    try {
      final result = <RasterizedPdfPage>[];
      for (final page in document.pages) {
        final pixelWidth = (page.width * scale).round();
        final pixelHeight = (page.height * scale).round();
        final rendered = await page.render(
          width: pixelWidth,
          height: pixelHeight,
          fullWidth: pixelWidth.toDouble(),
          fullHeight: pixelHeight.toDouble(),
        );
        if (rendered == null) continue;
        try {
          final image = await rendered.createImage();
          final byteData =
              await image.toByteData(format: ui.ImageByteFormat.png);
          image.dispose();
          if (byteData == null) continue;
          result.add(RasterizedPdfPage(
            png: byteData.buffer.asUint8List(),
            width: page.width,
            height: page.height,
          ));
        } finally {
          rendered.dispose();
        }
      }
      return result;
    } finally {
      await document.dispose();
    }
  }
}
