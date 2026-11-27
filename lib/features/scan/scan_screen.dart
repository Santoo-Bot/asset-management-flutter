import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import '../../app/providers.dart';
import '../../ui/common.dart';

/// Masukan kode yang sama dipakai di Scan dan Opname:
/// Android → kamera (`mobile_scanner`); Windows → pemindai USB (mode keyboard) atau ketik manual.
class ScanInput extends StatefulWidget {
  const ScanInput({super.key, required this.onCode, this.cameraHeight = 240});
  final Future<void> Function(String code) onCode;
  final double cameraHeight;

  @override
  State<ScanInput> createState() => _ScanInputState();
}

class _ScanInputState extends State<ScanInput> {
  final _text = TextEditingController();
  final _focus = FocusNode();
  String? _last;
  DateTime _lastAt = DateTime.fromMillisecondsSinceEpoch(0);

  @override
  void dispose() {
    _text.dispose();
    _focus.dispose();
    super.dispose();
  }

  Future<void> _submit(String raw) async {
    final code = raw.trim();
    if (code.isEmpty) return;
    // Kamera mendeteksi terus-menerus; abaikan kode sama dalam 2 detik.
    final now = DateTime.now();
    if (code == _last && now.difference(_lastAt) < const Duration(seconds: 2)) return;
    _last = code;
    _lastAt = now;
    _text.clear();
    await widget.onCode(code);
    if (mounted) _focus.requestFocus();
  }

  @override
  Widget build(BuildContext context) {
    return Column(mainAxisSize: MainAxisSize.min, children: [
      if (Platform.isAndroid)
        SizedBox(
          height: widget.cameraHeight,
          child: ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: MobileScanner(
              onDetect: (capture) {
                final value = capture.barcodes.map((b) => b.rawValue).whereType<String>().firstOrNull;
                if (value != null) _submit(value);
              },
            ),
          ),
        ),
      const SizedBox(height: 12),
      TextField(
        controller: _text,
        focusNode: _focus,
        autofocus: !Platform.isAndroid,
        decoration: InputDecoration(
          labelText: Platform.isAndroid ? 'Atau ketik kode' : 'Pindai dengan alat USB atau ketik kode, lalu Enter',
          prefixIcon: const Icon(Icons.qr_code),
          border: const OutlineInputBorder(),
        ),
        onSubmitted: _submit,
      ),
    ]);
  }
}

class ScanScreen extends ConsumerWidget {
  const ScanScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      appBar: AppBar(title: const Text('Scan aset'), automaticallyImplyLeading: false),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: ScanInput(onCode: (code) async {
          final id = await ref.read(assetRepositoryProvider).idByCode(code);
          if (!context.mounted) return;
          if (id != null) {
            context.go('/assets/$id');
          } else {
            showMessage(context, 'Kode "$code" tidak terdaftar');
          }
        }),
      ),
    );
  }
}
