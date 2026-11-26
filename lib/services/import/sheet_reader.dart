import 'dart:convert';
import 'dart:typed_data';

import 'package:csv/csv.dart';
import 'package:excel/excel.dart';

/// A spreadsheet loaded as plain cells: String, num, DateTime, bool or null.
class SheetData {
  const SheetData({required this.name, required this.rows, this.otherSheets = const []});

  final String name;
  final List<List<Object?>> rows;

  /// Other sheets in the workbook, in case the data is not on the first one.
  final List<String> otherSheets;
}

/// A file the importer can't read, with a message for the user.
class UnsupportedFileException implements Exception {
  UnsupportedFileException(this.message);
  final String message;
  @override
  String toString() => message;
}

/// Turns an .xlsx or .csv file into rows of cells.
class SheetReader {
  const SheetReader();

  SheetData read(String fileName, Uint8List bytes, {String? sheetName}) {
    final ext = fileName.toLowerCase().split('.').last;
    switch (ext) {
      case 'csv':
      case 'txt':
        return SheetData(name: fileName, rows: readCsv(bytes));
      case 'xlsx':
        return readXlsx(bytes, sheetName: sheetName);
      case 'xls':
        throw UnsupportedFileException(
          'This is an old .xls file. Open it in Excel or Google Sheets and save it as .xlsx or .csv, then import that.',
        );
      default:
        throw UnsupportedFileException('Pick an .xlsx or .csv file.');
    }
  }

  List<List<Object?>> readCsv(Uint8List bytes) {
    var text = utf8.decode(bytes, allowMalformed: true);
    if (text.startsWith('﻿')) text = text.substring(1);
    final rows = Csv().decode(text);
    return [
      for (final r in rows) [for (final c in r) _csvCell(c)],
    ];
  }

  Object? _csvCell(Object? c) {
    if (c == null) return null;
    final s = c.toString().trim();
    return s.isEmpty ? null : s;
  }

  /// Reads the named sheet, or else the sheet with the most rows.
  SheetData readXlsx(Uint8List bytes, {String? sheetName}) {
    final Excel book;
    try {
      book = Excel.decodeBytes(bytes);
    } catch (_) {
      throw UnsupportedFileException('This file could not be opened as an Excel workbook.');
    }
    if (book.tables.isEmpty) throw UnsupportedFileException('The workbook has no sheets.');
    final names = book.tables.keys.toList();
    final chosen = sheetName != null && book.tables.containsKey(sheetName)
        ? sheetName
        : names.reduce((a, b) => book.tables[b]!.maxRows > book.tables[a]!.maxRows ? b : a);
    final sheet = book.tables[chosen]!;
    final rows = [
      for (final r in sheet.rows) [for (final c in r) cellValue(c?.value)],
    ];
    return SheetData(
      name: chosen,
      rows: rows,
      otherSheets: [
        for (final n in names)
          if (n != chosen) n,
      ],
    );
  }

  static Object? cellValue(CellValue? v) => switch (v) {
    null => null,
    TextCellValue() => _blankToNull(v.value.toString()),
    IntCellValue() => v.value,
    DoubleCellValue() => v.value,
    BoolCellValue() => v.value,
    DateCellValue() => v.asDateTimeLocal(),
    DateTimeCellValue() => v.asDateTimeLocal(),
    TimeCellValue() => '${v.hour.toString().padLeft(2, '0')}:${v.minute.toString().padLeft(2, '0')}',
    FormulaCellValue() => null,
  };

  static String? _blankToNull(String s) {
    final t = s.trim();
    return t.isEmpty ? null : t;
  }
}
