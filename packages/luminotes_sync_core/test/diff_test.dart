import 'package:luminotes_sync_core/luminotes_sync_core.dart';
import 'package:test/test.dart';

ManifestEntry e(String hash) =>
    ManifestEntry(size: hash.length, sha256: hash, modifiedMs: 0);

Manifest m(Map<String, String> hashes) =>
    Manifest({for (final kv in hashes.entries) kv.key: e(kv.value)});

SyncOp? opFor(List<SyncAction> actions, String path) {
  for (final a in actions) {
    if (a.path == path) return a.op;
  }
  return null;
}

void main() {
  test('no changes -> no actions', () {
    final actions = diffManifests(
      local: m({'a': 'x'}),
      remote: m({'a': 'x'}),
      base: m({'a': 'x'}),
    );
    expect(actions, isEmpty);
  });

  test('local-only edit pushes', () {
    final actions = diffManifests(
      local: m({'a': 'x2'}),
      remote: m({'a': 'x'}),
      base: m({'a': 'x'}),
    );
    expect(opFor(actions, 'a'), SyncOp.push);
  });

  test('remote-only edit pulls', () {
    final actions = diffManifests(
      local: m({'a': 'x'}),
      remote: m({'a': 'x2'}),
      base: m({'a': 'x'}),
    );
    expect(opFor(actions, 'a'), SyncOp.pull);
  });

  test('local delete removes remote', () {
    final actions = diffManifests(
      local: m({}),
      remote: m({'a': 'x'}),
      base: m({'a': 'x'}),
    );
    expect(opFor(actions, 'a'), SyncOp.deleteRemote);
  });

  test('remote delete removes local', () {
    final actions = diffManifests(
      local: m({'a': 'x'}),
      remote: m({}),
      base: m({'a': 'x'}),
    );
    expect(opFor(actions, 'a'), SyncOp.deleteLocal);
  });

  test('both edit to different content -> conflict', () {
    final actions = diffManifests(
      local: m({'a': 'L'}),
      remote: m({'a': 'R'}),
      base: m({'a': 'x'}),
    );
    expect(opFor(actions, 'a'), SyncOp.conflict);
  });

  test('both edit to same content -> no action', () {
    final actions = diffManifests(
      local: m({'a': 'same'}),
      remote: m({'a': 'same'}),
      base: m({'a': 'x'}),
    );
    expect(actions, isEmpty);
  });

  test('first sync union: each side keeps its own new files', () {
    final actions = diffManifests(
      local: m({'a': 'x'}),
      remote: m({'b': 'y'}),
      base: m({}),
    );
    expect(opFor(actions, 'a'), SyncOp.push);
    expect(opFor(actions, 'b'), SyncOp.pull);
  });

  test('delete/modify conflict keeps the modified side', () {
    // local deleted, remote modified -> pull (resurrect remote)
    expect(
      opFor(
        diffManifests(local: m({}), remote: m({'a': 'r2'}), base: m({'a': 'x'})),
        'a',
      ),
      SyncOp.pull,
    );
    // remote deleted, local modified -> push
    expect(
      opFor(
        diffManifests(local: m({'a': 'l2'}), remote: m({}), base: m({'a': 'x'})),
        'a',
      ),
      SyncOp.push,
    );
  });
}
