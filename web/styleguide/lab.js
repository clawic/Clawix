/* ============================================================
   Clawix Style System - LAB behaviors (additive, non-shared).
   Wires every new x-* component. Loads alongside (after) app.js
   and never touches the shared dropdown/menu code, so the
   canonical pages are unaffected. Runs on DOMContentLoaded,
   which fires after the deferred app.js has executed.
   ============================================================ */
(function () {
  "use strict";
  var ic = function (n, cls) { return '<svg class="ic' + (cls ? " " + cls : "") + '"><use href="icons.svg#i-' + n + '"/></svg>'; };
  var $ = function (s, r) { return (r || document).querySelector(s); };
  var $$ = function (s, r) { return [].slice.call((r || document).querySelectorAll(s)); };

  /* ---------- the core: place a floating element as fixed ----------
     Anchored to a viewport rect, flips up when there is no room
     below, and clamps inside the viewport. Because it is
     position:fixed with a high z-index it can never be clipped by
     an overflow:hidden ancestor or hidden under a sibling stack. */
  function place(menu, rect, opts) {
    opts = opts || {};
    var gap = opts.gap == null ? 6 : opts.gap;
    menu.style.position = "fixed";
    menu.style.right = "auto"; menu.style.bottom = "auto";
    menu.style.top = "0px"; menu.style.left = "0px";
    var mw = menu.offsetWidth, mh = menu.offsetHeight;
    var vw = window.innerWidth, vh = window.innerHeight;
    var below = vh - rect.bottom, above = rect.top;
    var up = opts.prefer === "up" || (below < mh + gap + 8 && above > below);
    var top = up ? Math.max(8, rect.top - gap - mh) : Math.min(vh - mh - 8, rect.bottom + gap);
    var align = opts.align || "start", left;
    if (align === "end") left = rect.right - mw;
    else if (align === "center") left = rect.left + rect.width / 2 - mw / 2;
    else left = rect.left;
    if (opts.side === "right") { left = rect.right - 4; top = Math.max(8, Math.min(rect.top - 6, vh - mh - 8)); }
    left = Math.max(8, Math.min(left, vw - mw - 8));
    menu.style.top = top + "px"; menu.style.left = left + "px";
    menu.classList.toggle("up", !!up && opts.side !== "right");
  }

  /* registry of open anchored menus, repositioned on scroll/resize */
  var anchored = [];
  function track(menu, getRect, opts) { anchored.push({ m: menu, r: getRect, o: opts }); }
  function untrack(menu) { anchored = anchored.filter(function (a) { return a.m !== menu; }); }
  function reflow() { anchored.forEach(function (a) { if (a.m.classList.contains("open")) place(a.m, a.r(), a.o); }); }
  window.addEventListener("scroll", reflow, true);
  window.addEventListener("resize", reflow);

  function closeSubs(scope) { $$(".x-sub.open", scope || document).forEach(function (s) { s.classList.remove("open"); untrack(s); }); }
  function closeMenus(except) {
    $$(".x-dd.open").forEach(function (d) {
      if (d === except) return;
      d.classList.remove("open");
      var m = $(".x-menu", d); if (m) { m.classList.remove("open"); untrack(m); }
      closeSubs(d);
    });
    $$(".x-menu.x-ctx.open").forEach(function (m) { if (m !== (except && $(".x-menu", except))) { m.classList.remove("open"); untrack(m); closeSubs(m); } });
  }

  /* ---------- dropdowns, comboboxes, submenus ---------- */
  function wireDropdowns() {
    $$(".x-dd").forEach(function (dd) {
      var trigger = $(".x-dd-trigger", dd) || dd.firstElementChild;
      var menu = $(".x-menu", dd);
      if (!trigger || !menu) return;
      var search = $(".x-search input", menu);
      var valOut = $(".x-dd-val", dd);

      function open() {
        closeMenus(dd);
        dd.classList.add("open");
        var rect = function () { return trigger.getBoundingClientRect(); };
        var opts = { align: dd.getAttribute("data-align") || "start", prefer: dd.getAttribute("data-side") === "top" ? "up" : null };
        place(menu, rect(), opts); menu.classList.add("open"); track(menu, rect, opts);
        if (search) { search.value = ""; filter(""); setTimeout(function () { search.focus(); }, 0); reflow(); }
      }
      function close() { dd.classList.remove("open"); menu.classList.remove("open"); untrack(menu); closeSubs(dd); }
      function filter(q) {
        q = (q || "").toLowerCase();
        var any = false;
        $$(".x-item", menu).forEach(function (it) {
          if (it.classList.contains("x-has-sub")) return;
          var hit = it.textContent.toLowerCase().indexOf(q) > -1;
          it.style.display = hit ? "" : "none"; if (hit) any = true;
        });
        var empty = $(".x-empty-row", menu);
        if (empty) empty.style.display = any ? "none" : "";
      }

      trigger.addEventListener("click", function (e) {
        e.stopPropagation();
        if (dd.classList.contains("open")) close(); else open();
      });
      if (search) search.addEventListener("input", function () { filter(search.value); reflow(); });

      $$(".x-item", menu).forEach(function (it) {
        if (it.classList.contains("x-has-sub")) {
          var sub = $(".x-sub", it);
          it.addEventListener("mouseenter", function () {
            closeSubs(menu);
            if (!sub) return;
            var r = function () { return it.getBoundingClientRect(); };
            place(sub, r(), { side: "right" }); sub.classList.add("open"); track(sub, r, { side: "right" });
          });
          $$(".x-item", sub).forEach(function (si) {
            si.addEventListener("click", function (e) { e.stopPropagation(); pick(si); });
          });
          return;
        }
        it.addEventListener("mouseenter", function () { closeSubs(menu); });
        it.addEventListener("click", function (e) { e.stopPropagation(); pick(it); });
      });
      function pick(it) {
        if (it.getAttribute("data-pick") === null && !dd.hasAttribute("data-select") && !valOut) { /* plain action */ close(); return; }
        $$(".x-item.on", menu).forEach(function (x) { x.classList.remove("on"); });
        it.classList.add("on");
        if (valOut) valOut.textContent = (it.getAttribute("data-label") || it.childNodes[0].textContent || it.textContent).trim();
        close();
      }
    });
  }

  /* ---------- right-click context menus ---------- */
  function wireContext() {
    $$("[data-ctx]").forEach(function (target) {
      var menu = $(target.getAttribute("data-ctx"));
      if (!menu) return;
      target.addEventListener("contextmenu", function (e) {
        e.preventDefault(); closeMenus();
        menu.classList.add("x-ctx");
        var r = function () { return { left: e.clientX, right: e.clientX, top: e.clientY, bottom: e.clientY, width: 0, height: 0 }; };
        place(menu, r(), { align: "start", gap: 2 }); menu.classList.add("open");
        $$(".x-item", menu).forEach(function (it) {
          if (it.__wired) return; it.__wired = 1;
          it.addEventListener("click", function (ev) { ev.stopPropagation(); menu.classList.remove("open"); closeSubs(menu); });
        });
      });
    });
  }

  document.addEventListener("click", function () { closeMenus(); });

  /* ---------- overlays: modal / drawer / sheet ---------- */
  function wireOverlays() {
    $$("[data-x-open]").forEach(function (btn) {
      btn.addEventListener("click", function (e) {
        e.stopPropagation();
        var sc = $(btn.getAttribute("data-x-open"));
        if (sc) sc.classList.add("show");
      });
    });
    $$(".x-scrim").forEach(function (sc) {
      sc.addEventListener("click", function (e) { if (e.target === sc) sc.classList.remove("show"); });
      $$("[data-x-close]", sc).forEach(function (b) { b.addEventListener("click", function () { sc.classList.remove("show"); }); });
    });
    window.addEventListener("keydown", function (e) {
      if (e.key !== "Escape") return;
      var open = $$(".x-scrim.show"); if (open.length) open[open.length - 1].classList.remove("show");
      var ck = $(".x-cmdk-scrim.show"); if (ck) ck.classList.remove("show");
    });
  }

  /* ---------- toasts ---------- */
  function toastRegion() {
    var r = $(".x-toast-region");
    if (!r) { r = document.createElement("div"); r.className = "x-toast-region"; document.body.appendChild(r); }
    return r;
  }
  function spawnToast(type, title, desc, action) {
    var map = { success: ["check", "var(--ok)"], error: ["alert", "var(--danger)"], warn: ["info", "var(--warn)"], info: ["info", "var(--text-2)"] };
    var m = map[type] || map.info;
    var el = document.createElement("div"); el.className = "x-toast";
    el.innerHTML = '<svg class="ic s" style="color:' + m[1] + '"><use href="icons.svg#i-' + m[0] + '"/></svg>' +
      '<div><div class="tt">' + (title || "Notification") + "</div>" + (desc ? '<div class="td">' + desc + "</div>" : "") + "</div>" +
      (action ? '<span class="ac">' + action + "</span>" : "");
    function dismiss() { el.classList.add("out"); setTimeout(function () { el.remove(); }, 200); }
    el.addEventListener("click", function (e) { if (e.target.classList.contains("ac")) dismiss(); });
    toastRegion().appendChild(el);
    setTimeout(dismiss, 3600);
  }
  function wireToasts() {
    $$("[data-x-toast]").forEach(function (b) {
      b.addEventListener("click", function (e) {
        e.stopPropagation();
        spawnToast(b.getAttribute("data-x-toast"), b.getAttribute("data-title"), b.getAttribute("data-desc"), b.getAttribute("data-action"));
      });
    });
  }

  /* ---------- command palette (⌘K) ---------- */
  function ensurePalette() {
    var sc = $(".x-cmdk-scrim");
    if (sc) return sc;
    sc = document.createElement("div"); sc.className = "x-cmdk-scrim";
    var items = [
      ["plus", "New chat", "⌘N"], ["search", "Search chats", "⌘G"], ["terminal", "Open terminal", "⌘J"],
      ["git", "Review my diff", ""], ["settings", "Open settings", "⌘,"], ["puzzle", "Browse skills", "⌘⇧K"],
      ["file", "Go to file…", "⌘P"], ["sparkles", "Explain this repo", ""], ["cpu", "Run on this Mac", ""]
    ];
    sc.innerHTML = '<div class="x-cmdk x-surface"><div class="top">' + ic("search") +
      '<input placeholder="Search actions, files and chats…" /><span class="kbd soft">esc</span></div>' +
      '<div class="list">' + items.map(function (it, i) {
        return '<div class="ci' + (i === 0 ? " on" : "") + '">' + ic(it[0], "s") + it[1] +
          (it[2] ? '<span class="sc"><span class="kbd soft">' + it[2] + "</span></span>" : "") + "</div>";
      }).join("") + "</div></div>";
    document.body.appendChild(sc);
    return sc;
  }
  function wirePalette() {
    var sc = ensurePalette();
    var input = $("input", sc), list = $(".list", sc);
    function rows() { return $$(".ci", list).filter(function (r) { return r.style.display !== "none"; }); }
    function open() { sc.classList.add("show"); input.value = ""; $$(".ci", list).forEach(function (r) { r.style.display = ""; }); mark(rows()[0]); setTimeout(function () { input.focus(); }, 0); }
    function close() { sc.classList.remove("show"); }
    function mark(r) { $$(".ci", list).forEach(function (x) { x.classList.remove("on"); }); if (r) r.classList.add("on"); }
    input.addEventListener("input", function () {
      var q = input.value.toLowerCase();
      $$(".ci", list).forEach(function (r) { r.style.display = r.textContent.toLowerCase().indexOf(q) > -1 ? "" : "none"; });
      mark(rows()[0]);
    });
    input.addEventListener("keydown", function (e) {
      var rs = rows(), cur = rs.indexOf($(".ci.on", list));
      if (e.key === "ArrowDown") { e.preventDefault(); mark(rs[Math.min(rs.length - 1, cur + 1)]); }
      else if (e.key === "ArrowUp") { e.preventDefault(); mark(rs[Math.max(0, cur - 1)]); }
      else if (e.key === "Enter") { e.preventDefault(); close(); }
    });
    sc.addEventListener("click", function (e) { if (e.target === sc) close(); if (e.target.closest(".ci")) close(); });
    $$("[data-x-cmdk]").forEach(function (b) { b.addEventListener("click", function (e) { e.stopPropagation(); open(); }); });
    window.addEventListener("keydown", function (e) {
      if ((e.metaKey || e.ctrlKey) && e.key.toLowerCase() === "k") { e.preventDefault(); sc.classList.contains("show") ? close() : open(); }
    });
  }

  /* ---------- tag input ---------- */
  function wireTagInputs() {
    $$(".x-tagin").forEach(function (box) {
      var input = $("input", box);
      function add(v) { v = v.trim(); if (!v) return; var t = document.createElement("span"); t.className = "tg"; t.innerHTML = v + '<span class="rm">' + ic("x", "xs") + "</span>"; box.insertBefore(t, input); }
      input.addEventListener("keydown", function (e) {
        if (e.key === "Enter" || e.key === ",") { e.preventDefault(); add(input.value); input.value = ""; }
        else if (e.key === "Backspace" && !input.value) { var tags = $$(".tg", box); if (tags.length) tags[tags.length - 1].remove(); }
      });
      box.addEventListener("click", function (e) { var rm = e.target.closest(".rm"); if (rm) rm.closest(".tg").remove(); else input.focus(); });
    });
  }

  /* ---------- OTP / code input ---------- */
  function wireOtp() {
    $$(".x-otp").forEach(function (box) {
      var ins = $$("input", box);
      ins.forEach(function (inp, i) {
        inp.addEventListener("input", function () { inp.value = inp.value.replace(/\D/g, "").slice(-1); if (inp.value && ins[i + 1]) ins[i + 1].focus(); });
        inp.addEventListener("keydown", function (e) { if (e.key === "Backspace" && !inp.value && ins[i - 1]) ins[i - 1].focus(); });
      });
    });
  }

  /* ---------- copy buttons ---------- */
  function wireCopy() {
    $$("[data-x-copy]").forEach(function (b) {
      b.addEventListener("click", function () {
        var v = b.getAttribute("data-x-copy") || "";
        try { navigator.clipboard && navigator.clipboard.writeText(v); } catch (e) {}
        b.classList.add("x-copied"); setTimeout(function () { b.classList.remove("x-copied"); }, 1200);
      });
    });
  }

  /* ---------- textarea autosize ---------- */
  function wireAutosize() {
    $$("textarea[data-x-autosize]").forEach(function (t) {
      function fit() { t.style.height = "auto"; t.style.height = Math.min(220, t.scrollHeight) + "px"; }
      t.addEventListener("input", fit); fit();
    });
  }

  /* ---------- password reveal ---------- */
  function wireReveal() {
    $$("[data-x-reveal]").forEach(function (b) {
      b.addEventListener("click", function () {
        var inp = $(b.getAttribute("data-x-reveal"));
        if (!inp) return; inp.type = inp.type === "password" ? "text" : "password";
        b.classList.toggle("on");
      });
    });
  }

  /* ---------- tabs that switch panels ---------- */
  function wireTabs() {
    $$("[data-x-tabs]").forEach(function (group) {
      var scope = group.getAttribute("data-x-tabs");
      var panels = $$('[data-x-panel][data-x-scope="' + scope + '"]');
      $$("[data-x-tab]", group).forEach(function (tab) {
        tab.addEventListener("click", function () {
          $$("[data-x-tab]", group).forEach(function (t) { t.classList.remove("on"); });
          tab.classList.add("on");
          var key = tab.getAttribute("data-x-tab");
          panels.forEach(function (p) { p.style.display = p.getAttribute("data-x-panel") === key ? "" : "none"; });
        });
      });
    });
  }

  /* ---------- dual-knob range ---------- */
  function wireRanges() {
    $$(".x-range").forEach(function (sl) {
      var min = parseFloat(sl.dataset.min || "0"), max = parseFloat(sl.dataset.max || "100");
      var fi = $(".fi", sl), knobs = $$(".kn", sl);
      var out = sl.dataset.out ? $(sl.dataset.out) : null;
      var vals = knobs.map(function (k) { return parseFloat(k.dataset.value || "0"); });
      function render() {
        vals.sort(function (a, b) { return a - b; });
        var p0 = (vals[0] - min) / (max - min) * 100, p1 = (vals[1] - min) / (max - min) * 100;
        knobs[0].style.left = p0 + "%"; knobs[1].style.left = p1 + "%";
        fi.style.left = p0 + "%"; fi.style.width = (p1 - p0) + "%";
        if (out) out.textContent = Math.round(vals[0]) + " – " + Math.round(vals[1]);
      }
      knobs.forEach(function (kn, i) {
        kn.addEventListener("mousedown", function (e) {
          e.preventDefault(); e.stopPropagation();
          function move(ev) { var r = sl.getBoundingClientRect(); var v = min + (ev.clientX - r.left) / r.width * (max - min); vals[i] = Math.max(min, Math.min(max, v)); render(); }
          function up() { window.removeEventListener("mousemove", move); window.removeEventListener("mouseup", up); }
          window.addEventListener("mousemove", move); window.addEventListener("mouseup", up);
        });
      });
      render();
    });
  }

  /* ---------- flexible table: sort / select / expand ---------- */
  function wireTables() {
    $$(".x-table").forEach(function (table) {
      var head = $(".thead", table);
      var allBox = head ? $('input[type="checkbox"]', head) : null;
      if (allBox) allBox.addEventListener("change", function () {
        $$(".trow", table).forEach(function (row) { var cb = $('input[type="checkbox"]', row); if (cb) { cb.checked = allBox.checked; row.classList.toggle("sel", allBox.checked); } });
      });
      $$(".trow", table).forEach(function (row) {
        var cb = $('input[type="checkbox"]', row);
        if (cb) cb.addEventListener("change", function () { row.classList.toggle("sel", cb.checked); });
        var caret = $(".caret", row);
        if (caret) caret.addEventListener("click", function (e) { e.stopPropagation(); row.classList.toggle("open"); });
      });
      $$(".th[data-sort]", table).forEach(function (th, idx) {
        th.addEventListener("click", function () {
          var desc = th.classList.contains("sorted") && !th.__desc; th.__desc = desc;
          $$(".th", head).forEach(function (h) { h.classList.remove("sorted"); var a = $(".ar", h); if (a) a.classList.remove("desc"); });
          th.classList.add("sorted"); var ar = $(".ar", th); if (ar) ar.classList.toggle("desc", desc);
          var col = th.getAttribute("data-sort");
          var rows = $$(".trow", table);
          rows.sort(function (a, b) {
            var av = a.getAttribute("data-" + col) || "", bv = b.getAttribute("data-" + col) || "";
            var an = parseFloat(av), bn = parseFloat(bv);
            var r = (!isNaN(an) && !isNaN(bn)) ? an - bn : av.localeCompare(bv);
            return desc ? -r : r;
          });
          rows.forEach(function (r) { table.appendChild(r); });
        });
      });
    });
  }

  /* ---------- steppers (+/- numeric) ---------- */
  function wireSteppers() {
    $$(".x-stepper").forEach(function (st) {
      var val = $(".v", st), min = parseFloat(st.dataset.min || "0"), max = parseFloat(st.dataset.max || "999"), step = parseFloat(st.dataset.step || "1");
      var btns = $$(".b", st);
      function set(n) { n = Math.max(min, Math.min(max, n)); val.textContent = n; }
      if (btns[0]) btns[0].addEventListener("click", function () { set(parseFloat(val.textContent) - step); });
      if (btns[1]) btns[1].addEventListener("click", function () { set(parseFloat(val.textContent) + step); });
    });
  }

  /* ---------- live character count ---------- */
  function wireCount() {
    $$("[data-x-count]").forEach(function (inp) {
      var out = $(inp.getAttribute("data-x-count")), max = inp.getAttribute("maxlength");
      function upd() { if (out) out.textContent = inp.value.length + (max ? " / " + max : ""); }
      inp.addEventListener("input", upd); upd();
    });
  }

  /* ---------- dropzone visual feedback ---------- */
  function wireDropzones() {
    $$(".x-dropzone").forEach(function (z) {
      ["dragenter", "dragover"].forEach(function (ev) { z.addEventListener(ev, function (e) { e.preventDefault(); z.classList.add("drag"); }); });
      ["dragleave", "drop"].forEach(function (ev) { z.addEventListener(ev, function (e) { e.preventDefault(); z.classList.remove("drag"); }); });
    });
  }

  function init() {
    wireDropdowns(); wireContext(); wireOverlays(); wireToasts(); wirePalette();
    wireTagInputs(); wireOtp(); wireCopy(); wireAutosize(); wireReveal();
    wireTabs(); wireRanges(); wireTables(); wireSteppers(); wireCount(); wireDropzones();
  }
  if (document.readyState === "loading") document.addEventListener("DOMContentLoaded", init);
  else init();
})();
