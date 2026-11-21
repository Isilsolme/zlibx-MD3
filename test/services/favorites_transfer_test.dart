import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:olib_api_plugin/olib_api_plugin.dart';
import 'package:zlibx/services/favorites_transfer.dart';

void main() {
  Book book(int id, {String? title, String? author}) => Book(
    id: id,
    title: title ?? 'Book $id',
    author: author,
    hash: 'hash-$id',
    cover: 'https://cover/$id.jpg',
    extension: 'epub',
  );

  test(
    'encode/decode round-trips metadata and keeps the newest-first order',
    () {
      final json = encodeFavoritesExport([
        book(3),
        book(1, author: 'A'),
        book(2),
      ], exportedAt: DateTime.utc(2026, 11, 21));
      final decoded = decodeFavoritesExport(json);
      expect(decoded.map((b) => b.id), [3, 1, 2]);
      expect(decoded[1].author, 'A');
      expect(decoded.first.hash, 'hash-3');
      expect(decoded.first.extension, 'epub');
    },
  );

  test('duplicates are exported once', () {
    final json = encodeFavoritesExport([book(1), book(1), book(2)]);
    expect(decodeFavoritesExport(json).map((b) => b.id), [1, 2]);
  });

  test('a bare array of ids is accepted', () {
    final books = decodeFavoritesExport(
      jsonEncode([
        {'id': 5, 'title': 'Five'},
        {'id': '6'},
        {'id': 'not-a-number'},
      ]),
    );
    expect(books.map((b) => b.id), [5, 6]);
    expect(books.first.title, 'Five');
  });

  test('malformed rows are skipped instead of failing the file', () {
    final books = decodeFavoritesExport(
      jsonEncode({
        'format': FavoritesExport.formatTag,
        'version': 1,
        'books': [
          {'id': 1},
          'garbage',
          {'title': 'no id'},
          {'id': 2},
        ],
      }),
    );
    expect(books.map((b) => b.id), [1, 2]);
  });

  test('a foreign document is rejected', () {
    expect(
      () => decodeFavoritesExport(jsonEncode({'format': 'something-else'})),
      throwsA(isA<FormatException>()),
    );
    expect(
      () => decodeFavoritesExport('not json'),
      throwsA(isA<FormatException>()),
    );
    expect(
      () => decodeFavoritesExport(jsonEncode({'version': 1})),
      throwsA(isA<FormatException>()),
    );
  });

  test('a newer export version is refused', () {
    expect(
      () => decodeFavoritesExport(
        jsonEncode({
          'format': FavoritesExport.formatTag,
          'version': FavoritesExport.currentVersion + 1,
          'books': [],
        }),
      ),
      throwsA(isA<FormatException>()),
    );
  });
}
