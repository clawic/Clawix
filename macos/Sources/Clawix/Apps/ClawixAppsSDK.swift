import Foundation

/// JS bundle that the macOS app injects via `WKUserScript` at document
/// start, before any code from the app's index.html runs. Mounts a
/// `window.clawix` namespace that talks back to the native side via
/// `window.webkit.messageHandlers.clawix.postMessage`.
///
/// Kept as a Swift string (not a Resources file) so the SDK ships
/// inside the binary, can't be tampered with on disk, and doesn't add
/// a Bundle-lookup dance to AppSurfaceView. Update by editing here.
let ClawixAppsSDKJS = #"""
(function () {
  if (window.clawix) return;

  var pending = Object.create(null);
  var listeners = Object.create(null);
  var seq = 0;
  var bridge = (window.webkit && window.webkit.messageHandlers && window.webkit.messageHandlers.clawix) || null;

  function send(op, payload, options) {
    if (!bridge) {
      return Promise.reject(new Error('clawix bridge unavailable: this surface is not a Clawix App'));
    }
    options = options || {};
    var requestId = 'r-' + (++seq);
    return new Promise(function (resolve, reject) {
      var settled = false;
      var abortHandler = null;
      function cleanup() {
        delete pending[requestId];
        if (options.signal && abortHandler) {
          options.signal.removeEventListener('abort', abortHandler);
        }
      }
      pending[requestId] = {
        resolve: function (value) {
          if (settled) return;
          settled = true;
          cleanup();
          resolve(value);
        },
        reject: function (err) {
          if (settled) return;
          settled = true;
          cleanup();
          reject(err);
        },
        onProgress: typeof options.onProgress === 'function' ? options.onProgress : null,
        onPartial: typeof options.onPartial === 'function' ? options.onPartial : null
      };
      if (options.signal) {
        if (options.signal.aborted) {
          cleanup();
          reject(new Error('Request cancelled'));
          return;
        }
        abortHandler = function () {
          var entry = pending[requestId];
          if (!entry) return;
          try {
            bridge.postMessage({
              requestId: 'cancel-' + (++seq),
              op: 'request.cancel',
              payload: { requestId: requestId }
            });
          } catch (e) { /* native cancellation is best-effort */ }
          entry.reject(new Error('Request cancelled'));
        };
        options.signal.addEventListener('abort', abortHandler, { once: true });
      }
      try {
        bridge.postMessage({ requestId: requestId, op: op, payload: payload || {} });
      } catch (err) {
        var entry = pending[requestId];
        if (entry) entry.reject(err);
      }
    });
  }

  // Resolved by AppBridgeMessageHandler.swift via evaluateJavaScript.
  window.__clawixResolve = function (requestId, result) {
    var entry = pending[requestId];
    if (!entry) return;
    entry.resolve(result);
  };
  window.__clawixReject = function (requestId, message) {
    var entry = pending[requestId];
    if (!entry) return;
    entry.reject(new Error(message || 'clawix call failed'));
  };
  window.__clawixDispatch = function (eventName, data) {
    if (eventName === 'request.progress' && data && data.requestId) {
      var entry = pending[data.requestId];
      if (entry && entry.onProgress) {
        try { entry.onProgress(data.progress || null); } catch (e) { /* swallow progress errors */ }
      }
    }
    if (eventName === 'request.partial' && data && data.requestId) {
      var partialEntry = pending[data.requestId];
      if (partialEntry && partialEntry.onPartial) {
        try { partialEntry.onPartial(data.partial || null); } catch (e) { /* swallow partial errors */ }
      }
    }
    var bucket = listeners[eventName];
    if (!bucket) return;
    bucket.slice().forEach(function (cb) {
      try { cb(data); } catch (e) { /* swallow listener errors */ }
    });
  };

  function on(name, cb) {
    if (!listeners[name]) listeners[name] = [];
    listeners[name].push(cb);
  }
  function off(name, cb) {
    var bucket = listeners[name];
    if (!bucket) return;
    var idx = bucket.indexOf(cb);
    if (idx !== -1) bucket.splice(idx, 1);
  }

  // The native side fills window.__clawixContext synchronously via
  // userContentController.addUserScript(forMainFrame:atDocumentStart),
  // injected from AppSurfaceView right before this SDK script.
  var ctx = window.__clawixContext || { app: {}, user: {} };

  window.clawix = {
    app: ctx.app,
    user: ctx.user,
    storage: {
      get: function (key) { return send('storage.get', { key: String(key) }); },
      set: function (key, value) { return send('storage.set', { key: String(key), value: value }); },
      delete: function (key) { return send('storage.delete', { key: String(key) }); },
      keys: function () { return send('storage.keys'); }
    },
    agent: {
      sendMessage: function (text) { return send('agent.sendMessage', { text: String(text || '') }); },
      callTool: function (opts) {
        var tool = (opts && opts.tool) ? String(opts.tool) : '';
        var args = (opts && opts.args) ? opts.args : {};
        return send('agent.callTool', { tool: tool, args: args });
      }
    },
    capabilities: {
      list: function () { return send('capabilities.list'); },
      contracts: function () { return send('capabilities.contracts'); },
      riskMap: function () { return send('capabilities.riskMap'); }
    },
    search: {
      query: function (opts) {
        opts = opts || {};
        return send('search.query', {
          query: String(opts.query || opts.text || ''),
          collections: Array.isArray(opts.collections) ? opts.collections : [],
          limit: opts.limit,
          offset: opts.offset,
          cursor: opts.cursor,
          facets: Array.isArray(opts.facets) ? opts.facets : []
        }, { signal: opts.signal, onProgress: opts.onProgress, onPartial: opts.onPartial });
      }
    },
    db: {
      query: function (opts) {
        opts = opts || {};
        return send('db.query', {
          collection: String(opts.collection || ''),
          filter: opts.filter || {},
          search: opts.search == null ? opts.query : opts.search,
          sort: opts.sort,
          limit: opts.limit,
          offset: opts.offset,
          cursor: opts.cursor,
          facets: Array.isArray(opts.facets) ? opts.facets : []
        }, { signal: opts.signal, onProgress: opts.onProgress, onPartial: opts.onPartial });
      }
    },
    resources: {
      list: function (opts) {
        opts = opts || {};
        return send('resources.list', {
          status: opts.status == null ? null : String(opts.status),
          kind: opts.kind == null ? null : String(opts.kind)
        }, { signal: opts.signal, onProgress: opts.onProgress, onPartial: opts.onPartial });
      },
      read: function (idOrOpts, opts) {
        var input = typeof idOrOpts === 'object' && idOrOpts !== null ? idOrOpts : (opts || {});
        var id = typeof idOrOpts === 'string' ? idOrOpts : String(input.id || '');
        return send('resources.read', {
          id: id,
          maxBytes: input.maxBytes
        }, { signal: input.signal, onProgress: input.onProgress, onPartial: input.onPartial });
      }
    },
    system: {
      telemetry: {
        snapshot: function (opts) {
          opts = opts || {};
          return send('system.telemetry.snapshot', {
            source: opts.source == null ? 'local' : String(opts.source),
            metricKeys: Array.isArray(opts.metricKeys) ? opts.metricKeys : [],
            includeUnavailable: opts.includeUnavailable !== false
          }, { signal: opts.signal, onProgress: opts.onProgress, onPartial: opts.onPartial });
        },
        history: function (opts) {
          opts = opts || {};
          return send('system.telemetry.history', {
            metricKey: String(opts.metricKey || opts.key || ''),
            range: opts.range == null ? '1h' : String(opts.range)
          }, { signal: opts.signal, onProgress: opts.onProgress, onPartial: opts.onPartial });
        }
      }
    },
    ui: {
      setTitle: function (title) { return send('ui.setTitle', { title: String(title || '') }); },
      setBadge: function (text) {
        return send('ui.setBadge', { text: text == null ? null : String(text) });
      },
      openExternal: function (url) { return send('ui.openExternal', { url: String(url || '') }); }
    },
    events: { on: on, off: off }
  };

  // Best-effort focus/blur events the SDK emits on its own without
  // needing a round trip to native (handlers can still subscribe via
  // events.on('focus' | 'blur')).
  window.addEventListener('focus', function () {
    window.__clawixDispatch('focus', null);
  });
  window.addEventListener('blur', function () {
    window.__clawixDispatch('blur', null);
  });
})();
"""#
