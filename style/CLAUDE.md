# CLAUDE.md

`AGENTS.md` is the canonical instruction file for this folder. Read and follow
it before changing anything here.

In short: this `style/` folder is both the **standard** (one set of tokens and
components, every rule shown live in light and dark) and the **laboratory**
(where the visual language is iterated in isolation before it touches macOS, iOS,
Android or web). Centralization is the law: no hardcoded values, everything is a
token in `tokens.css`. Never delete a curated treatment to force a rule, surface
it as a discordance in `lab/` and let the user decide on the visual.

If `CLAUDE.md` and `AGENTS.md` ever diverge, `AGENTS.md` wins. The repository-wide
rules in `../AGENTS.md` and `../CLAUDE.md` still apply on top of this.
