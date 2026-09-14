# Enterprise SSO Bridge icon set

A suspension bridge in elevation: two towers, a main cable sagging to meet the deck at midspan, hangers, and side spans running down to their anchorages. The accent is International Orange (#E8420B), the colour the Golden Gate is actually painted, which is also the one hue that holds contrast on both a white Chromium toolbar and a near-black Gecko one.

Open `index.html` for the full plate: rationale, cable geometry, size ladder, both toolbars, badge states, and palette.

## Contents

- `svg/` — the four masters: `app-icon.svg`, `app-icon-small.svg` (the cut used at 16 and 32 px), `toolbar-icon.svg`, `toolbar-icon-16.svg`.
- `EnterpriseSSOBridge.icns` and `AppIcon.iconset/` — the app icon, assembled with `iconutil`.
- `extension/icon-16.png`, `icon-32.png`, `icon-48.png`, `icon-128.png` — the manifests' `icons` and `action.default_icon` keys, identical in both builds. `icon-16@2x.png` is for plate rendering only.
- `app-icon-1024.png` — flat image for a README or a release page.
- `make.py` — regenerates every SVG. One `Bridge` class takes the span, deck, tower, cable, and anchorage dimensions and emits the elevation; the cables are sampled parabolas, and the body is a sampled superellipse (`|x|^5 + |y|^5 = 1`).

## Rebuilding

```sh
python3 make.py                     # rewrites svg/ from the geometry
rsvg-convert -w 1024 -h 1024 svg/app-icon.svg -o app-icon-1024.png
iconutil -c icns AppIcon.iconset -o EnterpriseSSOBridge.icns
```

`make.py` emits only the SVG masters. The PNGs and the `.icns` are rendered from them with `rsvg-convert` and `iconutil`, and are committed so a build can copy them without needing librsvg installed.

The toolbar icon does not change with Handoff state. State is the badge's job, which the Extension already owns.
