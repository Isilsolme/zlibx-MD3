import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:olib_api_plugin/olib_api_plugin.dart';
import 'package:zlibx/providers/favorites_transfer_provider.dart';
import 'package:zlibx/providers/zlibrary_provider.dart';
import 'package:zlibx/services/favorites_transfer.dart';
import 'package:zlibx/services/storage_service.dart';

class _FakeApi implements ZLibraryApi {
  _FakeApi({this.failIds = const {}});

  final Set<int> failIds;
  final List<String> savedIds = [];
  int inFlight = 0;
  int maxInFlight = 0;

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnsupportedError('unexpected: ${invocation.memberName}');

  @override
  Future<ApiResponse<void>> saveBook(String bookId) async {
    inFlight++;
    if (inFlight > maxInFlight) maxInFlight = inFlight;
    await Future<void>.delayed(const Duration(milliseconds: 10));
    inFlight--;
    savedIds.add(bookId);
    if (failIds.contains(int.parse(bookId))) {
      return ApiResponse.fail('save failed');
    }
    return ApiResponse.ok(null);
  }
}

class _FakeStorage extends StorageService {
  final List<String> added = [];

  @override
  Future<void> addFavorite(String bookId) async {
    added.add(bookId);
  }
}

FavoritesExportBook entry(int id) => FavoritesExportBook(id: id);

void main() {
  test('imports every id exactly once, four at a time', () async {
    final api = _FakeApi();
    final storage = _FakeStorage();
    final container = ProviderContainer(
      overrides: [
        zlibraryApiProvider.overrideWithValue(api),
        storageServiceProvider.overrideWithValue(storage),
      ],
    );
    addTearDown(container.dispose);

    await container.read(favoritesImportProvider.notifier).run([
      for (var i = 1; i <= 12; i++) entry(i),
      entry(3),
    ]);

    expect(api.savedIds.toSet(), {for (var i = 1; i <= 12; i++) i.toString()});
    expect(api.savedIds.length, 12); // deduplicated
    expect(storage.added.toSet(), api.savedIds.toSet());
    expect(api.maxInFlight, FavoritesImportNotifier.concurrency);

    final state = container.read(favoritesImportProvider);
    expect(state.running, isFalse);
    expect(state.total, 12);
    expect(state.done, 12);
    expect(state.imported, 12);
    expect(state.failed, 0);
  });

  test('a failing row is counted, not fatal', () async {
    final api = _FakeApi(failIds: {2, 7});
    final storage = _FakeStorage();
    final container = ProviderContainer(
      overrides: [
        zlibraryApiProvider.overrideWithValue(api),
        storageServiceProvider.overrideWithValue(storage),
      ],
    );
    addTearDown(container.dispose);

    await container.read(favoritesImportProvider.notifier).run([
      for (var i = 1; i <= 5; i++) entry(i),
      entry(7),
    ]);

    final state = container.read(favoritesImportProvider);
    expect(state.running, isFalse);
    expect(state.total, 6);
    expect(state.imported, 4);
    expect(state.failed, 2);
    // A failed server save must not record a local favorite.
    expect(storage.added, isNot(contains('2')));
    expect(storage.added, isNot(contains('7')));
    expect(storage.added.length, 4);
  });

  test('an empty list is a no-op', () async {
    final api = _FakeApi();
    final container = ProviderContainer(
      overrides: [
        zlibraryApiProvider.overrideWithValue(api),
        storageServiceProvider.overrideWithValue(_FakeStorage()),
      ],
    );
    addTearDown(container.dispose);

    await container.read(favoritesImportProvider.notifier).run(const []);

    expect(api.savedIds, isEmpty);
    expect(container.read(favoritesImportProvider).total, 0);
  });
}
