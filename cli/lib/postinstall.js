'use strict';

// Kept as a compatibility shim for older tooling that may import this module.
// The npm package no longer runs a lifecycle installer; native helpers install
// only through the explicit `clawix setup` command.
module.exports = require('./setup');
