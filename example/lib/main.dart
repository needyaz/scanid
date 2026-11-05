import 'dart:io';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:scanid/scanid.dart';

void main() {
  runApp(const MyApp());
}

class MyApp extends StatefulWidget {
  const MyApp({super.key});

  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> {
  final CaptureService _capture = const PlatformCaptureService();
  final _picker = ImagePicker();
  String _status = 'Pick a photo of a driver\'s license or passport page.';

  Future<void> _pickAndScan() async {
    final picked = await _picker.pickImage(source: ImageSource.gallery);
    if (picked == null) return;
    final bytes = await File(picked.path).readAsBytes();

    setState(() => _status = 'Scanning on-device…');

    final barcodes = await _capture.recognizeBarcodes(bytes);
    final aamva = barcodes
        .map(Aamva.parse)
        .firstWhere((f) => f != null, orElse: () => null);
    if (aamva != null) {
      setState(() => _status = 'AAMVA driver\'s-license barcode:\n$aamva');
      return;
    }

    final ocr = await _capture.recognize(bytes);
    final mrz = Mrz.parse(ocr.fullText);
    if (mrz != null) {
      setState(() => _status = 'MRZ passport/ID:\n'
          '${mrz.fullName}, ${mrz.issuingCountry}\n'
          'number: ${mrz.documentNumber} (valid: ${mrz.numberValid})\n'
          'born: ${mrz.dateOfBirth}, expires: ${mrz.expiryDate}');
      return;
    }

    setState(() => _status = ocr.fullText.isEmpty
        ? 'No text, barcode, or MRZ found.'
        : 'Recognized text (no AAMVA/MRZ match):\n${ocr.fullText}');
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      home: Scaffold(
        appBar: AppBar(title: const Text('scanid example')),
        body: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(child: SingleChildScrollView(child: Text(_status))),
              const SizedBox(height: 16),
              ElevatedButton(
                onPressed: _pickAndScan,
                child: const Text('Pick photo & scan'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
