# Clawix Style System

The centralized source of truth for how Clawix looks and moves: one set of
tokens and components, every rule shown live, across web, macOS, iOS and Android.

It is both the **standard** (foundations, components, iconography and mocked
screens, all driven by `tokens.css`) and the **laboratory** (`lab/`, where the
visual language is iterated in isolation before it reaches product code).

## Run it

The icon sprite needs a real origin, so serve over HTTP rather than opening the
files directly:

```bash
cd clawix/style
python3 -m http.server 8800
# then open http://localhost:8800/
```

Use the toggle in the top bar to switch light / dark; the choice persists across
pages.

## What's inside

| Path | What it is |
| --- | --- |
| `tokens.css` | Every value (color, size, radius, weight, duration, curve) as a token, light + dark. Change one and it propagates. |
| `ui.css` | All component and layout classes. Imports `tokens.css`. |
| `app.js` | Shared chrome (top nav, theme toggle, window frame) and every interactive behavior. |
| `icons.svg` | The single icon sprite. |
| `assets/fonts/` | Vendored font, so the folder is self-contained. |
| `index.html` | Hub. |
| `foundations.html` | The rules, each shown applied. |
| `components.html` | The primitive gallery. |
| `icons.html` | Iconography: the set, the sizing scale, and what each icon is for. |
| `chat-catalog.html` | Every conversation element as its own component. |
| `menus.html` | Popups, overlays and the more advanced components. |
| `screen-*.html` | Mocked app interfaces, abstracted into archetypes that cover every surface. |
| `lab/` | The iteration layer: discordances, the decisions board, and staging experiments. |

## How changes are made

1. Edit a token in `tokens.css` (or a component in `ui.css`) and confirm it
   propagates across the gallery and every screen.
2. When the app and the fundamentals diverge, record it in
   `lab/discordances.html` as a side-by-side A / B with a question, instead of
   editing one to match the other. The call is made on the visual.
3. Settled decisions go on `lab/decisions.html`, then get folded into the tokens
   and components.

The full rules for agents working here live in `AGENTS.md`.
