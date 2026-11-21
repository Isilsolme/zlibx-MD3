import 'dart:convert';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:olib_api_plugin/olib_api_plugin.dart';
import 'package:zlibx/providers/download_provider.dart';
import 'package:zlibx/services/hive_service.dart';

/// Recovery of in-flight downloads after the process was killed: the
/// persisted task record plus the .part bytes on disk must come back as
/// an interrupted task (Retry resumes with Range), while a record whose
/// bytes are gone is dropped.
void main() {
  late Directory dir;
  late Box<dynamic> box;

  setUpAll(() async {
    dir = await Directory.systemTemp.createTemp('download_recovery');
    Hive.init(dir.path);
    box = await Hive.openBox(HiveService.settingsBoxName);
  });

  setUp(() async {
    await box.clear();
  });

  tearDownAll(() async {
    await Hive.close();
    await dir.delete(recursive: true);
  });

  Book book(int id, {String? hash}) => Book(
    id: id,
    title: 'Book $id',
    author: 'Author $id',
    hash: hash ?? 'hash-$id',
    cover: 'https://cover/$id.jpg',
    extension: 'epub',
  );

  Future<DownloadTask?> restoredTask(
    Book entry, {
    required String partPath,
    bool external = false,
  }) async {
    await File(partPath).writeAsString('partial bytes');
    await box.put(
      'download_tasks',
      jsonEncode({
        entry.id.toString(): {
          'book': entry.toJson(),
          'partPath': partPath,
          'progress': 0.42,
          'external': external,
        },
      }),
    );
    final container = ProviderContainer();
    addTearDown(container.dispose);
    container.listen(downloadProvider, (_, _) {});
    await container.read(downloadProvider.notifier).ready;
    for (final task in container.read(downloadProvider)) {
      if (task.id == entry.id.toString()) return task;
    }
    return null;
  }

  test('a z-library partial comes back as an interrupted, retryable task',
      () async {
    final task = await restoredTask(
      book(42),
      partPath: '${dir.path}/Book-42.epub.part',
    );
    expect(task, isNotNull);
    expect(task!.status, DownloadStatus.error);
    expect(task.interrupted, isTrue);
    expect(task.needsFreshLink, isFalse);
    expect(task.canRetry, isTrue);
    expect(task.progress, 0.42);
    expect(task.book.title, 'Book 42');
  });

  test('an external partial asks for a fresh link instead of retrying blindly',
      () async {
    final task = await restoredTask(
      book(43, hash: '0123456789abcdef0123456789abcdef'),
      partPath: '${dir.path}/Book-43.epub.part',
      external: true,
    );
    expect(task, isNotNull);
    expect(task!.interrupted, isTrue);
    expect(task.external, isTrue);
    expect(task.needsFreshLink, isTrue);
    // The old direct link has expired; the UI sends the user back to the
    // detail page, where the new download resumes the same .part.
    expect(task.canRetry, isFalse);
  });

  test('a record whose bytes are gone is dropped', () async {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    await box.put(
      'download_tasks',
      jsonEncode({
        '44': {
          'book': book(44).toJson(),
          'partPath': '${dir.path}/missing.epub.part',
          'progress': 0.5,
          'external': false,
        },
      }),
    );
    container.listen(downloadProvider, (_, _) {});
    await container.read(downloadProvider.notifier).ready;
    expect(
      container.read(downloadProvider).where((t) => t.id == '44'),
      isEmpty,
    );
    expect(box.get('download_tasks'), isNull);
  });
}
