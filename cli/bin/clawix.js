#!/usr/bin/env node
'use strict';

const readline = require('node:readline');
const pkg = require('../package.json');

const COMMANDS = [
    'up', 'start', 'stop', 'status', 'pair', 'unpair', 'logs', 'doctor',
    'install-app', 'restart', 'setup', 'uninstall',
];

// Honour --no-color BEFORE require()ing ui.js: ui.js samples
// process.stdout.isTTY + NO_COLOR at module load.
if (process.argv.includes('--no-color')) {
    process.env.NO_COLOR = '1';
}

const ui = require('../lib/ui');

function help() {
    process.stdout.write(`
${ui.bold('clawix')} v${pkg.version} — bridge codex from your phone via your mac.

${ui.bold('usage')}
  clawix <command> [flags]

${ui.bold('commands')}
  up               start bridge + menu bar, show pairing QR, watch live status
  start            start bridge as launchd agent (no QR, no watch)
  stop             stop bridge + menu bar
  restart          restart the bridge
  status           bridge state, port, peers, app presence
  pair             show pairing QR + short code
  unpair           rotate pairing token + short code (kicks every paired device)
  doctor           run health checks across the whole environment
  logs [-f]        tail bridge logs
  install-app      install /Applications/Clawix.app from the latest release
  setup            install signed native bridge helpers into ~/.clawix/bin
  uninstall        remove ~/.clawix/bin and unregister launchd agents

${ui.bold('flags')}
  --json           machine-readable output (status, pair, doctor)
  --no-color       disable ANSI colors (also honoured: NO_COLOR=1)
  --yes            allow noninteractive native setup
  --version, -v    print cli version
  --help, -h       this message

${ui.bold('examples')}
  clawix up                         first-time pairing with live watch
  clawix doctor --json              ci-friendly health check
  clawix logs -f                    debug a bridge that won't connect

${ui.bold('paths')}
  ~/.clawix/bin/                              ${ui.dim('binaries installed by clawix setup')}
  ~/.clawix/state/bridge-status.json          ${ui.dim('daemon heartbeat')}
  ~/Library/LaunchAgents/clawix.bridge.plist  ${ui.dim('launchd registration')}
  ~/Library/Preferences/clawix.bridge.plist   ${ui.dim('pairing token + short code')}
  /tmp/clawix-bridge.{out,err}               ${ui.dim('daemon logs')}
`);
}

function askYesNo(question) {
    return new Promise((resolve) => {
        const rl = readline.createInterface({ input: process.stdin, output: process.stdout });
        rl.question(question, (answer) => {
            rl.close();
            resolve(/^(y|yes)$/i.test(String(answer).trim()));
        });
    });
}

async function runExplicitSetup({ yes = false, stdoutIsTTY = process.stdout.isTTY, setupModule = null, exit = process.exit } = {}) {
    if (!stdoutIsTTY && !yes) {
        ui.fail(
            'native setup needs explicit confirmation in noninteractive shells.',
            null,
            'run `clawix setup --yes` to download and install signed bridge helpers.'
        );
        exit(1);
        return;
    }
    const setup = setupModule || require('../lib/setup');
    await setup.runSetup();
}

async function ensureBridgeAvailable({
    setupModule = null,
    stdoutIsTTY = process.stdout.isTTY,
    ask = askYesNo,
    exit = process.exit
} = {}) {
    const setup = setupModule || require('../lib/setup');
    if (setup.hasNativeBinaries()) return;
    if (!stdoutIsTTY) {
        ui.fail(
            'clawix-bridge is not installed.',
            'npm install no longer downloads native helpers.',
            'run `clawix setup` first.'
        );
        exit(1);
        return;
    }
    const ok = await ask(
        'clawix-bridge is not installed. Download and install signed native helpers now? [y/N] '
    );
    if (!ok) {
        ui.fail('native setup was cancelled.', null, 'run `clawix setup` when you are ready.');
        exit(1);
        return;
    }
    await setup.runSetup();
    if (!setup.hasNativeBinaries()) {
        ui.fail('clawix-bridge is still not installed.', null, 'run `clawix setup` and then `clawix doctor`.');
        exit(1);
    }
}

async function main(argv) {
    const args = argv.slice(2).filter((a) => a !== '--no-color');
    if (args.length === 0 || args[0] === '--help' || args[0] === '-h' || args[0] === 'help') {
        help();
        return;
    }
    if (args[0] === '--version' || args[0] === '-v') {
        console.log(pkg.version);
        return;
    }

    const cmd = args[0];
    if (!COMMANDS.includes(cmd)) {
        ui.fail(
            `unknown command "${cmd}".`,
            null,
            'run `clawix --help` to list commands.'
        );
        process.exit(2);
    }
    const rest = args.slice(1);
    const flag = (name) => rest.includes(name);

    if (cmd === 'setup') {
        await runExplicitSetup({ yes: flag('--yes') });
        return;
    }

    const platform = require('../lib/platform');
    platform.ensureSupported();

    switch (cmd) {
        case 'up': {
            await ensureBridgeAvailable();
            const up = require('../lib/up');
            await up.run({ noWatch: flag('--no-watch') });
            return;
        }
        case 'start': {
            await ensureBridgeAvailable();
            const daemon = require('../lib/daemon');
            const r = daemon.start();
            console.log(r.reused ? 'bridge: already running' : `bridge: started (${r.binary})`);
            return;
        }
        case 'stop': {
            const daemon = require('../lib/daemon');
            const menubar = require('../lib/menubar');
            menubar.stop();
            daemon.stop();
            console.log('bridge: stopped');
            return;
        }
        case 'restart': {
            await ensureBridgeAvailable();
            const daemon = require('../lib/daemon');
            daemon.restart();
            console.log('bridge: restarted');
            return;
        }
        case 'status': {
            const daemon = require('../lib/daemon');
            const menubar = require('../lib/menubar');
            const s = await daemon.status();
            const m = menubar.isRunning();
            const view = {
                bridge: {
                    loaded: s.loaded,
                    reachable: s.reachable,
                    port: s.port,
                    peerCount: s.peerCount,
                    heartbeatAgeMs: s.heartbeatAgeMs,
                    heartbeatStale: s.heartbeatStale
                },
                binary: s.binary,
                menubar: m,
                app: { installed: s.appInstalled, path: '/Applications/Clawix.app' }
            };
            if (flag('--json')) {
                console.log(JSON.stringify(view, null, 2));
            } else {
                let bridgeState;
                if (!s.loaded) bridgeState = 'not running';
                else if (!s.reachable) bridgeState = 'loaded but not reachable';
                else if (s.heartbeatStale) bridgeState = 'reachable, heartbeat stale';
                else bridgeState = 'running';
                console.log(`bridge   : ${bridgeState} (port ${s.port})`);
                if (s.peerCount !== null && s.peerCount !== undefined) {
                    console.log(`peers    : ${s.peerCount}`);
                }
                if (s.heartbeatAgeMs !== null && s.heartbeatAgeMs !== undefined) {
                    console.log(`heartbeat: ${Math.round(s.heartbeatAgeMs / 1000)}s ago`);
                }
                console.log(`binary   : ${s.binary}`);
                console.log(`menubar  : ${m ? 'running' : 'not running'}`);
                console.log(`Clawix.app: ${s.appInstalled ? 'installed' : 'not installed'}`);
            }
            return;
        }
        case 'pair': {
            const pair = require('../lib/pair');
            pair.show({ json: flag('--json') });
            return;
        }
        case 'unpair': {
            const { unpair } = require('../lib/unpair');
            unpair();
            return;
        }
        case 'logs': {
            const logs = require('../lib/logs');
            logs.tail({ follow: flag('-f') || flag('--follow') });
            return;
        }
        case 'doctor': {
            const doctor = require('../lib/doctor');
            const checks = doctor.run();
            const summary = doctor.print(checks, { json: flag('--json') });
            if (summary.fail) process.exit(1);
            return;
        }
        case 'install-app': {
            const installApp = require('../lib/install-app');
            await installApp.install();
            return;
        }
        case 'uninstall': {
            const { uninstall } = require('../lib/uninstall');
            uninstall({ keepState: !flag('--purge') });
            console.log('clawix: uninstalled. To remove the npm package run `npm uninstall -g clawix`.');
            return;
        }
    }
}

if (require.main === module) {
    main(process.argv).catch((err) => {
        ui.fail(
            (err && err.message) || String(err),
            null,
            'if this looks wrong, run `clawix doctor` to diagnose the environment.'
        );
        process.exit(1);
    });
}

module.exports = { askYesNo, ensureBridgeAvailable, main, runExplicitSetup };
