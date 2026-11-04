"""Builds one picture of tap-by-tap steps from simulator screenshots, for /mm-screen-guide.

    python3 -I annotate.py <spec.json> <out.png>
    python3 -I annotate.py --self-test

The spec (paths are relative to the spec's folder):

    {"title": "...", "notes": ["...", "..."], "scale": 3,
     "steps": [{"image": "01.png", "marks": [[202, 803, "1"]], "caption": ["..."]}]}

marks are the points mobilebuildmcp's tap and touch results print (x, y); scale turns them into the
screenshot's pixels (3 on an iPhone 17 Pro: 1206 px / 402 pt). Captions and notes wrap to the width.
"""

import json
import os
import sys
import tempfile

from PIL import Image, ImageDraw, ImageFont

FONT = "/System/Library/Fonts/ヒラギノ角ゴシック W6.ttc"
RED = (230, 30, 30)
W = 560  # width of one screen in the sheet
COLS = 2
GAP = 24


def font(size):
    return ImageFont.truetype(FONT, size)


NO_LINE_START = "」』）)、。，．！？!?・ー"


def wrap(draw, text, f, width):
    """Lines of text that each fit in width, broken between characters (Japanese has no spaces).
    No line starts with a closing bracket or punctuation: when one would, the character before it
    (and any closers already after that character) moves to the next line with it."""
    lines, line = [], ""
    for ch in text:
        if draw.textlength(line + ch, font=f) <= width or not line.strip():
            line += ch
            continue
        if ch in NO_LINE_START:
            k = len(line)
            while k > 0 and line[k - 1] in NO_LINE_START:
                k -= 1
            k = max(k - 1, 0)
            if line[:k].strip():
                lines.append(line[:k])
                line = "  " + line[k:] + ch
                continue
        lines.append(line)
        line = "  " + ch if ch != " " else "  "
    if line:
        lines.append(line)
    return lines


def mark(draw, px, py, label, unit):
    r = int(32 * unit)
    draw.ellipse([px - r, py - r, px + r, py + r], outline=RED, width=max(4, int(4.5 * unit)))
    br = int(15 * unit)
    bx, by = px + r - int(3 * unit), py - r + int(3 * unit)
    draw.ellipse([bx - br, by - br, bx + br, by + br], fill=RED)
    f = font(int((18 if len(label) == 1 else 14.5) * unit))
    tw = draw.textlength(label, font=f)
    draw.text((bx - tw / 2, by - f.size * 0.6), label, font=f, fill="white")


def build(spec, base, out):
    scale = float(spec.get("scale", 3))
    cap_f, note_f, title_f = font(26), font(22), font(34)
    probe = ImageDraw.Draw(Image.new("RGB", (10, 10)))
    tiles = []
    for step in spec["steps"]:
        img = Image.open(os.path.join(base, step["image"])).convert("RGB")
        d = ImageDraw.Draw(img)
        for x, y, label in step.get("marks", []):
            px, py = x * scale, y * scale
            if not (0 <= px < img.width and 0 <= py < img.height):
                raise ValueError(f"{step['image']}: mark {label} at ({x}, {y}) x{scale} = ({px:.0f}, {py:.0f}) is outside the "
                                 f"{img.width}x{img.height} screenshot; marks are points from the tap result, not pixels")
            mark(d, px, py, str(label), scale)
        small = img.resize((W, int(img.height * W / img.width)), Image.LANCZOS)
        lines = [l for c in step.get("caption", []) for l in wrap(probe, c, cap_f, W - 32)]
        tile = Image.new("RGB", (W, small.height + 30 + 36 * len(lines)), "white")
        tile.paste(small, (0, 0))
        td = ImageDraw.Draw(tile)
        for j, line in enumerate(lines):
            td.text((16, small.height + 14 + 36 * j), line, font=cap_f, fill=(20, 20, 20))
        tiles.append(tile)

    sheet_w = COLS * W + (COLS + 1) * GAP
    titles = wrap(probe, spec.get("title", ""), title_f, sheet_w - 2 * GAP)
    notes = [l for n in spec.get("notes", []) for l in wrap(probe, n, note_f, sheet_w - 2 * GAP)]
    notes_y = 24 + 46 * len(titles) + 8
    head = notes_y + 34 * len(notes) + 16
    rows = (len(tiles) + COLS - 1) // COLS
    row_h = max(t.height for t in tiles)
    sheet = Image.new("RGB", (sheet_w, head + rows * (row_h + GAP) + GAP), (242, 242, 247))
    sd = ImageDraw.Draw(sheet)
    for j, line in enumerate(titles):
        sd.text((GAP, 24 + 46 * j), line, font=title_f, fill=(20, 20, 20))
    for j, line in enumerate(notes):
        sd.text((GAP, notes_y + 34 * j), line, font=note_f, fill=(90, 90, 90))
    for k, t in enumerate(tiles):
        r, c = divmod(k, COLS)
        sheet.paste(t, (GAP + c * (W + GAP), head + r * (row_h + GAP)))
    sheet.save(out, optimize=True)
    return sheet.size


def self_test():
    with tempfile.TemporaryDirectory() as d:
        for n in ("a.png", "b.png", "c.png"):
            Image.new("RGB", (1206, 2622), (200, 200, 200)).save(os.path.join(d, n))
        long = "とても長い説明の行が一枚の幅を超えても、はみ出さずに次の行へ折り返されることを確かめる「電話」と打ち、出た「電話」を押す"
        spec = {"title": long, "notes": [long], "scale": 3,
                "steps": [{"image": "a.png", "marks": [[100, 100, "1"], [300, 800, "12"]], "caption": [long]},
                          {"image": "b.png", "marks": [], "caption": ["短い"]},
                          {"image": "c.png", "marks": [[200, 400, "3"]], "caption": []}]}
        out = os.path.join(d, "out.png")
        w, h = build(spec, d, out)
        probe = ImageDraw.Draw(Image.new("RGB", (10, 10)))
        lines = wrap(probe, long, font(26), W - 32)
        assert len(lines) >= 2, "a long caption wraps"
        assert len(wrap(probe, long, font(34), COLS * W + (COLS - 1) * GAP)) >= 2, "a long title wraps"
        # A run of closers at every position across the break: still inside the width, never at a line start.
        for n in range(10, 30):
            for closers in ("」", "」。", "」）。"):
                ls = wrap(probe, "あ" * n + closers + "い" * 6, font(26), W - 32)
                assert all(probe.textlength(l, font=font(26)) <= W - 32 for l in ls), f"fits: {n} {closers}"
                assert not any(l.lstrip()[:1] in NO_LINE_START for l in ls[1:]), f"no closer starts a line: {n} {closers}"
        try:
            build({"steps": [{"image": "a.png", "marks": [[600, 1200, "1"]]}], "scale": 3}, d, out)
            raise AssertionError("a mark given in pixels instead of points is refused")
        except ValueError:
            pass
        assert w == COLS * W + (COLS + 1) * GAP and h > 2 * 1200, f"two rows of two columns: {w}x{h}"
        colors = Image.open(out).convert("RGB").getcolors(maxcolors=1 << 24) or []
        reds = sum(n for n, (r, g, b) in colors if r > 200 and g < 80 and b < 80)
        assert reds > 500, f"the marks are drawn in red ({reds} red pixels)"
        print(f"self-test ok: {w}x{h}, caption wrapped into {len(lines)} lines")


if __name__ == "__main__":
    if sys.argv[1:] == ["--self-test"]:
        self_test()
    elif len(sys.argv) == 3:
        spec_path = sys.argv[1]
        with open(spec_path, encoding="utf-8") as fh:
            spec = json.load(fh)
        print(build(spec, os.path.dirname(os.path.abspath(spec_path)), sys.argv[2]))
    else:
        sys.exit(__doc__)
