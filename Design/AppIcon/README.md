# Paired Signal app icon

`Paired Signal` is CodeIsland's provider-neutral identity: two Mac/iPhone
islands create a focused connection channel, with one signal point marking the
exact item that needs attention.

The three SVG files are the deterministic source of truth:

- `paired-signal-light.svg` — default appearance;
- `paired-signal-dark.svg` — dark Home Screen appearance; and
- `paired-signal-tinted.svg` — grayscale luminance map for iOS tinting.

Run `scripts/generate-app-icons.sh` from any directory to regenerate the iOS
asset catalog PNGs, `Legacy/` inspection sizes, and `manifest.json`. The
generated artwork is a full, opaque 1024×1024 square. Do not pre-apply Apple's
rounded icon mask. Legacy renders stay outside `AppIcon.appiconset` because
modern Xcode derives runtime sizes from the three universal masters.

The visual concept was explored with image generation, then redrawn as simple
SVG geometry so shipped assets remain repeatable, inspectable, and sharp at
small sizes.
