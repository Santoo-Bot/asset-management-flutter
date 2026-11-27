import 'package:flutter/material.dart';

import '../core/formatters.dart';

void showMessage(BuildContext context, String message) {
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(message)));
}

/// Pesan kesalahan ramah pengguna dari exception apa pun.
void showError(BuildContext context, Object error) {
  var text = error.toString();
  if (text.contains('UNIQUE constraint failed')) text = 'Data dengan nilai yang sama sudah ada';
  if (text.contains('FOREIGN KEY constraint failed')) text = 'Data masih terkait dengan data lain';
  showMessage(context, text.replaceFirst(RegExp(r'^(Exception|Bad state|Invalid argument\(s\)): '), ''));
}

Future<bool> confirm(BuildContext context, String title, String body, {String action = 'Ya'}) async {
  final ok = await showDialog<bool>(
    context: context,
    builder: (c) => AlertDialog(
      title: Text(title),
      content: Text(body),
      actions: [
        TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Batal')),
        FilledButton(onPressed: () => Navigator.pop(c, true), child: Text(action)),
      ],
    ),
  );
  return ok ?? false;
}

/// Tombol pemilih tanggal; menyimpan epoch ms (null = kosong).
class DateField extends StatelessWidget {
  const DateField({super.key, required this.label, required this.value, required this.onChanged, this.allowClear = true});
  final String label;
  final int? value;
  final ValueChanged<int?> onChanged;
  final bool allowClear;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: () async {
        final initial = value == null ? DateTime.now() : DateTime.fromMillisecondsSinceEpoch(value!);
        final picked = await showDatePicker(
          context: context,
          initialDate: initial,
          firstDate: DateTime(1990),
          lastDate: DateTime(2100),
        );
        if (picked != null) onChanged(DateTime(picked.year, picked.month, picked.day).millisecondsSinceEpoch);
      },
      child: InputDecorator(
        decoration: InputDecoration(
          labelText: label,
          border: const OutlineInputBorder(),
          suffixIcon: (allowClear && value != null)
              ? IconButton(icon: const Icon(Icons.clear), onPressed: () => onChanged(null))
              : const Icon(Icons.calendar_today, size: 18),
        ),
        child: Text(value == null ? '-' : formatDate(value)),
      ),
    );
  }
}

/// Dropdown generik dengan opsi "kosong".
class PickerField<T> extends StatelessWidget {
  const PickerField({
    super.key,
    required this.label,
    required this.value,
    required this.options,
    required this.onChanged,
    this.allowEmpty = true,
  });
  final String label;
  final T? value;
  final List<({T value, String label})> options;
  final ValueChanged<T?> onChanged;
  final bool allowEmpty;

  @override
  Widget build(BuildContext context) {
    final valid = options.any((o) => o.value == value) ? value : null;
    return DropdownButtonFormField<T>(
      value: valid,
      isExpanded: true,
      decoration: InputDecoration(labelText: label, border: const OutlineInputBorder()),
      items: [
        if (allowEmpty) DropdownMenuItem<T>(value: null, child: const Text('-')),
        for (final o in options) DropdownMenuItem<T>(value: o.value, child: Text(o.label, overflow: TextOverflow.ellipsis)),
      ],
      onChanged: onChanged,
    );
  }
}

Widget infoRow(String label, String? value) {
  return Padding(
    padding: const EdgeInsets.symmetric(vertical: 4),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(width: 130, child: Text(label, style: const TextStyle(color: Colors.grey))),
        Expanded(child: Text((value == null || value.isEmpty) ? '-' : value)),
      ],
    ),
  );
}
