/**
 * bind.test.mjs — tests for --bind ro/wr sandbox bind mounts.
 */

import { test, describe } from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import path from 'node:path';
import { spawnSync } from 'node:child_process';
import { run, TEMPDIR, toJsonRpc, fromJsonRpc } from './helpers.mjs';

function makeBindDirs() {
  const base = fs.mkdtempSync(path.join(TEMPDIR, 'boxsh-bind-'));
  const src = path.join(base, 'src');
  const dst = path.join(base, 'dst');
  fs.mkdirSync(src);
  return {
    base,
    src,
    dst,
    cleanup: () => {
      spawnSync('chmod', ['-R', 'u+rwx', base]);
      spawnSync('rm', ['-rf', base]);
    },
  };
}

function rpcWith(extraFlags, cmd, timeout_ms = 5000) {
  const input = JSON.stringify(toJsonRpc({ id: '1', cmd })) + '\n';
  const r = run(
    ['--rpc', '--workers', '1', '--sandbox', ...extraFlags],
    input,
    timeout_ms,
  );
  assert.equal(r.signal, null, `boxsh killed by signal ${r.signal}`);
  const line = r.stdout.trim();
  assert.ok(line.length > 0, `no output; stderr: ${r.stderr}`);
  return fromJsonRpc(JSON.parse(line));
}

describe('sandbox — ro/wr bind mounts', () => {
  test('legacy ro:PATH exposes the path read-only', () => {
    const { src, cleanup } = makeBindDirs();
    try {
      fs.writeFileSync(path.join(src, 'hello.txt'), 'from-src\n');
      const read = rpcWith(['--bind', `ro:${src}`], `cat ${src}/hello.txt`);
      assert.equal(read.exit_code, 0);
      assert.equal(read.stdout, 'from-src\n');

      const write = rpcWith(
        ['--bind', `ro:${src}`],
        `printf bad > ${src}/hello.txt`,
      );
      assert.notEqual(write.exit_code, 0);
      assert.equal(fs.readFileSync(path.join(src, 'hello.txt'), 'utf8'), 'from-src\n');
    } finally {
      cleanup();
    }
  });

  test('ro:SRC:DST exposes src at dst read-only',
    { skip: process.platform === 'darwin' ? 'ro:SRC:DST remapping is Linux-only' : false },
    () => {
    const { src, dst, cleanup } = makeBindDirs();
    try {
      fs.writeFileSync(path.join(src, 'hello.txt'), 'from-src\n');
      const read = rpcWith(['--bind', `ro:${src}:${dst}`], `cat ${dst}/hello.txt`);
      assert.equal(read.exit_code, 0);
      assert.equal(read.stdout, 'from-src\n');

      const write = rpcWith(
        ['--bind', `ro:${src}:${dst}`],
        `printf bad > ${dst}/hello.txt`,
      );
      assert.notEqual(write.exit_code, 0);
      assert.equal(fs.readFileSync(path.join(src, 'hello.txt'), 'utf8'), 'from-src\n');
    } finally {
      cleanup();
    }
  });

  test('wr:SRC:DST exposes src at dst read-write',
    { skip: process.platform === 'darwin' ? 'wr:SRC:DST remapping is Linux-only' : false },
    () => {
    const { src, dst, cleanup } = makeBindDirs();
    try {
      fs.writeFileSync(path.join(src, 'hello.txt'), 'from-src\n');
      const write = rpcWith(
        ['--bind', `wr:${src}:${dst}`],
        `printf changed > ${dst}/hello.txt && cat ${dst}/hello.txt`,
      );
      assert.equal(write.exit_code, 0);
      assert.equal(write.stdout, 'changed');
      assert.equal(fs.readFileSync(path.join(src, 'hello.txt'), 'utf8'), 'changed');
    } finally {
      cleanup();
    }
  });

  test('ro:SRC:DST is rejected on macOS',
    { skip: process.platform !== 'darwin' ? 'macOS-only validation' : false },
    () => {
    const { src, dst, cleanup } = makeBindDirs();
    try {
      const r = run(['--rpc', '--sandbox', '--bind', `ro:${src}:${dst}`], '');
      assert.equal(r.status, 1);
      assert.match(r.stderr, /SRC:DST bind remapping is only supported on Linux/);
    } finally {
      cleanup();
    }
  });
});
