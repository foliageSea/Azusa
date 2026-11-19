import 'dart:async';
import 'dart:typed_data';

import 'package:azusa/features/organizer/connections/connection_settings.dart';
import 'package:azusa/features/organizer/file_server/file_server_factory.dart';
import 'package:azusa/features/organizer/smb/smb_client.dart';
import 'package:azusa/features/organizer/smb/smb_connection.dart';
import 'package:dart_smb2/dart_smb2.dart';
import 'package:flutter_test/flutter_test.dart';

Matcher _message(String message) =>
    isA<StateError>().having((e) => e.message, 'message', message);

void main() {
  late _Backend backend;
  late SmbClient client;
  late int connects;
  setUp(() {
    backend = _Backend();
    connects = 0;
    client = SmbClient.withBackend(() async {
      connects++;
      return backend;
    }, stagingName: () => '.stage');
    addTearDown(client.close);
  });

  test('default factory validates and creates the SMB transport offline', () {
    const connection = SmbConnection(
      id: 'smb-id',
      name: 'Media',
      host: 'nas.example',
      share: 'media',
      username: 'user',
    );
    defaultFileServerFactory.validate(connection);
    expect(defaultFileServerFactory.scope(connection), connection.scope);
    final adapter = defaultFileServerFactory.create(
      const ConnectionSettings(fileServerConnection: connection),
    );
    expect(adapter, isA<SmbClient>());
    expect(adapter.root, '/');
    adapter.close();
  });

  test(
    'canonicalizes once and rejects unsafe paths without connecting',
    () async {
      expect(
        client.normalize('/media/a%20b/%252e%252e/%23/'),
        '/media/a%20b/%252e%252e/%23/',
      );
      for (final path in [
        '',
        'x',
        '//host/x',
        '/a//b',
        '/.',
        '/%2e%2E',
        '/a%2fb',
        '/a%5Cb',
        '/a%00b',
        '/a%7fb',
        '/a%3ab',
        '/a%2ab',
        '/a%20',
        '/a.',
        '/a%',
        '/a%ff',
        '/a?b',
        '/a#b',
        '/CON.txt',
        '/com1',
        '/LPT%C2%B2.mkv',
      ]) {
        expect(
          () => client.normalize(path),
          throwsFormatException,
          reason: path,
        );
      }
      await expectLater(client.list('/%2e%2e'), throwsFormatException);
      expect(connects, 0);
    },
  );

  test('never mutates the share root or starts a connection for it', () async {
    final expected = throwsA(_message(SmbClientMessages.rootMutation));
    await expectLater(client.move('/', '/to'), expected);
    await expectLater(client.move('/from', '/'), expected);
    await expectLater(client.mkdir('/'), expected);
    await expectLater(client.remove('/'), expected);
    await expectLater(client.upload('/', const Stream.empty(), 0), expected);
    await expectLater(
      client.upload('/file', const Stream.empty(), -1),
      throwsA(_message(SmbClientMessages.invalidLength)),
    );
    expect(connects, 0);
  });

  test('opens lazily, shares one connection, and closes once', () async {
    expect(connects, 0);
    await Future.wait([client.list('/'), client.stat('/')]);
    expect(connects, 1);
    client.close();
    client.close();
    expect(backend.disconnects, 1);
    await expectLater(
      client.list('/'),
      throwsA(_message(SmbClientMessages.closed)),
    );
  });

  test(
    'closing during connection closes a late pool without using it',
    () async {
      final pending = Completer<SmbBackend>();
      final other = SmbClient.withBackend(() => pending.future);
      final stat = other.stat('/');
      other.close();
      pending.complete(backend);
      await expectLater(stat, throwsA(_message(SmbClientMessages.closed)));
      expect(backend.disconnects, 1);
      expect(backend.calls, isEmpty);
    },
  );

  test('display filters hidden/system; listAll includes both', () async {
    backend.put('Media', type: Smb2FileType.directory);
    backend.put('Media/a # %.txt', size: 42);
    backend.put('Media/hidden', attributes: 2);
    backend.put('Media/system', attributes: 4);
    final display = await client.list('/Media/');
    expect(display.single.path, '/Media/a%20%23%20%25.txt');
    expect(display.single.size, 42);
    expect((await client.listAll('/Media/')).map((e) => e.name), [
      'a # %.txt',
      'hidden',
      'system',
    ]);
    expect((await client.stat('/Media'))?.path, '/Media/');
    await client.download('/Media/a%20%23%20%25.txt', '/local/target');
    expect(backend.calls.last, 'download Media/a # %.txt /local/target');
  });

  test(
    'listAll fails closed for unrepresentable or ambiguous entries',
    () async {
      backend.put('unsafe:ads');
      backend.put('ordinary');
      expect((await client.list('/')).map((e) => e.name), ['ordinary']);
      await expectLater(
        client.listAll('/'),
        throwsA(_message(SmbClientMessages.incompleteListing)),
      );
      backend.items.remove('unsafe:ads');
      backend.put('ORDINARY');
      expect(await client.list('/'), isEmpty);
      await expectLater(
        client.listAll('/'),
        throwsA(_message(SmbClientMessages.incompleteListing)),
      );
    },
  );

  test('rejects reparse endpoints and every intermediate segment', () async {
    backend.put('junction', type: Smb2FileType.directory, attributes: 0x400);
    backend.put('link', type: Smb2FileType.link);
    backend.put('ordinary');
    final reparse = throwsA(_message(SmbClientMessages.reparsePoint));
    await expectLater(client.stat('/junction/child'), reparse);
    await expectLater(client.list('/junction'), reparse);
    await expectLater(client.remove('/link'), reparse);
    await expectLater(client.download('/link', 'local'), reparse);
    await expectLater(client.move('/ordinary', '/junction/new'), reparse);
    await expectLater(client.mkdir('/junction/new'), reparse);
    await expectLater(
      client.upload('/junction/new', const Stream.empty(), 0),
      reparse,
    );
    expect(backend.calls.toSet(), {'list '});
    expect((await client.list('/')).map((e) => e.name), ['ordinary']);
    await expectLater(
      client.listAll('/'),
      throwsA(_message(SmbClientMessages.incompleteListing)),
    );
  });

  test(
    'distinguishes confirmed absence from non-visible names and failures',
    () async {
      expect(await client.stat('/missing'), isNull);
      backend.put('UPPER');
      expect(await client.stat('/upper'), isNull);
      backend.put('unlisted');
      backend.omit.add('unlisted');
      await expectLater(
        client.stat('/unlisted'),
        throwsA(_message(SmbClientMessages.incompleteListing)),
      );
      backend.statFailure = const Smb2Exception(
        'credential and remote location must not escape',
        type: Smb2ErrorType.notFound,
        ntStatus: 0xC0000056, // DELETE_PENDING is not definitive absence.
      );
      await expectLater(
        client.stat('/ambiguous'),
        throwsA(_message(SmbClientMessages.notFound)),
      );
      backend.listFailure = const Smb2Exception(
        'secret',
        type: Smb2ErrorType.accessDenied,
      );
      await expectLater(
        client.listAll('/'),
        throwsA(_message(SmbClientMessages.accessDenied)),
      );
    },
  );

  test(
    'retries a failed lazy connect and sanitizes native and unexpected errors',
    () async {
      var attempts = 0;
      final other = SmbClient.withBackend(() async {
        switch (attempts++) {
          case 0:
            throw const Smb2Exception(
              'secret',
              type: Smb2ErrorType.auth,
              path: 'private',
            );
          case 1:
            throw ArgumentError('secret');
          default:
            return backend;
        }
      });
      addTearDown(other.close);
      await expectLater(
        other.list('/'),
        throwsA(_message(SmbClientMessages.authentication)),
      );
      await expectLater(
        other.list('/'),
        throwsA(_message(SmbClientMessages.failed)),
      );
      expect(await other.list('/'), isEmpty);
    },
  );

  test(
    'moves without overwrite and removes directories only with rmdir',
    () async {
      backend.put('folder', type: Smb2FileType.directory);
      backend.put('folder/file');
      backend.put('existing');
      await expectLater(
        client.move('/folder/file', '/existing'),
        throwsA(_message(SmbClientMessages.alreadyExists)),
      );
      await expectLater(
        client.remove('/folder/'),
        throwsA(_message(SmbClientMessages.notEmpty)),
      );
      expect(backend.items, contains('folder/file'));
      expect(backend.mutations, ['rmdir folder']);
      await client.move('/folder/file', '/renamed');
      await client.remove('/folder/');
      await client.remove('/renamed');
      expect(backend.mutations, [
        'rmdir folder',
        'rename folder/file renamed false',
        'rmdir folder',
        'delete renamed',
      ]);
    },
  );

  test(
    'publishes only from an exclusive staging directory after streaming',
    () async {
      await client.upload(
        '/result',
        Stream.fromIterable([
          [1, 2],
          [3],
        ]),
        3,
      );
      expect(backend.items['result']?.size, 3);
      expect(backend.mutations, [
        'mkdir .stage',
        'write .stage/payload',
        'rename .stage/payload result false',
        'rmdir .stage',
      ]);
      expect(backend.items, isNot(contains('.stage')));
      await client.upload('/empty', const Stream.empty(), 0);
      expect(backend.items['empty']?.size, 0);
    },
  );

  test('never touches an existing destination or staging directory', () async {
    backend.put('existing');
    backend.put('.stage', type: Smb2FileType.directory);
    backend.put('.stage/payload', size: 123);
    final exists = throwsA(_message(SmbClientMessages.alreadyExists));
    await expectLater(
      client.upload('/existing', const Stream.empty(), 0),
      exists,
    );
    expect(backend.mutations, isEmpty);
    await expectLater(client.upload('/new', const Stream.empty(), 0), exists);
    expect(backend.mutations, ['mkdir .stage']);
    expect(backend.items['.stage/payload']?.size, 123);
  });

  test(
    'upload never publishes on short, long, or misreported streams',
    () async {
      final mismatch = throwsA(_message(SmbClientMessages.transferLength));
      await expectLater(
        client.upload('/short', Stream.value([1]), 2),
        mismatch,
      );
      await expectLater(
        client.upload('/long', Stream.value([1, 2]), 1),
        mismatch,
      );
      backend.writeReported = 0;
      await expectLater(
        client.upload('/misreported', Stream.value([1]), 1),
        mismatch,
      );
      backend.writeReported = null;
      backend.remoteSize = 0;
      await expectLater(
        client.upload('/remote-truncated', Stream.value([1]), 1),
        mismatch,
      );
      expect(backend.items.keys, ['']);
      expect(backend.mutations.where((s) => s.startsWith('rename')), isEmpty);
    },
  );

  test('upload protects a destination that appears at rename time', () async {
    backend.beforeRename = (to) => backend.put(to, size: 123);
    await expectLater(
      client.upload('/result', Stream.value([1]), 1),
      throwsA(_message(SmbClientMessages.alreadyExists)),
    );
    expect(backend.items['result']?.size, 123);
    expect(backend.mutations, [
      'mkdir .stage',
      'write .stage/payload',
      'rename .stage/payload result false',
      'delete .stage/payload',
      'rmdir .stage',
    ]);
  });

  test(
    'changed staging identity prevents publication and all cleanup',
    () async {
      backend.afterWrite = () =>
          backend.put('.stage', type: Smb2FileType.directory);
      await expectLater(
        client.upload('/result', Stream.value([1]), 1),
        throwsA(_message(SmbClientMessages.unsafePath)),
      );
      expect(backend.mutations, ['mkdir .stage', 'write .stage/payload']);
    },
  );
}

class _Backend implements SmbBackend {
  _Backend() {
    put('', type: Smb2FileType.directory);
  }

  final items = <String, Smb2Stat>{};
  final omit = <String>{};
  final calls = <String>[];
  final mutations = <String>[];
  var disconnects = 0;
  var _nextId = 0;
  int? writeReported;
  int? remoteSize;
  Smb2Exception? statFailure;
  Smb2Exception? listFailure;
  void Function(String)? beforeRename;
  void Function()? afterWrite;

  static const missing = Smb2Exception(
    'private',
    type: Smb2ErrorType.notFound,
    ntStatus: 0xC0000034,
  );
  static const exists = Smb2Exception(
    'private',
    type: Smb2ErrorType.alreadyExists,
  );
  static final time = DateTime.utc(2026, 11, 19);

  void put(
    String path, {
    Smb2FileType type = Smb2FileType.file,
    int size = 0,
    int attributes = 0,
  }) {
    items[path] = Smb2Stat(
      type: type,
      size: size,
      created: time,
      accessed: time,
      modified: time,
      changed: time,
      attributes: attributes,
      fileId: ++_nextId,
    );
  }

  @override
  Future<List<Smb2DirEntry>> listDirectory(String path) async {
    calls.add('list $path');
    if (listFailure case final failure?) throw failure;
    if (!items.containsKey(path)) throw missing;
    final prefix = path.isEmpty ? '' : '$path/';
    return [
      for (final entry in items.entries)
        if (entry.key != path &&
            !omit.contains(entry.key) &&
            entry.key.startsWith(prefix) &&
            !entry.key.substring(prefix.length).contains('/'))
          Smb2DirEntry(
            name: entry.key.substring(prefix.length),
            stat: entry.value,
          ),
    ];
  }

  @override
  Future<Smb2Stat> stat(String path) async {
    calls.add('stat $path');
    if (statFailure case final failure?) throw failure;
    return items[path] ?? (throw missing);
  }

  @override
  Future<void> mkdir(String path) async {
    mutations.add('mkdir $path');
    if (items.containsKey(path)) throw exists;
    put(path, type: Smb2FileType.directory);
  }

  @override
  Future<void> rmdir(String path) async {
    mutations.add('rmdir $path');
    if (items.keys.any((key) => key.startsWith('$path/'))) {
      throw const Smb2Exception('private', type: Smb2ErrorType.notEmpty);
    }
    if (items.remove(path) == null) throw missing;
  }

  @override
  Future<void> deleteFile(String path) async {
    mutations.add('delete $path');
    if (items.remove(path) == null) throw missing;
  }

  @override
  Future<void> rename(String from, String to, {required bool overwrite}) async {
    mutations.add('rename $from $to $overwrite');
    beforeRename?.call(to);
    if (!overwrite && items.containsKey(to)) throw exists;
    items[to] = items.remove(from) ?? (throw missing);
  }

  @override
  Future<int> streamWrite(
    String path,
    Stream<Uint8List> chunks,
    int length,
  ) async {
    mutations.add('write $path');
    put(path);
    var offset = 0;
    await for (final chunk in chunks) {
      offset += chunk.length;
      put(path, size: offset);
    }
    if (remoteSize case final size?) put(path, size: size);
    afterWrite?.call();
    return writeReported ?? offset;
  }

  @override
  Future<void> download(String path, String destination) async {
    calls.add('download $path $destination');
  }

  @override
  Future<void> disconnect() async {
    disconnects++;
  }
}
