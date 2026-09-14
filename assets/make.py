#!/usr/bin/env python3
"""Enterprise SSO Bridge icon set: a suspension bridge, drawn from geometry."""

import math
import pathlib

OUT = pathlib.Path(__file__).parent / "svg"
OUT.mkdir(parents=True, exist_ok=True)

ORANGE = "#E8420B"
ORANGE_LIT = "#FF7A35"
CABLE = "#CBDCEC"
FIELD_TOP = "#22415E"
FIELD_BOT = "#081220"


def squircle(cx, cy, half, n=5.0, steps=720):
    pts = []
    for i in range(steps):
        t = 2 * math.pi * i / steps
        ct, st = math.cos(t), math.sin(t)
        x = math.copysign(abs(ct) ** (2.0 / n), ct)
        y = math.copysign(abs(st) ** (2.0 / n), st)
        pts.append((cx + half * x, cy + half * y))
    return "M" + " L".join(f"{x:.2f} {y:.2f}" for x, y in pts) + " Z"


def sample(f, x0, x1, steps=60):
    step = (x1 - x0) / steps
    pts = [(x0 + i * step, f(x0 + i * step)) for i in range(steps + 1)]
    return "M" + " L".join(f"{x:.1f} {y:.1f}" for x, y in pts)


class Bridge:
    """One elevation of a suspension bridge, sized by its own numbers."""

    def __init__(self, span, deck_y, deck_h, tower_x, tower_top, cable_y, sag,
                 anchor_x, anchor_y, leg_w, leg_gap, cable_w, hangers, beams):
        self.__dict__.update(locals())
        del self.self

    def main_cable(self, x):
        cx = (self.tower_x[0] + self.tower_x[1]) / 2
        half = (self.tower_x[1] - self.tower_x[0]) / 2
        return self.cable_y + self.sag * (1 - ((x - cx) / half) ** 2)

    def side_cable(self, x, tower):
        ax = self.anchor_x[tower]
        run = abs(self.tower_x[tower] - ax)
        if run == 0:  # a cut with no side spans: the cable stops at the saddle
            return self.cable_y
        drop = self.anchor_y - self.cable_y
        return self.anchor_y - drop * ((x - ax) / run) ** 2

    @property
    def saddle_w(self):
        return self.leg_gap + self.leg_w

    def on_tower(self, x):
        return any(abs(x - tx) <= self.saddle_w / 2 for tx in self.tower_x)

    def cable_at(self, x):
        # the cable runs flat over the saddle rather than dipping between the legs
        if self.on_tower(x):
            return self.cable_y
        if self.tower_x[0] <= x <= self.tower_x[1]:
            return self.main_cable(x)
        return self.side_cable(x, 0 if x < self.tower_x[0] else 1)

    def svg(self, deck_fill, tower_fill, cable_fill, lit=None):
        parts = []
        # cables first, so the towers read as standing in front of them
        half = self.saddle_w / 2
        if self.anchor_x[0] >= self.tower_x[0]:
            cable = sample(self.cable_at, self.tower_x[0] - half, self.tower_x[1] + half, 90)
        else:
            cable = (sample(self.cable_at, self.anchor_x[0], self.tower_x[0] - half, 22)
                     + " " + sample(self.cable_at, self.tower_x[0] - half, self.tower_x[1] + half, 90)[1:]
                     + " " + sample(self.cable_at, self.tower_x[1] + half, self.anchor_x[1], 22)[1:])

        parts.append(f'<path d="{cable}" fill="none" stroke="{cable_fill}" '
                     f'stroke-width="{self.cable_w}" stroke-linecap="round" stroke-linejoin="round"/>')
        for x in (h for h in self.hangers if not self.on_tower(h)):
            top = self.cable_at(x)
            if self.deck_y - top > self.cable_w:
                parts.append(f'<line x1="{x}" y1="{top:.1f}" x2="{x}" y2="{self.deck_y}" '
                             f'stroke="{cable_fill}" stroke-width="{self.cable_w * 0.55:.1f}"/>')
        for tx in self.tower_x:
            legs = [tx] if self.leg_gap == 0 else [tx - self.leg_gap / 2, tx + self.leg_gap / 2]
            for lx in legs:
                parts.append(f'<rect x="{lx - self.leg_w / 2:.1f}" y="{self.tower_top}" '
                             f'width="{self.leg_w}" height="{self.deck_y + self.deck_h - self.tower_top:.1f}" '
                             f'fill="{tower_fill}"/>')
            if self.leg_gap:
                sw = self.leg_gap + self.leg_w
                parts.append(f'<rect x="{tx - sw / 2:.1f}" y="{self.cable_y - self.cable_w * 0.7:.1f}" '
                             f'width="{sw:.1f}" height="{self.cable_w * 1.4:.1f}" fill="{tower_fill}"/>')
            for by, bw in self.beams:
                parts.append(f'<rect x="{tx - bw / 2:.1f}" y="{by}" width="{bw}" '
                             f'height="{self.leg_w * 0.72:.1f}" fill="{tower_fill}"/>')
        parts.append(f'<rect x="{self.span[0]}" y="{self.deck_y}" width="{self.span[1] - self.span[0]}" '
                     f'height="{self.deck_h}" fill="{deck_fill}"/>')
        if lit:
            parts.append(f'<rect x="{self.span[0]}" y="{self.deck_y}" width="{self.span[1] - self.span[0]}" '
                         f'height="{self.deck_h * 0.28:.1f}" fill="{lit}"/>')
        return "\n  ".join(parts)


FULL = Bridge(span=(50, 974), deck_y=664, deck_h=28, tower_x=(250, 774), tower_top=372,
              cable_y=396, sag=268, anchor_x=(50, 974), anchor_y=664, leg_w=24, leg_gap=70,
              cable_w=14,
              hangers=[302 + 30 * i for i in range(14)] + [110, 150, 190, 806, 846, 886],
              beams=[(372, 94), (486, 94), (580, 94)])

# At 16 px one unit of this canvas is 1/64 of a device pixel, so the small cut is drawn
# with strokes near 100 units: anything finer disappears into the field.
SMALL = Bridge(span=(30, 994), deck_y=636, deck_h=92, tower_x=(268, 756), tower_top=316,
               cable_y=396, sag=240, anchor_x=(30, 994), anchor_y=636, leg_w=88, leg_gap=0,
               cable_w=62, hangers=[], beams=[])

# The toolbar glyph is cropped to the main span: the cable leaves the frame on the way
# down to its anchorage instead of landing on the deck, which at 16 px would read as a
# pair of filled triangles rather than as cable.
BAR = Bridge(span=(0, 128), deck_y=94, deck_h=11, tower_x=(30, 98), tower_top=26,
             cable_y=44, sag=34, anchor_x=(30, 98), anchor_y=94, leg_w=9, leg_gap=0,
             cable_w=7, hangers=[44, 56, 64, 72, 84], beams=[(58, 22)])

# At 16 px the side spans are dropped entirely: two towers, the dip between them, and the
# deck are the least that still says suspension bridge.
BAR16 = Bridge(span=(0, 128), deck_y=96, deck_h=14, tower_x=(28, 100), tower_top=22,
               cable_y=48, sag=32, anchor_x=(28, 100), anchor_y=96, leg_w=12, leg_gap=0,
               cable_w=11, hangers=[], beams=[])


def app_icon(simplified=False):
    body = squircle(512, 512, 412)
    bridge = (SMALL if simplified else FULL).svg(
        deck_fill="url(#deck)" if not simplified else ORANGE,
        tower_fill=ORANGE if not simplified else ORANGE,
        cable_fill=CABLE,
        lit=None if simplified else ORANGE_LIT)
    sky = "" if simplified else """
    <rect x="100" y="100" width="824" height="824" fill="url(#haze)"/>"""
    rim = "" if simplified else f"""
  <path d="{body}" fill="none" stroke="#FFFFFF" stroke-opacity="0.18" stroke-width="3"/>"""
    return f"""<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 1024 1024" width="1024" height="1024">
  <defs>
    <linearGradient id="field" x1="0" y1="0" x2="0" y2="1">
      <stop offset="0" stop-color="{FIELD_TOP}"/>
      <stop offset="1" stop-color="{FIELD_BOT}"/>
    </linearGradient>
    <linearGradient id="deck" x1="0" y1="0" x2="0" y2="1">
      <stop offset="0" stop-color="{ORANGE_LIT}"/>
      <stop offset="1" stop-color="{ORANGE}"/>
    </linearGradient>
    <radialGradient id="haze" cx="0.5" cy="0.72" r="0.52">
      <stop offset="0" stop-color="#8FCDF2" stop-opacity="0.26"/>
      <stop offset="1" stop-color="#8FCDF2" stop-opacity="0"/>
    </radialGradient>
    <clipPath id="body"><path d="{body}"/></clipPath>
  </defs>
  <path d="{body}" fill="{'#1C3established' if False else ('#1B3149' if simplified else 'url(#field)')}"/>
  <g clip-path="url(#body)">{sky}
  {bridge}
  </g>{rim}
</svg>
"""


def toolbar_icon(small=False):
    b = BAR16 if small else BAR
    return f"""<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 128 128" width="128" height="128">
  {b.svg(deck_fill=ORANGE, tower_fill=ORANGE, cable_fill=ORANGE)}
</svg>
"""


(OUT / "app-icon.svg").write_text(app_icon())
(OUT / "app-icon-small.svg").write_text(app_icon(simplified=True))
(OUT / "toolbar-icon.svg").write_text(toolbar_icon())
(OUT / "toolbar-icon-16.svg").write_text(toolbar_icon(small=True))
print("wrote", *(p.name for p in sorted(OUT.iterdir())))
