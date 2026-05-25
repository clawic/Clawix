/* ============================================================
   Clawix Style System - shared chrome & behaviors.
   Single source for: top nav, theme, the macOS window frame,
   the chat sidebar, and every interactive behavior. Screens
   stay thin: they declare data-shell and provide a <template
   id="main">; this file assembles the rest.
   ============================================================ */
(function () {
  "use strict";
  var root = document.documentElement;
  var body = document.body;
  var ic = function (n, cls) { return '<svg class="ic' + (cls ? ' ' + cls : '') + '"><use href="icons.svg#i-' + n + '"/></svg>'; };

  /* ---------- top navigation (identical on every page) ----------
     Reference pages stay as flat links; every mocked screen lives in
     a single "Screens" dropdown so the bar never overflows as the
     archetype set grows. */
  var REF = [
    { id: "foundations", label: "Foundations", href: "foundations.html" },
    { id: "components", label: "Components", href: "components.html" },
    { id: "chat", label: "Chat catalog", href: "chat-catalog.html" },
    { id: "menus", label: "Menus & popups", href: "menus.html" }
  ];
  var SCREENS = [
    { id: "sidebar", label: "Home / Sidebar", href: "screen-sidebar.html", group: "App" },
    { id: "conversation", label: "Conversation", href: "screen-conversation.html", group: "App" },
    { id: "settings", label: "Settings", href: "screen-settings.html", group: "App" },
    { id: "tool-computer", label: "On this Mac", href: "screen-tool-computer.html", group: "Tools" },
    { id: "tool-browser", label: "Browser", href: "screen-tool-browser.html", group: "Tools" },
    { id: "tool-terminal", label: "Terminal", href: "screen-tool-terminal.html", group: "Tools" },
    { id: "master-detail", label: "Master–detail · Secrets", href: "screen-master-detail.html", group: "Patterns" },
    { id: "browse", label: "Browse / grid · Skills", href: "screen-browse.html", group: "Patterns" },
    { id: "tabbed", label: "Tabbed workspace · Index", href: "screen-tabbed.html", group: "Patterns" },
    { id: "dashboard", label: "Dashboard · Network", href: "screen-dashboard.html", group: "Patterns" },
    { id: "workbench", label: "Workbench · Database", href: "screen-workbench.html", group: "Patterns" }
  ];
  var current = body.getAttribute("data-page") || "";
  var screenOn = SCREENS.some(function (s) { return s.id === current; });
  var screensMenu = "", lastGroup = "";
  SCREENS.forEach(function (s) {
    if (s.group !== lastGroup) { screensMenu += '<div class="gh">' + s.group + "</div>"; lastGroup = s.group; }
    var sel = s.id === current;
    screensMenu += '<a class="it" href="' + s.href + '" style="text-decoration:none' + (sel ? ";background:var(--sel)" : "") + '">' + s.label +
      (sel ? '<span class="ck">' + ic("check", "xs") + "</span>" : "") + "</a>";
  });
  var nav = document.createElement("div");
  nav.className = "topbar";
  nav.innerHTML =
    '<a class="brand" href="index.html" style="text-decoration:none">Clawix <span>· Style System</span></a>' +
    '<div class="nav-links">' +
      REF.map(function (p) {
        return '<a class="nav-link' + (p.id === current ? " on" : "") + '" href="' + p.href + '">' + p.label + "</a>";
      }).join("") +
      '<span class="dropdown"><span class="nav-link js-pop' + (screenOn ? " on" : "") + '" style="cursor:pointer;display:inline-flex;align-items:center;gap:5px">Screens' + ic("chevron-down", "xs") + "</span>" +
        '<div class="pop-menu">' + screensMenu + "</div></span>" +
    "</div>" +
    '<div class="sp"></div>' +
    '<span class="tlabel">Light</span>' +
    '<label class="toggle" title="Toggle theme"><input type="checkbox" id="themeToggle"><span class="tr"></span><span class="kn"></span></label>' +
    '<span class="tlabel">Dark</span>';
  body.insertBefore(nav, body.firstChild);

  /* ---------- theme (persisted across pages) ---------- */
  var toggle = document.getElementById("themeToggle");
  var saved = localStorage.getItem("clawix-theme") || "dark";
  toggle.checked = saved === "dark";
  function applyTheme() {
    var dark = toggle.checked;
    root.setAttribute("data-theme", dark ? "dark" : "light");
    localStorage.setItem("clawix-theme", dark ? "dark" : "light");
    paintSwatches();
  }

  /* ---------- chat sidebar (shared by app screens) ---------- */
  function sidebar(active) {
    var navItem = function (icon, name, sc, on) {
      return '<div class="sb-item' + (on ? " on" : "") + '">' + ic(icon) + '<span class="nm">' + name + "</span>" +
        (sc ? '<span class="sc"><span class="kbd soft">' + sc + "</span></span>" : "") + "</div>";
    };
    var chat = function (name, on, unread) {
      return '<div class="sb-chat' + (on ? " on" : "") + '"><span class="nm">' + name + "</span>" +
        (unread ? '<span class="un"></span>' : "") + "</div>";
    };
    var head = function (name, add) {
      return '<div class="sb-head">' + ic("chevron-down", "xs") + "<span>" + name + "</span><span class=\"sp\"></span>" +
        (add ? '<span class="ad">' + ic("plus", "xs") + "</span>" : "") + "</div>";
    };
    return '<aside class="app-sidebar"><div class="sb-scroll">' +
      '<div class="sb-nav">' +
        navItem("pencil", "New chat", "⌘N", false) +
        navItem("search", "Search", "⌘G", active === "search") +
        navItem("puzzle", "Skills", "⌘⇧K", active === "skills") +
        navItem("network", "Network", "", active === "network") +
      "</div>" +
      head("Tools", true) +
      '<div class="sb-nav">' +
        navItem("cpu", "On this Mac", "", active === "computer") +
        navItem("globe", "Browser", "", active === "browser") +
        navItem("terminal", "Terminal", "", active === "terminal") +
        navItem("key", "Secrets", "", active === "secrets") +
        navItem("stack", "Index", "", active === "index") +
        navItem("database", "Database", "", active === "database") +
      "</div>" +
      head("Pinned", false) +
      '<div class="sb-nav">' + chat("Style system pages", active === "pinned", false) + "</div>" +
      head("Projects", true) +
      '<div class="sb-nav">' +
        '<div class="sb-item">' + ic("folder") + '<span class="nm">clawix</span></div>' +
        '<div class="sb-item">' + ic("folder") + '<span class="nm">landing</span></div>' +
      "</div>" +
      head("All chats", false) +
      '<div class="sb-nav">' +
        chat("Refactor the login flow", active === "conv", false) +
        chat("Migrate the database layer", false, true) +
        chat("Fix sidebar icon sizes", false, false) +
        chat("Computer Use parity", false, false) +
        chat("Wallpaper library polish", false, false) +
      "</div>" +
      "</div>" +
      '<div class="sb-foot"><div class="sb-account"><span class="av round">CX</span>' +
        '<div class="who"><div class="nm">Your account</div><div class="pl">Plus · 1,240 credits</div></div>' +
        ic("chevron-down", "xs") + "</div></div>" +
      "</aside>";
  }

  function windowFrame(title, innerHTML) {
    return '<div class="stage"><div class="win">' +
      '<div class="titlebar"><span class="lights"><i class="r"></i><i class="y"></i><i class="g"></i></span>' +
        '<span class="win-title">' + title + "</span>" +
        '<div class="tb-right"><span class="iconbtn s">' + ic("sliders", "s") + "</span></div></div>" +
      '<div class="appbody">' + innerHTML + "</div></div></div>";
  }

  /* ---------- mount screen shells ---------- */
  var shell = body.getAttribute("data-shell");
  if (shell) {
    var tpl = document.getElementById("main");
    var mainHTML = tpl ? tpl.innerHTML : "";
    var title = body.getAttribute("data-title") || "Clawix";
    var host = document.createElement("div");
    if (shell === "app") {
      host.innerHTML = windowFrame(title, sidebar(body.getAttribute("data-active") || "") +
        '<div class="content">' + mainHTML + "</div>");
    } else { /* "window": full-width content (settings) */
      host.innerHTML = windowFrame(title, '<div class="content">' + mainHTML + "</div>");
    }
    body.appendChild(host.firstChild);
  }

  /* ---------- gallery-only: swatches + icon grid ---------- */
  function paintSwatches() {
    var box = document.getElementById("swatches");
    if (!box) return;
    var cs = getComputedStyle(root);
    var names = [["--bg", "bg"], ["--card", "card"], ["--text", "text"], ["--text-2", "text-2"], ["--text-3", "text-3"], ["--strong", "strong"], ["--accent", "accent (blue)"], ["--ok", "ok (green)"], ["--warn", "warn"], ["--danger", "danger (red)"], ["--hairline", "hairline"], ["--sel", "selection"]];
    box.innerHTML = names.map(function (n) {
      var v = cs.getPropertyValue(n[0]).trim();
      return '<div class="sw"><div class="chip" style="background:' + v + '"></div><div class="meta"><div class="nm">' + n[1] + '</div><div class="val mono">' + v + "</div></div></div>";
    }).join("");
  }
  var gallery = document.getElementById("iconGallery");
  if (gallery) {
    var icons = "plus x check minus search chevron-down chevron-right chevron-left chevron-up arrow-up terminal folder file message settings sliders pencil copy trash info alert bell user calendar clock more database bot globe command send star circle loader eye home network puzzle pin archive mic paperclip sparkles cpu git chart key grid stop shield refresh download link play stack wrench".split(" ");
    gallery.innerHTML = icons.map(function (n) {
      return '<div class="icw">' + ic(n, "l") + '<span class="nm">' + n + "</span></div>";
    }).join("");
  }

  /* ---------- shared interactive behaviors (work on every page) ---------- */
  function wire() {
    var ind = document.getElementById("indet");
    if (ind) ind.indeterminate = true;

    [].forEach.call(document.querySelectorAll(".js-seg"), function (seg) {
      var i = seg.querySelector(".ind"), b = [].slice.call(seg.querySelectorAll("button"));
      function move(x) { b.forEach(function (y) { y.classList.toggle("on", y === x); }); i.style.left = x.offsetLeft + "px"; i.style.width = x.offsetWidth + "px"; }
      b.forEach(function (x) { x.addEventListener("click", function () { move(x); }); });
      move(seg.querySelector("button.on") || b[0]);
    });

    function single(sel, child, key) {
      [].forEach.call(document.querySelectorAll(sel), function (g) {
        var it = [].slice.call(g.querySelectorAll(child));
        it.forEach(function (x) { x.addEventListener("click", function () { it.forEach(function (y) { y.classList.remove(key); }); x.classList.add(key); }); });
      });
    }
    single(".js-chips", ".chip", "on");
    single(".js-tabs", ".tab", "on");
    single(".js-utabs", ".utab", "on");
    single(".js-pg", ".b", "on");
    single(".js-dots", "i", "on");
    single(".js-setnav", ".set-cat", "on");
    single(".scope-rows", ".scope-row", "on");
    single(".md-list .scroll", ".mrow", "on");

    [].forEach.call(document.querySelectorAll(".dropdown"), function (dd) {
      var tg = dd.querySelector(".js-pop");
      if (!tg) return;
      tg.addEventListener("click", function (e) {
        e.stopPropagation();
        var open = dd.classList.contains("open");
        [].forEach.call(document.querySelectorAll(".dropdown.open"), function (x) { x.classList.remove("open"); });
        if (!open) dd.classList.add("open");
      });
      [].forEach.call(dd.querySelectorAll("[data-pick]"), function (it) {
        it.addEventListener("click", function () {
          [].forEach.call(dd.querySelectorAll("[data-pick] .ck"), function (c) { c.remove(); });
          var v = dd.querySelector("[data-val]");
          if (v) v.textContent = it.childNodes[0].textContent.trim();
          it.insertAdjacentHTML("beforeend", '<span class="ck">' + ic("check", "xs") + "</span>");
          dd.classList.remove("open");
        });
      });
    });
    document.addEventListener("click", function () {
      [].forEach.call(document.querySelectorAll(".dropdown.open"), function (x) { x.classList.remove("open"); });
    });

    [].forEach.call(document.querySelectorAll(".js-acc"), function (a) {
      a.querySelector(".ah").addEventListener("click", function () { a.classList.toggle("open"); });
    });
  }

  toggle.addEventListener("change", applyTheme);
  applyTheme();
  wire();
})();


/* functional sliders (drag + click + live value) */
(function () {
  function fmt(v, step) { var dec = (String(step).split(".")[1] || "").length; return dec ? v.toFixed(dec) : String(Math.round(v)); }
  [].forEach.call(document.querySelectorAll(".slider"), function (sl) {
    var min = parseFloat(sl.dataset.min || "0"), max = parseFloat(sl.dataset.max || "100"), step = parseFloat(sl.dataset.step || "1");
    var fi = sl.querySelector(".fi"), kn = sl.querySelector(".kn2");
    if (!fi || !kn) return;
    var out = sl.dataset.out ? document.querySelector(sl.dataset.out)
      : (sl.nextElementSibling && sl.nextElementSibling.classList.contains("slider-val") ? sl.nextElementSibling : null);
    var val = sl.dataset.value != null ? parseFloat(sl.dataset.value) : min + (max - min) * (parseFloat(fi.style.width) || 0) / 100;
    function clampStep(v) { v = Math.max(min, Math.min(max, v)); v = Math.round((v - min) / step) * step + min; return Math.max(min, Math.min(max, v)); }
    function render() { var pct = (val - min) / (max - min) * 100; fi.style.width = pct + "%"; kn.style.left = pct + "%"; if (out) out.textContent = fmt(val, step) + (sl.dataset.suffix || ""); }
    function setFromX(x) { var r = sl.getBoundingClientRect(); val = clampStep(min + ((x - r.left) / r.width) * (max - min)); render(); }
    var dragging = false;
    sl.addEventListener("mousedown", function (e) { dragging = true; setFromX(e.clientX); e.preventDefault(); });
    window.addEventListener("mousemove", function (e) { if (dragging) setFromX(e.clientX); });
    window.addEventListener("mouseup", function () { dragging = false; });
    val = clampStep(val); render();
  });
})();


/* assistant "Worked for Xs" disclosure */
(function () {
  [].forEach.call(document.querySelectorAll(".js-work"), function (w) {
    var head = w.querySelector(".work-head");
    if (head) head.addEventListener("click", function () { w.classList.toggle("open"); });
  });
})();


/* collapsible sidebar sections (catalog demo) */
(function () {
  [].forEach.call(document.querySelectorAll(".js-collapse"), function (h) {
    h.addEventListener("click", function () {
      var sec = h.closest(".sb-section");
      if (sec) sec.classList.toggle("collapsed");
    });
  });
})();
