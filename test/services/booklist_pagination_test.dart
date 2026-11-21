import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:olib_api_plugin/olib_api_plugin.dart';
import 'package:zlibx/providers/auth_provider.dart';
import 'package:zlibx/providers/booklist_detail_provider.dart';
import 'package:zlibx/providers/zlibrary_provider.dart';
import 'package:zlibx/services/booklist_html_cache.dart';

/// Booklist pagination: the papi endpoint may answer without a
/// `pagination` block (the page count is then unknown), and on some
/// lines the route 404s. Both used to end a large booklist after its
/// first page; the controller now arbitrates by page size and falls
/// back to the server-rendered `?page=N` route.
const _user = User(
  id: '35899435',
  email: 'mingdao@example.com',
  name: 'mingdao',
  remixUserkey: 'key',
);

class _FakeAuthNotifier extends AuthNotifier {
  @override
  AuthState build() => AuthState(user: _user);
}

List<Book> _books(int start, int count) => [
  for (var i = 0; i < count; i++) Book(id: start + i, title: 'Book ${start + i}'),
];

class _FakePagedApi implements ZLibraryApi {
  _FakePagedApi({
    required this.page1,
    required this.papiPages,
    required this.htmlPages,
    this.totalPages,
    this.papiFails = false,
  });

  final List<Book> page1;
  final Map<int, List<Book>> papiPages;
  final Map<int, List<Book>> htmlPages;

  /// Null = the response carried no `pagination` block.
  final int? totalPages;
  final bool papiFails;

  int papiCalls = 0;
  int htmlPageCalls = 0;

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnsupportedError('unexpected: ${invocation.memberName}');

  @override
  Future<ApiResponse<List<Book>>> getBooklistDetailBooks(
    Booklist list,
  ) async => ApiResponse.ok(page1);

  @override
  Future<ApiResponse<BooklistBooksPage>> getBooklistBooks(
    String id, {
    int page = 2,
  }) async {
    papiCalls++;
    if (papiFails) return ApiResponse.fail('HTTP 404: not found');
    return ApiResponse.ok(
      BooklistBooksPage(
        books: papiPages[page] ?? const <Book>[],
        totalPages: totalPages,
      ),
    );
  }

  @override
  Future<ApiResponse<List<Book>>> getBooklistDetailBooksPage(
    Booklist list, {
    required int page,
  }) async {
    htmlPageCalls++;
    return ApiResponse.ok(htmlPages[page] ?? const <Book>[]);
  }
}

const _args = BooklistDetailArgs(
  booklist: Booklist(
    id: '4088695',
    name: 'Large list',
    url: 'https://example.com/booklist/4088695/hash/001.html',
    count: 60,
  ),
  canEdit: false,
);

Future<ProviderContainer> _loaded(_FakePagedApi api) async {
  final container = ProviderContainer(
    overrides: [
      zlibraryApiProvider.overrideWithValue(api),
      authProvider.overrideWith(_FakeAuthNotifier.new),
    ],
  );
  addTearDown(container.dispose);
  final provider = booklistDetailControllerProvider(_args);
  container.listen(provider, (_, _) {});
  await container.read(provider.notifier).initialLoadDone;
  return container;
}

BooklistDetailState _state(ProviderContainer container) =>
    container.read(booklistDetailControllerProvider(_args));

void main() {
  late Directory tempDir;

  setUpAll(() async {
    // The controller persists parsed pages + page-1 HTML in Hive.
    tempDir = await Directory.systemTemp.createTemp('booklist_pagination');
    Hive.init(tempDir.path);
    await Hive.openBox(BooklistHtmlCache.boxName);
  });

  setUp(() async {
    await Hive.box(BooklistHtmlCache.boxName).clear();
  });

  tearDownAll(() async {
    await Hive.close();
    await tempDir.delete(recursive: true);
  });

  test('missing pagination: a full page keeps loading, an empty page ends it',
      () async {
    final api = _FakePagedApi(
      page1: _books(1, 20),
      papiPages: {2: _books(21, 20), 3: const <Book>[]},
      htmlPages: const {},
    );
    final container = await _loaded(api);
    final controller = container.read(
      booklistDetailControllerProvider(_args).notifier,
    );

    expect(_state(container).books.length, 20);
    expect(_state(container).hasMore, isTrue);

    await controller.loadMore();
    expect(_state(container).books.length, 40);
    // Unknown total + full page (20) => there may be a successor.
    expect(_state(container).hasMore, isTrue);

    await controller.loadMore();
    expect(_state(container).books.length, 40);
    // Empty page is the end even without a total.
    expect(_state(container).hasMore, isFalse);
  });

  test('a short page without a total ends the list', () async {
    final api = _FakePagedApi(
      page1: _books(1, 20),
      papiPages: {2: _books(21, 7)},
      htmlPages: const {},
    );
    final container = await _loaded(api);
    final controller = container.read(
      booklistDetailControllerProvider(_args).notifier,
    );
    await controller.loadMore();
    expect(_state(container).books.length, 27);
    expect(_state(container).hasMore, isFalse);
  });

  test('a known total still wins over the page size rule', () async {
    final api = _FakePagedApi(
      page1: _books(1, 20),
      papiPages: {2: _books(21, 20)},
      htmlPages: const {},
      totalPages: 2,
    );
    final container = await _loaded(api);
    final controller = container.read(
      booklistDetailControllerProvider(_args).notifier,
    );
    await controller.loadMore();
    expect(_state(container).books.length, 40);
    expect(_state(container).hasMore, isFalse);
  });

  test('a missing papi route falls back to the HTML page route', () async {
    final api = _FakePagedApi(
      page1: _books(1, 20),
      papiPages: const {},
      htmlPages: {2: _books(21, 20), 3: const <Book>[]},
      papiFails: true,
    );
    final container = await _loaded(api);
    final controller = container.read(
      booklistDetailControllerProvider(_args).notifier,
    );

    await controller.loadMore();
    expect(api.htmlPageCalls, 1);
    expect(_state(container).books.length, 40);
    expect(_state(container).hasMore, isTrue);

    await controller.loadMore();
    expect(_state(container).books.length, 40);
    expect(_state(container).hasMore, isFalse);
  });
}
