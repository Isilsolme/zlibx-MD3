import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../services/favorites_transfer.dart';
import '../services/storage_service.dart';
import '../utils/app_log.dart';
import '../utils/diagnostics.dart';
import 'zlibrary_provider.dart';

/// Progress of one favorites import run.
class FavoritesImportState {
  const FavoritesImportState({
    this.running = false,
    this.done = 0,
    this.total = 0,
    this.imported = 0,
    this.failed = 0,
    this.error,
  });

  final bool running;
  final int done;
  final int total;
  final int imported;
  final int failed;

  /// Set when the run could not start or aborted (e.g. signed out).
  final String? error;

  bool get finished => !running && total > 0;

  FavoritesImportState copyWith({
    bool? running,
    int? done,
    int? total,
    int? imported,
    int? failed,
    String? error,
  }) => FavoritesImportState(
    running: running ?? this.running,
    done: done ?? this.done,
    total: total ?? this.total,
    imported: imported ?? this.imported,
    failed: failed ?? this.failed,
    error: error ?? this.error,
  );
}

/// Re-adds exported favorites to the signed-in account, four requests at
/// a time (the site's save endpoint is a small GET; 4 keeps a move of a
/// few hundred books under a couple of seconds without hammering the
/// mirror). Failures are counted per row, never thrown: a single bad id
/// must not abort the whole import.
class FavoritesImportNotifier extends Notifier<FavoritesImportState> {
  static const int concurrency = 4;

  @override
  FavoritesImportState build() => const FavoritesImportState();

  Future<void> run(List<FavoritesExportBook> books) async {
    if (state.running) return;
    final ids = <String>[];
    final seen = <int>{};
    for (final book in books) {
      if (book.id <= 0 || !seen.add(book.id)) continue;
      ids.add(book.id.toString());
    }
    if (ids.isEmpty) {
      state = const FavoritesImportState();
      return;
    }

    state = FavoritesImportState(running: true, total: ids.length);
    var next = 0;
    var imported = 0;
    var failed = 0;

    Future<void> worker() async {
      while (true) {
        final index = next++;
        if (index >= ids.length) return;
        final ok = await _importOne(ids[index]);
        if (ok) {
          imported++;
        } else {
          failed++;
        }
        state = state.copyWith(
          done: imported + failed,
          imported: imported,
          failed: failed,
        );
      }
    }

    await Future.wait(<Future<void>>[
      for (var i = 0; i < concurrency; i++) worker(),
    ]);
    state = state.copyWith(running: false);
  }

  Future<bool> _importOne(String bookId) async {
    try {
      final response = await ref.read(zlibraryApiProvider).saveBook(bookId);
      if (!response.success) {
        AppLog.report(
          'favorites import save failed: ${response.error ?? 'unknown'}',
          tag: 'favorites_import',
        );
        return false;
      }
      await ref.read(storageServiceProvider).addFavorite(bookId);
      return true;
    } catch (error) {
      logIgnored('favorites_import', error);
      return false;
    }
  }
}

final favoritesImportProvider =
    NotifierProvider<FavoritesImportNotifier, FavoritesImportState>(
      FavoritesImportNotifier.new,
    );
