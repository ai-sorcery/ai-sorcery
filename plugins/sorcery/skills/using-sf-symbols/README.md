# using-sf-symbols

Drops two scripts into `scripts/` that turn Apple's free SF Symbols catalog into a no-friction icon source: keyword search across the system catalog, and named-symbol → `viewBox="0 0 1 1"` SVG with `fill="currentColor"`.

The scripts are self-contained and use only public AppKit / Vision APIs — no automation permissions, no SF Symbols.app dependency. The catalog they read ships with macOS itself.

The skill does not depend on Apple's SF Symbols.app. If a designer wants the visual browser anyway, `brew install --cask sf-symbols` is the one-line install — no wrapper needed.

See [`SKILL.md`](SKILL.md) for the trigger description Claude reads, install commands, and the search → convert workflow.
