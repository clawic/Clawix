'use strict';

const fs = require('node:fs');
const path = require('node:path');
const os = require('node:os');
const https = require('node:https');
const crypto = require('node:crypto');
const { spawnSync, execFileSync } = require('node:child_process');

const pkg = require('../package.json');

const SUPPORTED_PLATFORMS = new Set(['darwin', 'linux', 'win32']);
const SUPPORTED_ARCHES = new Set(['arm64', 'x64']);
const BASE_URL = `https://github.com/clawic/clawix/releases/download/v${pkg.version}`;

function assetForPlatform(platform = process.platform, arch = process.arch) {
  if (platform === 'darwin') return 'clawix-cli-darwin-universal.tar.gz';
  if (platform === 'linux') {
    const linuxArch = arch === 'arm64' ? 'aarch64' : 'x86_64';
    return `clawix-cli-linux-${linuxArch}.tar.gz`;
  }
  if (platform === 'win32') return 'clawix-cli-windows-x86_64.zip';
  return null;
}

function binNamesForPlatform(platform = process.platform) {
  return platform === 'win32'
    ? ['clawix-bridge.exe', 'clawix-menubar.exe']
    : ['clawix-bridge', 'clawix-menubar'];
}

function readChecksums(checksumsPath = path.join(__dirname, 'checksums.json')) {
  try {
    return JSON.parse(fs.readFileSync(checksumsPath, 'utf8'));
  } catch {
    return {};
  }
}

function preflight(log = console.log) {
  if (!SUPPORTED_PLATFORMS.has(process.platform)) {
    return { skipped: true, reason: `unsupported platform ${process.platform}` };
  }
  if (!SUPPORTED_ARCHES.has(process.arch)) {
    return { skipped: true, reason: `unsupported architecture ${process.arch}` };
  }

  let chownTarget = null;
  if (process.geteuid && process.geteuid() === 0 && process.env.SUDO_USER) {
    const sudoUser = process.env.SUDO_USER;
    let realHome;
    if (process.platform === 'darwin') {
      realHome = path.join('/Users', sudoUser);
    } else {
      try {
        const out = execFileSync('/usr/bin/getent', ['passwd', sudoUser], { encoding: 'utf8' });
        realHome = out.split(':')[5] || path.join('/home', sudoUser);
      } catch {
        realHome = path.join('/home', sudoUser);
      }
    }
    if (!fs.existsSync(realHome)) {
      throw new Error(`SUDO_USER=${sudoUser} but ${realHome} does not exist; refusing to install into root's home.`);
    }
    process.env.HOME = realHome;
    chownTarget = sudoUser;
    log(
      `clawix: detected \`sudo clawix setup\`. Installing into ${realHome} for user ${sudoUser}.\n` +
      `        Tip: configure npm to use a user-owned prefix to avoid sudo entirely.`
    );
  }

  if (process.platform === 'darwin') {
    const macosMajor = (() => {
      try {
        const out = execFileSync('/usr/bin/sw_vers', ['-productVersion'], { encoding: 'utf8' }).trim();
        const major = parseInt(out.split('.')[0], 10);
        return Number.isFinite(major) ? major : null;
      } catch {
        return null;
      }
    })();
    if (macosMajor !== null && macosMajor < 14) {
      throw new Error(
        `requires macOS Sonoma 14 or later (detected macOS ${macosMajor}).\n` +
        `The bundled binaries will not launch on this system. Aborting.`
      );
    }
  }

  return { skipped: false, chownTarget };
}

function fetch(u) {
  return new Promise((resolve, reject) => {
    const get = (url, redirects = 0) => {
      if (redirects > 5) return reject(new Error('Too many redirects.'));
      https.get(url, (res) => {
        if (res.statusCode === 301 || res.statusCode === 302) {
          if (!res.headers.location) return reject(new Error('Redirect without Location header.'));
          return get(res.headers.location, redirects + 1);
        }
        if (res.statusCode !== 200) {
          return reject(new Error(`HTTP ${res.statusCode} fetching ${url}`));
        }
        const chunks = [];
        res.on('data', (chunk) => chunks.push(chunk));
        res.on('end', () => resolve(Buffer.concat(chunks)));
        res.on('error', reject);
      }).on('error', reject);
    };
    get(u);
  });
}

async function fetchWithRetry(url) {
  const delays = [2_000, 4_000, 8_000];
  let lastErr;
  for (let attempt = 1; attempt <= 3; attempt++) {
    try {
      return await fetch(url);
    } catch (err) {
      lastErr = err;
      if (attempt === 3) break;
      const delay = delays[attempt - 1];
      console.error(`clawix: network error fetching tarball (try ${attempt}/3): retrying in ${delay / 1000}s...`);
      await new Promise((r) => setTimeout(r, delay));
    }
  }
  throw new Error(
    `could not fetch ${url} after 3 attempts: ${(lastErr && lastErr.message) || lastErr}.\n` +
    'check your network and rerun `clawix setup`.'
  );
}

function chownToRealUser(filePath, chownTarget) {
  if (!chownTarget) return;
  spawnSync('/usr/sbin/chown', ['-R', `${chownTarget}:staff`, filePath], { stdio: 'ignore' });
}

function hasNativeBinaries({ binary = require('./binary'), fsModule = fs } = {}) {
  return fsModule.existsSync(binary.resolveBridged());
}

async function runSetup(options = {}) {
  const log = options.log || console.log;
  const status = preflight(log);
  if (status.skipped) {
    log(`clawix: skipping native setup (${status.reason}).`);
    return status;
  }

  const platform = options.platform || require('./platform');
  const manifest = options.manifest || require('./manifest');
  const checksums = options.checksums || readChecksums(options.checksumsPath);
  const asset = options.asset || assetForPlatform(process.platform, process.arch);
  const url = `${BASE_URL}/${asset}`;
  const localTarball = options.localTarball !== undefined
    ? options.localTarball
    : (process.env[platform.Env.clawixLocalTarball] || null);
  const expectedSha = checksums[asset];

  if (!localTarball && !expectedSha) {
    log(
      `clawix: no checksum recorded for ${asset} in this build.\n` +
      `        This is expected if you're running from a source checkout without a release pipeline.\n` +
      `        Set CLAWIX_LOCAL_TARBALL=/path/to/${asset} for local testing.`
    );
    return { skipped: true, reason: 'missing-checksum', asset };
  }

  fs.mkdirSync(platform.CLAWIX_HOME, { recursive: true });
  chownToRealUser(platform.CLAWIX_HOME, status.chownTarget);
  const stagingDir = platform.BIN_DIR + '.tmp';
  if (fs.existsSync(stagingDir)) fs.rmSync(stagingDir, { recursive: true, force: true });
  fs.mkdirSync(stagingDir, { recursive: true });

  let data;
  let sha;
  if (localTarball) {
    if (!fs.existsSync(localTarball)) {
      throw new Error(`CLAWIX_LOCAL_TARBALL=${localTarball} does not exist.`);
    }
    log(`clawix: using local tarball ${localTarball} (CLAWIX_LOCAL_TARBALL set).`);
    data = fs.readFileSync(localTarball);
    sha = crypto.createHash('sha256').update(data).digest('hex');
  } else {
    log(`clawix: fetching ${asset} v${pkg.version}...`);
    data = await (options.fetchWithRetry || fetchWithRetry)(url);
    sha = crypto.createHash('sha256').update(data).digest('hex');
    if (sha !== expectedSha) {
      throw new Error(
        `Checksum mismatch for ${asset}.\n` +
        `  expected: ${expectedSha}\n` +
        `  got:      ${sha}\n` +
        'Aborting; nothing was installed.'
      );
    }
  }

  const isZip = asset.endsWith('.zip');
  const archivePath = path.join(os.tmpdir(), `clawix-${pkg.version}-${process.pid}${isZip ? '.zip' : '.tar.gz'}`);
  fs.writeFileSync(archivePath, data);
  try {
    if (isZip) {
      const tarBin = process.platform === 'win32' ? 'tar' : '/usr/bin/tar';
      let r = spawnSync(tarBin, ['-xf', archivePath, '-C', stagingDir], { stdio: 'inherit' });
      if (r.status !== 0 && process.platform === 'win32') {
        r = spawnSync('powershell.exe', [
          '-NoProfile', '-Command',
          `Expand-Archive -Path '${archivePath}' -DestinationPath '${stagingDir}' -Force`
        ], { stdio: 'inherit' });
      }
      if (r.status !== 0) throw new Error('zip extraction failed.');
    } else {
      const r = spawnSync('/usr/bin/tar', ['-xzf', archivePath, '-C', stagingDir], { stdio: 'inherit' });
      if (r.status !== 0) throw new Error('tar extraction failed.');
    }
  } finally {
    try { fs.unlinkSync(archivePath); } catch {}
  }

  for (const name of binNamesForPlatform(process.platform)) {
    const p = path.join(stagingDir, name);
    if (!fs.existsSync(p)) continue;
    if (process.platform !== 'win32') fs.chmodSync(p, 0o755);
    if (process.platform === 'darwin') {
      const v = spawnSync('/usr/bin/codesign', ['--verify', '--strict', p], { stdio: 'pipe' });
      if (v.status !== 0) {
        fs.rmSync(stagingDir, { recursive: true, force: true });
        throw new Error(`${name} failed codesign verification; aborting install.`);
      }
    }
  }

  if (fs.existsSync(platform.BIN_DIR)) {
    const archive = platform.BIN_DIR + '.old';
    fs.rmSync(archive, { recursive: true, force: true });
    fs.renameSync(platform.BIN_DIR, archive);
    try {
      fs.renameSync(stagingDir, platform.BIN_DIR);
    } catch (err) {
      fs.renameSync(archive, platform.BIN_DIR);
      throw err;
    }
    fs.rmSync(archive, { recursive: true, force: true });
  } else {
    fs.renameSync(stagingDir, platform.BIN_DIR);
  }

  manifest.write({
    version: pkg.version,
    bridgeLabel: platform.BRIDGE_LABEL,
    menubarLabel: platform.MENUBAR_LABEL,
    port: platform.BRIDGE_PORT,
    asset,
    sha256: sha,
    installedAt: new Date().toISOString(),
    source: localTarball ? 'local' : 'github-release'
  });

  chownToRealUser(platform.CLAWIX_HOME, status.chownTarget);
  log('clawix: installed. Run `clawix up` to start the bridge and pair your phone.');
  return { installed: true, asset, sha256: sha, source: localTarball ? 'local' : 'github-release' };
}

module.exports = {
  assetForPlatform,
  binNamesForPlatform,
  fetchWithRetry,
  hasNativeBinaries,
  readChecksums,
  runSetup
};
