import 'package:flutter/material.dart';

import 'package:note_vision/features/musicXML/musicxml_import_exception.dart';
import 'package:note_vision/features/musicXML/musicxml_importer.dart';
import 'package:note_vision/features/musicXML/musicxml_import_result.dart';

/// Dev test screen for manually verifying MusicXML import.
class DevTestScreen extends StatefulWidget {
  const DevTestScreen({super.key});

  @override
  State<DevTestScreen> createState() => _DevTestScreenState();
}

class _DevTestScreenState extends State<DevTestScreen> {
  final MusicXmlImporter _importer = MusicXmlImporter();

  bool _loading = false;
  String? _fileName;
  String? _rawPreview; // first 300 chars of raw XML
  bool? _parseSuccess;
  String? _rootTagName;
  String? _parseError;
  String? _parsedPreview; //
  String? _errorMessage;

  Future<void> _handleImport() async {
    setState(() {
      _loading = true;
      _fileName = null;
      _rawPreview = null;
      _parseSuccess = null;
      _rootTagName = null;
      _parseError = null;
      _parsedPreview = null;
      _errorMessage = null;
    });

    try {
      final MusicXmlImportResult? result = await _importer.pickAndRead();

      if (result == null) {
        // User cancelled — no error, just reset.
        setState(() => _loading = false);
        return;
      }

      final prettyXml = result.parseResult.document?.toXmlString(pretty: true);

      setState(() {
        _fileName = result.fileName;
        _rawPreview = result.xmlContent.length > 300
            ? '${result.xmlContent.substring(0, 300)}…'
            : result.xmlContent;
        _parseSuccess = result.parseResult.success;
        _rootTagName = result.parseResult.rootTagName;
        _parseError = result.parseResult.errorMessage;
        if (prettyXml != null) {
          _parsedPreview = prettyXml.length > 300
              ? '${prettyXml.substring(0, 300)}…'
              : prettyXml;
        }
      });
    } on MusicXmlImportException catch (e) {
      setState(() => _errorMessage = e.message);
    } catch (e) {
      setState(() => _errorMessage = 'Unexpected error: $e');
    } finally {
      setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('MusicXML Import — Dev Test')),
      body: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            ElevatedButton.icon(
              onPressed: _loading ? null : _handleImport,
              icon: const Icon(Icons.file_open),
              label: Text(_loading ? 'Importing…' : 'Import MusicXML File'),
            ),
            const SizedBox(height: 24),
            if (_loading) const Center(child: CircularProgressIndicator()),
            if (_errorMessage != null) ...[
              const Text(
                'Error',
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  color: Colors.red,
                ),
              ),
              const SizedBox(height: 8),
              Text(_errorMessage!, style: const TextStyle(color: Colors.red)),
            ],
            if (_fileName != null) ...[
              Text(
                'File: $_fileName',
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              Text('Parse success: ${_parseSuccess == true ? 'Yes' : 'No'}'),
              if (_rootTagName != null) Text('Root tag: $_rootTagName'),
              if (_parseError != null && _parseSuccess == false)
                Text(
                  'Parse error: $_parseError',
                  style: const TextStyle(color: Colors.red),
                ),
              const SizedBox(height: 12),
              const Text('Raw XML Preview (first 300 chars):'),
              const SizedBox(height: 8),
              Container(
                constraints: const BoxConstraints(maxHeight: 140),
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.grey.shade100,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.grey.shade300),
                ),
                child: SingleChildScrollView(
                  child: Text(
                    _rawPreview ?? '',
                    style: const TextStyle(
                      fontFamily: 'monospace',
                      fontSize: 12,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              const Text('Parsed XML Preview (first 300 chars):'),
              const SizedBox(height: 8),
              Expanded(
                child: Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.grey.shade100,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.grey.shade300),
                  ),
                  child: SingleChildScrollView(
                    child: Text(
                      _parsedPreview ?? '(No parsed XML available)',
                      style: const TextStyle(
                        fontFamily: 'monospace',
                        fontSize: 12,
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
