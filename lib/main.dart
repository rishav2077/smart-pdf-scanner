import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_image_compress/flutter_image_compress.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:share_plus/share_plus.dart';
import 'package:signature/signature.dart';

void main() {
  runApp(const SmartPdfScannerApp());
}

class SmartPdfScannerApp extends StatelessWidget {
  const SmartPdfScannerApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: "Smart PDF Scanner",
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorSchemeSeed: Colors.indigo,
        useMaterial3: true,
      ),
      home: const HomePage(),
    );
  }
}

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  final ImagePicker picker = ImagePicker();

  final List<File> images = [];

  File? generatedPdf;
  Uint8List? signatureBytes;

  bool enableCompression = true;
  bool enableOCR = true;

  String extractedText = "";

  final SignatureController signatureController = SignatureController(
    penStrokeWidth: 3,
    penColor: Colors.black,
    exportBackgroundColor: Colors.transparent,
  );

  @override
  void dispose() {
    signatureController.dispose();
    super.dispose();
  }

  Future<void> pickFromCamera() async {
    final XFile? photo = await picker.pickImage(
      source: ImageSource.camera,
      imageQuality: 90,
    );

    if (photo != null) {
      setState(() {
        images.add(File(photo.path));
      });
    }
  }

  Future<void> pickFromGallery() async {
    final List<XFile> selectedImages = await picker.pickMultiImage(
      imageQuality: 90,
    );

    setState(() {
      images.addAll(selectedImages.map((image) => File(image.path)));
    });
  }

  Future<Uint8List> compressImage(File file) async {
    final Uint8List? compressedBytes =
        await FlutterImageCompress.compressWithFile(
      file.absolute.path,
      quality: 55,
      minWidth: 1200,
      minHeight: 1600,
      format: CompressFormat.jpeg,
    );

    return compressedBytes ?? await file.readAsBytes();
  }

  Future<void> extractTextFromImages() async {
    if (images.isEmpty) {
      showMessage("Please add images first");
      return;
    }

    final TextRecognizer textRecognizer =
        TextRecognizer(script: TextRecognitionScript.latin);

    String allText = "";

    try {
      for (final File image in images) {
        final InputImage inputImage = InputImage.fromFile(image);
        final RecognizedText recognizedText =
            await textRecognizer.processImage(inputImage);

        allText += "${recognizedText.text}\n\n";
      }

      setState(() {
        extractedText = allText.trim();
      });

      showMessage("OCR text extracted successfully");
    } finally {
      await textRecognizer.close();
    }
  }

  Future<void> openSignaturePad() async {
    await showDialog(
      context: context,
      builder: (_) {
        return AlertDialog(
          title: const Text("Add E-Signature"),
          content: SizedBox(
            height: 260,
            width: double.maxFinite,
            child: Container(
              decoration: BoxDecoration(
                border: Border.all(color: Colors.black26),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Signature(
                controller: signatureController,
                backgroundColor: Colors.white,
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () {
                signatureController.clear();
              },
              child: const Text("Clear"),
            ),
            FilledButton(
              onPressed: () async {
                final Uint8List? data =
                    await signatureController.toPngBytes();

                if (data != null) {
                  setState(() {
                    signatureBytes = data;
                  });

                  if (mounted) {
                    Navigator.pop(context);
                    showMessage("Signature saved");
                  }
                }
              },
              child: const Text("Save"),
            ),
          ],
        );
      },
    );
  }

  Future<void> createPdf() async {
    if (images.isEmpty) {
      showMessage("Please add images first");
      return;
    }

    if (enableOCR) {
      await extractTextFromImages();
    }

    final pw.Document pdf = pw.Document();

    final pw.MemoryImage? signatureImage =
        signatureBytes != null ? pw.MemoryImage(signatureBytes!) : null;

    for (int i = 0; i < images.length; i++) {
      final Uint8List imageBytes = enableCompression
          ? await compressImage(images[i])
          : await images[i].readAsBytes();

      final pw.MemoryImage pageImage = pw.MemoryImage(imageBytes);

      pdf.addPage(
        pw.Page(
          margin: const pw.EdgeInsets.all(24),
          build: (context) {
            return pw.Stack(
              children: [
                pw.Center(
                  child: pw.Image(
                    pageImage,
                    fit: pw.BoxFit.contain,
                  ),
                ),

                pw.Center(
                  child: pw.Opacity(
                    opacity: 0.06,
                    child: pw.Transform.rotate(
                      angle: -0.5,
                      child: pw.Text(
                        "Rishav Paul",
                        style: pw.TextStyle(
                          fontSize: 60,
                          fontWeight: pw.FontWeight.bold,
                        ),
                      ),
                    ),
                  ),
                ),

                if (signatureImage != null)
                  pw.Positioned(
                    bottom: 35,
                    right: 10,
                    child: pw.Column(
                      children: [
                        pw.Image(
                          signatureImage,
                          width: 130,
                          height: 55,
                        ),
                        pw.Text(
                          "E-Signature",
                          style: const pw.TextStyle(fontSize: 8),
                        ),
                      ],
                    ),
                  ),

                pw.Positioned(
                  bottom: 0,
                  left: 0,
                  right: 0,
                  child: pw.Text(
                    "Created with Smart PDF Scanner | Developer: Rishav Paul",
                    textAlign: pw.TextAlign.center,
                    style: const pw.TextStyle(fontSize: 9),
                  ),
                ),
              ],
            );
          },
        ),
      );
    }

    if (extractedText.isNotEmpty) {
      pdf.addPage(
        pw.MultiPage(
          margin: const pw.EdgeInsets.all(32),
          build: (context) {
            return [
              pw.Text(
                "OCR Extracted Text",
                style: pw.TextStyle(
                  fontSize: 22,
                  fontWeight: pw.FontWeight.bold,
                ),
              ),
              pw.SizedBox(height: 16),
              pw.Text(
                extractedText,
                style: const pw.TextStyle(fontSize: 11),
              ),
              pw.SizedBox(height: 20),
              pw.Text(
                "Developer: Rishav Paul",
                style: pw.TextStyle(
                  fontWeight: pw.FontWeight.bold,
                ),
              ),
            ];
          },
        ),
      );
    }

    final Directory directory = await getApplicationDocumentsDirectory();

    final File file = File(
      "${directory.path}/SmartScanner_${DateTime.now().millisecondsSinceEpoch}.pdf",
    );

    await file.writeAsBytes(await pdf.save());

    setState(() {
      generatedPdf = file;
    });

    showMessage("PDF created successfully");
  }

  Future<void> previewPdf() async {
    if (generatedPdf == null) {
      showMessage("Create PDF first");
      return;
    }

    final Uint8List bytes = await generatedPdf!.readAsBytes();

    await Printing.layoutPdf(
      onLayout: (_) async => bytes,
    );
  }

  Future<void> sharePdf() async {
    if (generatedPdf == null) {
      showMessage("Create PDF first");
      return;
    }

    await Share.shareXFiles(
      [XFile(generatedPdf!.path)],
      text: "PDF created by Smart PDF Scanner | Developer: Rishav Paul",
    );
  }

  void removeImage(int index) {
    setState(() {
      images.removeAt(index);
    });
  }

  void clearAll() {
    setState(() {
      images.clear();
      generatedPdf = null;
      extractedText = "";
      signatureBytes = null;
      signatureController.clear();
    });
  }

  void showOCRText() {
    if (extractedText.isEmpty) {
      showMessage("No OCR text available");
      return;
    }

    showDialog(
      context: context,
      builder: (_) {
        return AlertDialog(
          title: const Text("Extracted OCR Text"),
          content: SingleChildScrollView(
            child: Text(extractedText),
          ),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.pop(context);
              },
              child: const Text("Close"),
            ),
          ],
        );
      },
    );
  }

  void showMessage(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }

  Widget featureCard() {
    return Container(
      margin: const EdgeInsets.all(16),
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(22),
        gradient: const LinearGradient(
          colors: [
            Colors.indigo,
            Colors.blueAccent,
          ],
        ),
      ),
      child: const Column(
        children: [
          Icon(
            Icons.document_scanner,
            size: 52,
            color: Colors.white,
          ),
          SizedBox(height: 10),
          Text(
            "Smart PDF Scanner",
            style: TextStyle(
              color: Colors.white,
              fontSize: 22,
              fontWeight: FontWeight.bold,
            ),
          ),
          SizedBox(height: 6),
          Text(
            "Scan • Gallery • Compress • OCR • E-Sign • Share",
            textAlign: TextAlign.center,
            style: TextStyle(color: Colors.white70),
          ),
          SizedBox(height: 6),
          Text(
            "Developer: Rishav Paul",
            style: TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }

  Widget actionButtons() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: Wrap(
        spacing: 10,
        runSpacing: 10,
        alignment: WrapAlignment.center,
        children: [
          ElevatedButton.icon(
            onPressed: pickFromCamera,
            icon: const Icon(Icons.camera_alt),
            label: const Text("Scan"),
          ),
          ElevatedButton.icon(
            onPressed: pickFromGallery,
            icon: const Icon(Icons.photo_library),
            label: const Text("Gallery"),
          ),
          ElevatedButton.icon(
            onPressed: openSignaturePad,
            icon: const Icon(Icons.draw),
            label: const Text("E-Sign"),
          ),
          ElevatedButton.icon(
            onPressed: extractTextFromImages,
            icon: const Icon(Icons.text_fields),
            label: const Text("OCR"),
          ),
        ],
      ),
    );
  }

  Widget settingsSection() {
    return Column(
      children: [
        SwitchListTile(
          title: const Text("Compress PDF"),
          subtitle: const Text("Reduce PDF size for easy sharing"),
          value: enableCompression,
          onChanged: (value) {
            setState(() {
              enableCompression = value;
            });
          },
        ),
        SwitchListTile(
          title: const Text("OCR Text Extraction"),
          subtitle: const Text("Add extracted text page inside PDF"),
          value: enableOCR,
          onChanged: (value) {
            setState(() {
              enableOCR = value;
            });
          },
        ),
      ],
    );
  }

  Widget imageGrid() {
    if (images.isEmpty) {
      return const Center(
        child: Text("No images selected yet"),
      );
    }

    return GridView.builder(
      padding: const EdgeInsets.all(12),
      itemCount: images.length,
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        crossAxisSpacing: 12,
        mainAxisSpacing: 12,
      ),
      itemBuilder: (context, index) {
        return Stack(
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(16),
              child: Image.file(
                images[index],
                fit: BoxFit.cover,
                width: double.infinity,
                height: double.infinity,
              ),
            ),
            Positioned(
              top: 6,
              right: 6,
              child: CircleAvatar(
                backgroundColor: Colors.black54,
                child: IconButton(
                  icon: const Icon(
                    Icons.close,
                    color: Colors.white,
                  ),
                  onPressed: () {
                    removeImage(index);
                  },
                ),
              ),
            ),
            Positioned(
              bottom: 6,
              left: 6,
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 8,
                  vertical: 4,
                ),
                decoration: BoxDecoration(
                  color: Colors.black54,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  "Page ${index + 1}",
                  style: const TextStyle(color: Colors.white),
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  Widget bottomControls() {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        children: [
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: createPdf,
              icon: const Icon(Icons.picture_as_pdf),
              label: const Text("Create Professional PDF"),
            ),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: previewPdf,
                  icon: const Icon(Icons.preview),
                  label: const Text("Preview"),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: sharePdf,
                  icon: const Icon(Icons.share),
                  label: const Text("Share"),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          OutlinedButton.icon(
            onPressed: showOCRText,
            icon: const Icon(Icons.article),
            label: const Text("View OCR Text"),
          ),
          const SizedBox(height: 8),
          Text(
            generatedPdf == null
                ? "No PDF created yet"
                : "PDF Ready: ${generatedPdf!.path.split('/').last}",
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 12),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("Smart PDF Scanner"),
        centerTitle: true,
        actions: [
          IconButton(
            onPressed: clearAll,
            icon: const Icon(Icons.delete_outline),
          ),
        ],
      ),
      body: Column(
        children: [
          featureCard(),
          actionButtons(),
          settingsSection(),
          Expanded(
            child: imageGrid(),
          ),
          bottomControls(),
        ],
      ),
    );
  }
}
