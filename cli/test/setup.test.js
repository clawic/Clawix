'use strict';

const assert = require('node:assert/strict');
const test = require('node:test');

const pkg = require('../package.json');
const setup = require('../lib/setup');
const cli = require('../bin/clawix');

function exitTrap(code) {
  const err = new Error(`exit ${code}`);
  err.code = code;
  throw err;
}

test('package install has no postinstall lifecycle', () => {
  assert.equal(Object.hasOwn(pkg.scripts || {}, 'postinstall'), false);
});

test('assetForPlatform resolves release archive names', () => {
  assert.equal(setup.assetForPlatform('darwin', 'arm64'), 'clawix-cli-darwin-universal.tar.gz');
  assert.equal(setup.assetForPlatform('linux', 'arm64'), 'clawix-cli-linux-aarch64.tar.gz');
  assert.equal(setup.assetForPlatform('linux', 'x64'), 'clawix-cli-linux-x86_64.tar.gz');
  assert.equal(setup.assetForPlatform('win32', 'x64'), 'clawix-cli-windows-x86_64.zip');
});

test('setup no-ops in source checkout when checksum is missing', async () => {
  let fetched = false;
  const result = await setup.runSetup({
    checksums: {},
    fetchWithRetry: async () => {
      fetched = true;
      throw new Error('network should not be called');
    },
    log: () => {}
  });

  assert.equal(result.skipped, true);
  assert.equal(result.reason, 'missing-checksum');
  assert.equal(fetched, false);
});

test('explicit setup requires --yes in noninteractive shells', async () => {
  let called = false;
  await assert.rejects(
    () => cli.runExplicitSetup({
      yes: false,
      stdoutIsTTY: false,
      setupModule: { runSetup: async () => { called = true; } },
      exit: exitTrap
    }),
    /exit 1/
  );
  assert.equal(called, false);
});

test('explicit setup --yes runs in noninteractive shells', async () => {
  let called = false;
  await cli.runExplicitSetup({
    yes: true,
    stdoutIsTTY: false,
    setupModule: { runSetup: async () => { called = true; } },
    exit: exitTrap
  });
  assert.equal(called, true);
});

test('first-use guard fails closed without a TTY', async () => {
  let setupCalls = 0;
  let asked = false;
  await assert.rejects(
    () => cli.ensureBridgeAvailable({
      setupModule: {
        hasNativeBinaries: () => false,
        runSetup: async () => { setupCalls += 1; }
      },
      stdoutIsTTY: false,
      ask: async () => { asked = true; return true; },
      exit: exitTrap
    }),
    /exit 1/
  );
  assert.equal(setupCalls, 0);
  assert.equal(asked, false);
});

test('first-use guard respects declined interactive setup', async () => {
  let setupCalls = 0;
  await assert.rejects(
    () => cli.ensureBridgeAvailable({
      setupModule: {
        hasNativeBinaries: () => false,
        runSetup: async () => { setupCalls += 1; }
      },
      stdoutIsTTY: true,
      ask: async () => false,
      exit: exitTrap
    }),
    /exit 1/
  );
  assert.equal(setupCalls, 0);
});

test('first-use guard runs setup after accepted prompt', async () => {
  let setupCalls = 0;
  await cli.ensureBridgeAvailable({
    setupModule: {
      hasNativeBinaries: () => setupCalls > 0,
      runSetup: async () => { setupCalls += 1; }
    },
    stdoutIsTTY: true,
    ask: async () => true,
    exit: exitTrap
  });
  assert.equal(setupCalls, 1);
});
