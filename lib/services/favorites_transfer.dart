import 'dart:convert';

import 'package:olib_api_plugin/olib_api_plugin.dart';

/// One favorite in the portable export (the site's saved-books row).
///
/// The id is what import actually needs; the metadata is for the user's
/// own record and for a readable diff — it is never trusted for lookups.
class FavoritesExportBook {
  const FavoritesExportBook({
    required this.id,
    this.hash,
    this.title,
    this.author,
    this.cover,
    this.extension,
  });

  final int id;
  final String? hash;
  final String? title;
  final String? author;
  final String? cover;
  final String? extension;

  Map<String, dynamic> toJson() => <String, dynamic>{
    'id': id,
    if (hash != null && hash!.isNotEmpty) 'hash': hash,
    if (title != null && title!.isNotEmpty) 'title': title,
    if (author != null && author!.isNotEmpty) 'author': author,
    if (cover != null && cover!.isNotEmpty) 'cover': cover,
    if (extension != null && extension!.isNotEmpty) 'extension': extension,
  };

  static FavoritesExportBook? tryParse(Object? raw) {
    if (raw is! Map) return null;
    final idRaw = raw['id'];
    final int? id = idRaw is int ? idRaw : int.tryParse('$idRaw');
    if (id == null || id <= 0) return null;
    String? text(String key) {
      final value = raw[key];
      return value is String && value.trim().isNotEmpty ? value.trim() : null;
    }

    return FavoritesExportBook(
      id: id,
      hash: text('hash'),
      title: text('title'),
      author: text('author'),
      cover: text('cover'),
      extension: text('extension'),
    );
  }
}

/// The export envelope. Versioned so a future format can migrate instead
/// of silently mis-reading an old file.
class FavoritesExport {
  const FavoritesExport({
    required this.version,
    required this.exportedAt,
    required this.books,
  });

  static const int currentVersion = 1;
  static const String formatTag = 'zlibx-favorites';

  final int version;
  final DateTime exportedAt;
  final List<FavoritesExportBook> books;

  Map<String, dynamic> toJson() => <String, dynamic>{
    'format': formatTag,
    'version': version,
    'exportedAt': exportedAt.toUtc().toIso8601String(),
    'books': [for (final book in books) book.toJson()],
  };
}

/// Serializes [books] into the portable JSON document, newest first as
/// the server lists them.
String encodeFavoritesExport(List<Book> books, {DateTime? exportedAt}) {
  final seen = <int>{};
  final entries = <FavoritesExportBook>[];
  for (final book in books) {
    if (!seen.add(book.id)) continue;
    entries.add(
      FavoritesExportBook(
        id: book.id,
        hash: book.hash,
        title: book.title,
        author: book.author,
        cover: book.cover,
        extension: book.extension,
      ),
    );
  }
  return const JsonEncoder.withIndent('  ').convert(
    FavoritesExport(
      version: FavoritesExport.currentVersion,
      exportedAt: exportedAt ?? DateTime.now().toUtc(),
      books: entries,
    ).toJson(),
  );
}

/// Parses an export document (or a bare array of {id: ...} entries).
///
/// Throws [FormatException] when the document is not a favorites export
/// at all; individual malformed rows are skipped so one bad entry does
/// not make the whole file unusable.
List<FavoritesExportBook> decodeFavoritesExport(String source) {
  Object? decoded;
  try {
    decoded = jsonDecode(source);
  } on FormatException {
    throw const FormatException('not JSON');
  }

  final Object? rawBooks;
  if (decoded is Map) {
    final format = decoded['format'];
    if (format != null && format != FavoritesExport.formatTag) {
      throw const FormatException('not a zlibx favorites export');
    }
    final version = decoded['version'];
    if (version is int && version > FavoritesExport.currentVersion) {
      throw const FormatException('export made by a newer app version');
    }
    rawBooks = decoded['books'];
  } else {
    rawBooks = decoded;
  }
  if (rawBooks is! List) {
    throw const FormatException('missing books list');
  }

  final seen = <int>{};
  final books = <FavoritesExportBook>[];
  for (final row in rawBooks) {
    final book = FavoritesExportBook.tryParse(row);
    if (book == null || !seen.add(book.id)) continue;
    books.add(book);
  }
  return books;
}
