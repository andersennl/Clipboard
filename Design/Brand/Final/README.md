# Clipboard brand assets

Selected direction: **A · Clipboard List**.

## Apple app icon

- Canvas: 1024 × 1024.
- Background: opaque and full-bleed.
- No rounded-square mask is baked into the master; Apple applies the platform mask.
- Foreground artwork is available as separate SVG layers for Icon Composer.
- The flattened App Store PNG is RGB and has no alpha channel.
- Brand blue: `#1478A8`; foreground: `#FFFFFF`.

## Files

- `clipboard-app-icon-master.svg`: full-bleed vector master.
- `clipboard-app-store-1024.png`: flattened App Store image.
- `clipboard-icon-composer-1024.png`: Apple `ictool` validation preview.
- `clipboard-web-512.png`: website image.
- `clipboard-web-256.png`: smaller website image.
- `clipboard-favicon-64.png`: favicon-sized image.
- `clipboard-logo-mark-blue.svg`: transparent blue mark for the website.
- `IconComposer/Clipboard.icon`: native Apple Icon Composer document with three
  vector layers; glass, specular, translucency, and shadow effects are disabled.

The PNG sizes are derived from the vector master. The transparent website mark is intentionally SVG-only so it remains sharp at any size.
