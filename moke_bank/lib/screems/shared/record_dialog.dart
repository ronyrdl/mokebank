import 'package:flutter/material.dart';

Future<void> showRecord(
  BuildContext context,
  String title,
  Map<String, Object?> fields,
) => showDialog<void>(
  context: context,
  builder: (context) => AlertDialog(
    title: Text(title),
    content: SingleChildScrollView(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (final field in fields.entries)
            ListTile(
              title: Text(field.key),
              subtitle: Text('${field.value ?? '—'}'),
            ),
        ],
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Cerrar'),
      ),
    ],
  ),
);
