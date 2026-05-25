# Style — Clawix design system: laboratory and standard

This folder is the centralized, platform-agnostic source of truth for how
Clawix looks and moves, expressed as a mock web interface. It plays two roles
at once:

- **The standard.** Every visual rule, token, component and screen is defined
  once here and shown live, in both light and dark.
- **The laboratory.** The place to iterate on the visual language in isolation,
  before any change touches product code (macOS, iOS, Android, web).

Work happens here first and propagates outward. Product code conforms to what is
decided here. This is the visual companion to `../STYLE.md` (the prose canon) and
`../docs/ui/` (the enforceable registry): when they disagree on a value, this is
where it gets seen and decided; those are where the decision is written down and
enforced.

## The five principles

1. **Centralization is the law.** No raw value lives in markup or a component.
   Every color, size, height, weight, radius, gap, duration, curve and shadow is
   a token in `tokens.css`. If you need a value that does not exist, add a token,
   do not hardcode. The test for any change: editing one token must visibly
   propagate everywhere it applies. Many tokens at first is fine; they get
   consolidated over time, never scattered.

2. **One source per concern.** `tokens.css` holds values, `ui.css` holds
   components and layout, `app.js` holds the shared chrome and behaviors,
   `icons.svg` holds the icons. Pages and screens are thin: they only compose
   these. Never redefine a component inside a page.

3. **Components are the design law.** A page that looks wrong is using a
   component wrong, so fix the page, not the component. Change a component only
   when the rule itself changes, and change only the aspect that changed.

4. **Everything is shown, in both themes.** Every rule has a live, applied
   example. Every page works in light and dark via the global toggle. English
   only, neutral demo data.

5. **Propagation, not duplication.** This is upstream of platform code. Platforms
   share semantic tokens and the same iconography; they diverge only in native
   materials and in fonts where each OS reads better.

## How to iterate (the working method)

- **Never delete a curated treatment to force a fundamental.** Before removing or
  overriding any existing visual treatment, it must be compared and explicitly
  discarded by the user. A treatment that was deliberate is not drift.
- **Surface drift, don't fix it silently.** When a surface breaks a rule or has
  quietly acquired a different radius, curve, weight or color, record it in
  `lab/discordances.html`: render A and B side by side, describe exactly what
  differs, and pose one specific question. The user decides on a validated
  visual, not on abstract rule text.
- **Record verdicts, then fold them in.** Settled calls land in
  `lab/decisions.html` and are then pushed into `tokens.css` / `ui.css` so the
  standard and every screen update together. Staging that is decided but not yet
  folded lives in `lab/`.
- **Keep app components covered.** Components that exist in the app but are not
  yet documented are added to the fundamentals, not left out.

## Structure

```
style/
  tokens.css        THE single source of values (light + dark)
  ui.css            components + layout (imports tokens.css)
  app.js            shared chrome (top nav, theme toggle, window frame) + behaviors
  icons.svg         the one icon sprite
  assets/fonts/     vendored font, so the folder is self-contained
  index.html        hub
  foundations.html  the rules, each shown applied
  components.html   the primitive gallery
  icons.html        iconography + sizing scale + usage
  chat-catalog.html every chat element as its own component
  menus.html        popups / overlays / advanced components
  screen-*.html     mocked app interfaces (archetypes covering every surface)
  lab/
    index.html        the lab hub + the working method
    discordances.html side-by-side A/B drift with a question
    decisions.html    the decisions ledger
    lab-*.html        staging experiments (overlays, forms, data, resolved)
```

Pages at the root use bare relative refs. Subfolder pages (`lab/`) set
`data-base="../"` on `<body>`; `app.js` reads it and prefixes every generated
href and icon ref, so the same chrome works at any depth.

## Run and verify

Serve over HTTP, never `file://` (the icon sprite breaks under a unique origin):

```
cd clawix/style
python3 -m http.server 8800
# open http://localhost:8800/
```

Always check both themes. The folder is self-contained: the font is vendored in
`assets/fonts/`, nothing depends on the web build output.

## Public hygiene

This is in the public repository. English only, neutral demo data, no personal
data, no internal markers, no signing identities, no private absolute paths.
