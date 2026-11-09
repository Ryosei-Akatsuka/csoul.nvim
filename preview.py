#!/usr/bin/env python3
"""
csoul — a colorscheme picker, rendered as a terminal UI study.

    python3 preview.py

The script is dependency-free.  It discovers the colorschemes that are
actually available to the local Neovim (runtime, lazy.nvim, pack/*, and user
colors directories), then paints a static mockup of the finished picker with
ANSI truecolor sequences.

Designed for a truecolor terminal of at least 112 x 33 cells.
"""

from __future__ import annotations

import math
import os
import re
import shutil
import subprocess
import sys
from dataclasses import dataclass
from functools import lru_cache
from pathlib import Path
from typing import Dict, List, Optional, Sequence, Set, Tuple

RGB = Tuple[int, int, int]


# ---------------------------------------------------------------------------
# colour helpers
# ---------------------------------------------------------------------------

@lru_cache(maxsize=None)
def rgb(value: str) -> RGB:
    value = value.lstrip("#")
    return (int(value[0:2], 16), int(value[2:4], 16), int(value[4:6], 16))


def hx(value: str) -> str:
    r, g, b = rgb(value)
    return f"#{r:02x}{g:02x}{b:02x}"


def mix(a: str, b: str, t: float) -> str:
    """Blend two colours.  t=0 -> a, t=1 -> b."""
    t = max(0.0, min(1.0, t))
    ar, ag, ab = rgb(a)
    br, bg, bb = rgb(b)
    return hx(
        f"#{round(ar + (br - ar) * t):02x}"
        f"{round(ag + (bg - ag) * t):02x}"
        f"{round(ab + (bb - ab) * t):02x}"
    )


def luminance(value: str) -> float:
    r, g, b = (c / 255.0 for c in rgb(value))

    def linear(c: float) -> float:
        return c / 12.92 if c <= 0.04045 else ((c + 0.055) / 1.055) ** 2.4

    return 0.2126 * linear(r) + 0.7152 * linear(g) + 0.0722 * linear(b)


def contrast(a: str, b: str) -> float:
    la, lb = luminance(a), luminance(b)
    light, dark = max(la, lb), min(la, lb)
    return (light + 0.05) / (dark + 0.05)


def ink_on(background: str) -> str:
    """Pick a warm near-black or paper-white for text on a colour."""
    dark, light = "#16161d", "#f4f1e8"
    return dark if contrast(dark, background) >= contrast(light, background) else light


def dim(foreground: str, background: str, amount: float = 0.35) -> str:
    return mix(foreground, background, amount)


# ---------------------------------------------------------------------------
# tiny ANSI canvas
# ---------------------------------------------------------------------------

@dataclass
class Cell:
    ch: str = " "
    fg: str = "#ffffff"
    bg: str = "#000000"
    bold: bool = False
    italic: bool = False
    faint: bool = False


@lru_cache(maxsize=None)
def sgr_fg(value: str) -> str:
    r, g, b = rgb(value)
    return f"\x1b[38;2;{r};{g};{b}m"


@lru_cache(maxsize=None)
def sgr_bg(value: str) -> str:
    r, g, b = rgb(value)
    return f"\x1b[48;2;{r};{g};{b}m"


class Canvas:
    def __init__(self, width: int, height: int) -> None:
        self.width = width
        self.height = height
        self.cells: List[List[Cell]] = [
            [Cell() for _ in range(width)] for _ in range(height)
        ]

    def cell(self, x: int, y: int) -> Cell:
        return self.cells[y][x]

    def put(
        self,
        x: int,
        y: int,
        text: str,
        fg: Optional[str] = None,
        bg: Optional[str] = None,
        bold: bool = False,
        italic: bool = False,
        faint: bool = False,
    ) -> int:
        """Write text.  bg=None keeps the existing background."""
        if y < 0 or y >= self.height:
            return 0
        for i, ch in enumerate(text):
            xx = x + i
            if 0 <= xx < self.width:
                c = self.cells[y][xx]
                c.ch = ch
                if fg is not None:
                    c.fg = fg
                if bg is not None:
                    c.bg = bg
                c.bold = bold
                c.italic = italic
                c.faint = faint
        return len(text)

    def fill(
        self,
        x: int,
        y: int,
        width: int,
        height: int,
        bg: str,
        ch: str = " ",
        fg: Optional[str] = None,
    ) -> None:
        for yy in range(y, y + height):
            if yy < 0 or yy >= self.height:
                continue
            for xx in range(x, x + width):
                if 0 <= xx < self.width:
                    c = self.cells[yy][xx]
                    c.ch = ch
                    c.bg = bg
                    if fg is not None:
                        c.fg = fg

    def hline(
        self,
        x: int,
        y: int,
        width: int,
        fg: str,
        ch: str = "─",
        bg: Optional[str] = None,
    ) -> None:
        self.put(x, y, ch * width, fg=fg, bg=bg)

    def vline(
        self,
        x: int,
        y: int,
        height: int,
        fg: str,
        ch: str = "│",
        bg: Optional[str] = None,
    ) -> None:
        for yy in range(y, y + height):
            self.put(x, yy, ch, fg=fg, bg=bg)

    def render(self) -> str:
        rows: List[str] = []
        for row in self.cells:
            pieces: List[str] = []
            previous: Optional[Tuple[str, str, bool, bool, bool]] = None
            for cell in row:
                style = (cell.fg, cell.bg, cell.bold, cell.italic, cell.faint)
                if style != previous:
                    pieces.append("\x1b[0m")
                    if cell.bold:
                        pieces.append("\x1b[1m")
                    if cell.italic:
                        pieces.append("\x1b[3m")
                    if cell.faint:
                        pieces.append("\x1b[2m")
                    pieces.append(sgr_fg(cell.fg))
                    pieces.append(sgr_bg(cell.bg))
                    previous = style
                pieces.append(cell.ch)
            pieces.append("\x1b[0m")
            rows.append("".join(pieces))
        return "\n".join(rows) + "\n"


# ---------------------------------------------------------------------------
# the palette library
# ---------------------------------------------------------------------------

@dataclass(frozen=True)
class Theme:
    slug: str
    bg: str
    fg: str
    surface: str
    muted: str
    border: str
    accent: str
    violet: str
    green: str
    amber: str
    red: str
    cyan: str
    selection: str
    search: str
    light: bool = False

    @property
    def display(self) -> str:
        return self.slug.replace("-", " ").title()

    @property
    def words(self) -> List[str]:
        return self.slug.split("-")

    @property
    def swatches(self) -> List[str]:
        return [self.bg, self.fg, self.accent, self.violet, self.green, self.amber]

    @property
    def mini(self) -> List[str]:
        return [self.accent, self.violet, self.green, self.amber]


THEMES: Dict[str, Theme] = {
    "kanagawa-wave": Theme(
        slug="kanagawa-wave",
        bg="#1f1f28", fg="#dcd7ba", surface="#2a2a37", muted="#727169",
        border="#54546d", accent="#7e9cd8", violet="#957fb8", green="#98bb6c",
        amber="#ffa066", red="#e82424", cyan="#7fb4ca",
        selection="#223249", search="#2d4f67",
    ),
    "kanagawa-dragon": Theme(
        slug="kanagawa-dragon",
        bg="#181616", fg="#c5c9c5", surface="#282727", muted="#737c73",
        border="#54546d", accent="#8ba4b0", violet="#8992a7", green="#8a9a7b",
        amber="#ff9e3b", red="#e82424", cyan="#949fb5",
        selection="#223249", search="#2d4f67",
    ),
    "kanagawa-lotus": Theme(
        slug="kanagawa-lotus",
        bg="#f2ecbc", fg="#545464", surface="#e7dba0", muted="#8a8980",
        border="#716e61", accent="#4d699b", violet="#624c83", green="#6f894e",
        amber="#cc6d00", red="#e82424", cyan="#6693bf",
        selection="#c9cbd1", search="#b5cbd2", light=True,
    ),
    "catppuccin": Theme(
        slug="catppuccin",
        bg="#1e1e2e", fg="#cdd6f4", surface="#313244", muted="#9399b2",
        border="#45475a", accent="#89b4fa", violet="#cba6f7", green="#a6e3a1",
        amber="#fab387", red="#f38ba8", cyan="#89dceb",
        selection="#45475a", search="#3e5767",
    ),
    "default": Theme(
        slug="default",
        bg="#14161b", fg="#e0e2ea", surface="#2c2e33", muted="#9b9ea4",
        border="#4f5258", accent="#8cf8f7", violet="#a6dbff", green="#b3f6c0",
        amber="#fce094", red="#ffc0b9", cyan="#8cf8f7",
        selection="#4f5258", search="#6b5300",
    ),
    "habamax": Theme(
        slug="habamax",
        bg="#1c1c1c", fg="#c7c7c7", surface="#303030", muted="#767676",
        border="#585858", accent="#87afaf", violet="#af87af", green="#5faf5f",
        amber="#d75f87", red="#ff0000", cyan="#5f8787",
        selection="#1a3456", search="#374a44",
    ),
    "retrobox": Theme(
        slug="retrobox",
        bg="#1c1c1c", fg="#ebdbb2", surface="#303030", muted="#928374",
        border="#504945", accent="#b8bb26", violet="#fb5944", green="#b8bb26",
        amber="#fe8019", red="#fb5944", cyan="#8ec07c",
        selection="#2a405a", search="#3a4a3a",
    ),
    "unokai": Theme(
        slug="unokai",
        bg="#282923", fg="#f8f8f2", surface="#3a392f", muted="#74705d",
        border="#585858", accent="#a6e22e", violet="#f92672", green="#e6db74",
        amber="#fd971f", red="#f92672", cyan="#66d9ef",
        selection="#3a392f", search="#282923",
    ),
    "sorbet": Theme(
        slug="sorbet",
        bg="#161821", fg="#dadada", surface="#363841", muted="#af87d7",
        border="#5f5f87", accent="#87d75f", violet="#87afd7", green="#d7af5f",
        amber="#d75f5f", red="#ff5f5f", cyan="#5fafaf",
        selection="#363841", search="#000000",
    ),
    "lunaperche": Theme(
        slug="lunaperche",
        bg="#000000", fg="#c6c6c6", surface="#303030", muted="#5fafff",
        border="#767676", accent="#5fafff", violet="#ff87ff", green="#ffd787",
        amber="#5fd75f", red="#ff5f5f", cyan="#5fafaf",
        selection="#104070", search="#3a4a3a",
    ),
    "wildcharm": Theme(
        slug="wildcharm",
        bg="#000000", fg="#d0d0d0", surface="#303030", muted="#767676",
        border="#767676", accent="#ff87ff", violet="#00afff", green="#00d75f",
        amber="#ff5f87", red="#d7005f", cyan="#875fff",
        selection="#204060", search="#3a4a3a",
    ),
    "quiet": Theme(
        slug="quiet",
        bg="#000000", fg="#dadada", surface="#303030", muted="#707070",
        border="#707070", accent="#dadada", violet="#ffaf00", green="#00afff",
        amber="#a8a8a8", red="#ff005f", cyan="#dadada",
        selection="#303030", search="#000000",
    ),
    "zaibatsu": Theme(
        slug="zaibatsu",
        bg="#0e0024", fg="#ffffff", surface="#362b49", muted="#afafff",
        border="#afafff", accent="#87ffff", violet="#ffafff", green="#ffff5f",
        amber="#ff5faf", red="#d70000", cyan="#87ff00",
        selection="#5fd7ff", search="#0e0024",
    ),
    "desert": Theme(
        slug="desert",
        bg="#333333", fg="#ffffff", surface="#666666", muted="#6dceeb",
        border="#7f7f8c", accent="#89fb98", violet="#f0e68c", green="#ffa0a0",
        amber="#ffde9b", red="#ff0000", cyan="#6dceeb",
        selection="#6b8e24", search="#7f7f8c",
    ),
    "morning": Theme(
        slug="morning",
        bg="#e4e4e4", fg="#000000", surface="#d3d3d3", muted="#0000ff",
        border="#bcbcbc", accent="#008787", violet="#a52a2a", green="#2e8b57",
        amber="#6a5acd", red="#ff0000", cyan="#008787",
        selection="#d0d0d0", search="#6a0dad", light=True,
    ),
}

DISPLAY_ORDER: List[str] = [
    "kanagawa-wave", "kanagawa-dragon", "kanagawa-lotus", "catppuccin",
    "default", "habamax", "retrobox", "unokai", "sorbet", "lunaperche",
    "wildcharm", "quiet", "zaibatsu", "desert", "morning",
]

KNOWN_LIGHT: Set[str] = {
    "morning", "peachpuff", "zellner", "delek", "shine", "kanagawa-lotus",
}

CORE_LIGHT: Set[str] = {"morning", "peachpuff", "zellner", "delek", "shine"}


# ---------------------------------------------------------------------------
# discovery — find what the local Neovim can actually load
# ---------------------------------------------------------------------------

@lru_cache(maxsize=None)
def nvim_runtimepath() -> List[str]:
    try:
        proc = subprocess.run(
            [
                "nvim", "--headless", "-u", "NONE",
                "-c", "lua print(vim.o.runtimepath)",
                "-c", "qa!",
            ],
            capture_output=True,
            text=True,
            timeout=3,
        )
        if proc.returncode == 0:
            raw = proc.stdout.strip() or proc.stderr.strip()
            # headless print() lands on stderr; take the last plausible line
            for line in reversed(raw.splitlines()):
                if "," in line and "/nvim" in line:
                    return [part for part in line.split(",") if part]
    except (OSError, subprocess.SubprocessError):
        pass
    return []


@lru_cache(maxsize=None)
def nvim_version() -> str:
    try:
        proc = subprocess.run(
            ["nvim", "--version"], capture_output=True, text=True, timeout=2
        )
        if proc.returncode == 0 and proc.stdout:
            match = re.search(r"NVIM v([0-9.]+)", proc.stdout)
            if match:
                return match.group(1)
    except (OSError, subprocess.SubprocessError):
        pass
    return ""


def colors_directories() -> List[Path]:
    directories: List[Path] = []
    seen: Set[str] = set()

    def add(path: Path) -> None:
        key = str(path)
        if key not in seen:
            seen.add(key)
            directories.append(path)

    for root in nvim_runtimepath():
        add(Path(root) / "colors")

    home = Path.home()
    data_home = Path(os.environ.get("XDG_DATA_HOME", home / ".local" / "share"))
    config_home = Path(os.environ.get("XDG_CONFIG_HOME", home / ".config"))
    nvim_data = data_home / "nvim"

    add(config_home / "nvim" / "colors")
    add(nvim_data / "site" / "colors")
    add(home / ".vim" / "colors")

    for lazy_root in (nvim_data / "lazy", data_home / "nvim" / "lazy"):
        if lazy_root.is_dir():
            for plugin in sorted(lazy_root.iterdir()):
                add(plugin / "colors")

    for base in (nvim_data / "site" / "pack", home / ".vim" / "pack"):
        if base.is_dir():
            for pack in sorted(base.iterdir()):
                for kind in ("start", "opt"):
                    kind_dir = pack / kind
                    if kind_dir.is_dir():
                        for plugin in sorted(kind_dir.iterdir()):
                            add(plugin / "colors")

    for plug_root in (nvim_data / "plugged", data_home / "nvim" / "plugged"):
        if plug_root.is_dir():
            for plugin in sorted(plug_root.iterdir()):
                add(plugin / "colors")

    return directories


def source_label(path: Path) -> str:
    text = str(path)
    if "/nvim/runtime/colors/" in text:
        return "nvim runtime"
    match = re.search(r"/lazy/([^/]+)/colors/", text)
    if match:
        return match.group(1)
    match = re.search(r"/pack/[^/]+/(?:start|opt)/([^/]+)/colors/", text)
    if match:
        return match.group(1)
    if "/site/colors/" in text:
        return "local colors"
    return "colors directory"


def looks_light(path: Path) -> bool:
    try:
        source = path.read_text(errors="ignore")[:131072]
    except OSError:
        return False
    return bool(
        re.search(
            r"""(?:set\s+background|background\s*=|background\s*==)\s*[=]?\s*["']?light""",
            source,
            re.IGNORECASE,
        )
    )


def discover_schemes() -> Dict[str, Path]:
    found: Dict[str, Path] = {}
    for directory in colors_directories():
        if not directory.is_dir():
            continue
        try:
            entries = sorted(directory.iterdir())
        except OSError:
            continue
        for entry in entries:
            if entry.suffix not in (".vim", ".lua"):
                continue
            name = entry.stem
            if name.lower() in ("readme", "readme.txt"):
                continue
            found.setdefault(name, entry)
    return found


def scheme_is_light(name: str, path: Path) -> bool:
    theme = THEMES.get(name)
    if theme is not None:
        return theme.light
    if source_label(path) == "nvim runtime":
        return name in CORE_LIGHT
    if name in KNOWN_LIGHT:
        return True
    return looks_light(path)


# ---------------------------------------------------------------------------
# composition
# ---------------------------------------------------------------------------

WIDTH, HEIGHT = 112, 33
MX, MY, MW, MH = 4, 2, 104, 28

LEFT_X, LEFT_W = 7, 38
DIV_X = 46
RIGHT_X, RIGHT_W = 49, 56
CONTENT_Y, CONTENT_H = 10, 15
SEARCH_Y = 6

MODAL_TOP = "#1a1a25"
MODAL_BOTTOM = "#14141c"


def modal_row_bg(y: int) -> str:
    t = (y - (MY + 1)) / max(1, MH - 3)
    return mix(MODAL_TOP, MODAL_BOTTOM, t)


def tracked(text: str) -> str:
    return " ".join(text.upper())


def fit(text: str, width: int) -> str:
    return text if len(text) <= width else text[: max(0, width - 2)] + ".."


def draw_backdrop(cv: Canvas, theme: Theme) -> None:
    """A quiet, blurred aurora behind the floating panel."""
    for y in range(HEIGHT):
        base = mix("#08080d", "#101019", y / (HEIGHT - 1))
        for x in range(WIDTH):
            # two soft light pools, offset from the panel
            d1 = math.hypot((x - WIDTH * 0.30) / (WIDTH * 0.50),
                            (y - HEIGHT * 0.12) / (HEIGHT * 0.55))
            d2 = math.hypot((x - WIDTH * 0.78) / (WIDTH * 0.48),
                            (y - HEIGHT * 0.92) / (HEIGHT * 0.55))
            glow = math.exp(-d1 * d1) * 0.085 + math.exp(-d2 * d2) * 0.055
            colour = mix(base, theme.accent, glow * 0.72)
            colour = mix(colour, theme.violet, glow * 0.28)
            cv.cell(x, y).bg = colour
            cv.cell(x, y).fg = colour
            cv.cell(x, y).ch = " "

    # an almost invisible dot grid gives the field a sense of scale
    for y in range(1, HEIGHT - 1, 2):
        for x in range(2, WIDTH - 1, 4):
            bg = cv.cell(x, y).bg
            cv.put(x, y, "·", fg=mix(bg, "#ffffff", 0.055))


def draw_shadow(cv: Canvas) -> None:
    cv.fill(MX + 2, MY + 2, MW, MH, "#050509")
    cv.fill(MX + 1, MY + 1, MW, MH, "#090910")


def border_top(i: int, theme: Theme) -> str:
    start = mix("#3b3b52", theme.accent, 0.30)
    rest = "#36364a"
    return mix(start, rest, min(1.0, i / 46.0))


def border_side(t: float, theme: Theme) -> str:
    return mix(mix("#42425c", theme.accent, 0.10), "#2c2c3c", t)


def draw_modal(cv: Canvas, theme: Theme) -> None:
    # interior: a barely perceptible vertical gradient
    for i in range(MH - 2):
        cv.fill(MX + 1, MY + 1 + i, MW - 2, 1, modal_row_bg(MY + 1 + i))

    # outer border: light falls from the top-left, then fades
    top_left = mix("#3b3b52", theme.accent, 0.26)
    top_right = "#3b3b52"
    cv.put(MX, MY, "╭", fg=top_left)
    for i in range(1, MW - 1):
        cv.put(MX + i, MY, "─", fg=border_top(i, theme))
    cv.put(MX + MW - 1, MY, "╮", fg=top_right)

    for j in range(1, MH - 1):
        t = j / max(1, MH - 2)
        cv.put(MX, MY + j, "│", fg=border_side(t, theme))
        cv.put(MX + MW - 1, MY + j, "│", fg=mix("#36364a", "#282838", t))

    cv.put(MX, MY + MH - 1, "╰", fg="#303044")
    cv.put(
        MX + 1, MY + MH - 1,
        "─" * (MW - 2),
        fg=mix("#333348", "#29293a", 0.5),
    )
    cv.put(MX + MW - 1, MY + MH - 1, "╯", fg="#29293a")


def pill(
    cv: Canvas,
    x: int,
    y: int,
    text: str,
    fg: str,
    bg: str,
    bold: bool = False,
) -> int:
    cv.put(x, y, f" {text} ", fg=fg, bg=bg, bold=bold)
    return len(text) + 2


def keycap(
    cv: Canvas,
    x: int,
    y: int,
    key: str,
    label: str,
    theme: Theme,
) -> int:
    key_bg = mix(theme.surface, theme.fg, 0.07)
    cv.put(x, y, f" {key} ", fg=theme.fg, bg=key_bg)
    label_x = x + len(key) + 2
    cv.put(label_x, y, label, fg=mix(theme.fg, theme.bg, 0.54))
    return label_x + len(label) - x


def draw_header(
    cv: Canvas, theme: Theme, detected_count: int, version: str
) -> None:
    y = MY + 2
    cv.put(LEFT_X, y, "◆", fg=theme.amber, bold=True)
    cv.put(LEFT_X + 2, y, "csoul", fg=theme.fg, bold=True)
    cv.put(LEFT_X + 9, y, "│", fg=mix(theme.border, theme.bg, 0.25))
    cv.put(
        LEFT_X + 12, y,
        "colorscheme studio",
        fg=mix(theme.fg, theme.bg, 0.58),
    )

    if detected_count:
        dot, rest = "●", f" {detected_count} detected  ·  nvim {version}".rstrip()
    else:
        dot, rest = "○", " curated preview  ·  nvim colors"
    start = 104 - (len(dot) + len(rest)) + 1
    cv.put(start, y, dot, fg=theme.green if detected_count else theme.muted)
    cv.put(start + 1, y, rest, fg=mix(theme.fg, theme.bg, 0.52))


def draw_search(
    cv: Canvas,
    theme: Theme,
    all_count: int,
    dark_count: int,
    light_count: int,
) -> None:
    labels = [
        ("ALL", all_count, True),
        ("DARK", dark_count, False),
        ("LIGHT", light_count, False),
    ]
    widths = [len(label) + len(str(count)) + 3 for label, count, _ in labels]
    total = sum(widths) + 2
    chip_x = 104 - total + 1
    field_x = LEFT_X
    field_w = chip_x - 2 - field_x + 1

    field_bg = mix(theme.bg, theme.surface, 0.38)
    cv.fill(field_x, SEARCH_Y, field_w, 1, field_bg)

    key_bg = mix(theme.surface, theme.fg, 0.08)
    cv.put(field_x + 1, SEARCH_Y, " / ", fg=theme.accent, bg=key_bg)
    cv.put(field_x + 5, SEARCH_Y, " ", bg=theme.accent)
    cv.put(
        field_x + 6, SEARCH_Y,
        "Search schemes, palettes, moods...",
        fg=mix(theme.fg, field_bg, 0.52),
    )

    esc_x = field_x + field_w - 6
    cv.put(esc_x, SEARCH_Y, " esc ", fg=mix(theme.fg, theme.bg, 0.45), bg=key_bg)

    x = chip_x
    for index, ((label, count, active), width) in enumerate(zip(labels, widths)):
        text = f"{label} {count}"
        if active:
            bg = theme.accent
            fg = ink_on(bg)
        else:
            bg = mix(theme.bg, theme.surface, 0.28)
            fg = mix(theme.fg, theme.bg, 0.48)
        cv.put(x, SEARCH_Y, f" {text} ", fg=fg, bg=bg, bold=active)
        x += width + 1


def draw_headers(cv: Canvas, theme: Theme, shown: int, all_count: int) -> None:
    y = MY + 6
    section = mix(theme.fg, theme.bg, 0.46)
    dim = mix(theme.fg, theme.bg, 0.68)
    cv.put(LEFT_X, y, tracked("schemes"), fg=section)
    cv.put(LEFT_X + len(tracked("schemes")) + 2, y, f"{shown} / {all_count}", fg=dim)
    cv.put(RIGHT_X, y, tracked("preview"), fg=section)
    cv.put(104 - len("TRUECOLOR") + 1, y, "TRUECOLOR", fg=dim)

    divider = mix(theme.border, theme.bg, 0.46)
    cv.hline(LEFT_X, y + 1, LEFT_W, divider)
    cv.hline(RIGHT_X, y + 1, RIGHT_W, divider)
    cv.vline(DIV_X, CONTENT_Y, CONTENT_H, mix(theme.border, theme.bg, 0.60))


def draw_list(
    cv: Canvas,
    theme: Theme,
    display: Sequence[str],
    selected: str,
) -> None:
    for i, name in enumerate(display):
        item = THEMES[name]
        y = CONTENT_Y + i
        is_selected = name == selected
        base = modal_row_bg(y)

        if is_selected:
            for rel in range(LEFT_W):
                amount = 0.04 + 0.10 * (1.0 - rel / max(1, LEFT_W - 1))
                cv.cell(LEFT_X + rel, y).bg = mix(base, theme.accent, amount)
            cv.put(LEFT_X, y, " ", bg=theme.accent)

        index_fg = theme.accent if is_selected else mix(theme.fg, theme.bg, 0.65)
        cv.put(LEFT_X + 2, y, f"{i + 1:02d}", fg=index_fg, bold=is_selected)

        name_fg = (
            mix(theme.fg, "#ffffff", 0.20)
            if is_selected
            else mix(theme.fg, theme.bg, 0.05)
        )
        cv.put(LEFT_X + 5, y, fit(name, 17), fg=name_fg, bold=is_selected)

        for j, colour in enumerate(item.mini):
            cv.cell(LEFT_X + 23 + j * 2, y).bg = colour

        if is_selected:
            tag, tag_fg = "current", theme.green
        elif item.light:
            tag, tag_fg = "light", theme.amber
        else:
            tag, tag_fg = "dark", mix(theme.fg, theme.bg, 0.52)
        cv.put(LEFT_X + LEFT_W - len(tag), y, tag, fg=tag_fg, bold=is_selected)


def draw_preview(
    cv: Canvas,
    theme: Theme,
    source: str,
    origin: str,
) -> None:
    # large, letterspaced name
    x = RIGHT_X + 1
    words = theme.words
    for i, word in enumerate(words):
        colour = theme.fg if i < len(words) - 1 else theme.accent
        if len(words) > 2 and 0 < i < len(words) - 1:
            colour = theme.violet
        rendered = tracked(word)
        cv.put(x, CONTENT_Y, fit(rendered, 104 - x + 1), fg=colour, bold=True)
        x += len(rendered) + 3

    # source + tiny badges
    meta_y = CONTENT_Y + 1
    source_text = fit(source, 24)
    source_fg = mix(theme.fg, theme.bg, 0.55)
    cv.put(RIGHT_X + 1, meta_y, source_text, fg=source_fg)

    badge_x = RIGHT_X + 1 + len(source_text) + 2
    kind = "LIGHT" if theme.light else "DARK"
    kind_bg = mix(theme.bg, theme.surface, 0.46)
    badge_x += pill(cv, badge_x, meta_y, kind, theme.fg, kind_bg) + 1
    origin_bg = mix(theme.bg, theme.accent, 0.18)
    origin_fg = mix(theme.accent, "#ffffff", 0.20)
    badge_x += pill(cv, badge_x, meta_y, origin, origin_fg, origin_bg) + 1

    ratio = contrast(theme.fg, theme.bg)
    grade = "AAA" if ratio >= 7.0 else "AA" if ratio >= 4.5 else "A"
    badge_x += pill(
        cv,
        badge_x,
        meta_y,
        f"{grade} {ratio:.1f}",
        mix(theme.green, "#ffffff", 0.18),
        mix(theme.bg, theme.green, 0.16),
    )

    # palette: six living swatches, with the hex and role printed in the ink
    palette_y = CONTENT_Y + 3
    roles = ["base", "ink", "blue", "iris", "moss", "amber"]
    for i, colour in enumerate(theme.swatches):
        x = RIGHT_X + 1 + i * 9
        cv.fill(x, palette_y, 8, 2, colour)
        ink = ink_on(colour)
        cv.put(x, palette_y, f" {hx(colour)}", fg=ink)
        cv.put(x, palette_y + 1, roles[i].center(8), fg=dim(ink, colour, 0.30))

    # syntax sample
    label_y = CONTENT_Y + 6
    section = mix(theme.fg, theme.bg, 0.46)
    cv.put(RIGHT_X + 1, label_y, tracked("syntax"), fg=section)
    cv.put(104 - len("init.lua") + 1, label_y, "init.lua", fg=mix(theme.fg, theme.bg, 0.70))

    panel_bg = mix(theme.bg, "#000000", 0.30)
    panel_y = CONTENT_Y + 7
    cv.fill(RIGHT_X, panel_y, RIGHT_W, 5, panel_bg)
    active_bg = mix(panel_bg, theme.accent, 0.065)
    cv.fill(RIGHT_X, panel_y + 3, RIGHT_W, 1, active_bg)
    cv.fill(RIGHT_X, panel_y, 1, 5, mix(theme.accent, panel_bg, 0.55))

    punct = mix(theme.fg, panel_bg, 0.25)
    line_height = 5
    for line_no in range(line_height):
        cv.put(
            RIGHT_X + 2,
            panel_y + line_no,
            f"{line_no + 1:>2}",
            fg=theme.amber if line_no == 3 else mix(theme.fg, panel_bg, 0.62),
            bold=line_no == 3,
        )

    code_x = RIGHT_X + 5
    code_rows = [
        [("-- ~/.config/nvim/init.lua", theme.muted, True)],
        [
            ("local", theme.violet, True),
            (" M", theme.fg, False),
            (" = {}", punct, False),
        ],
        [
            ("function", theme.violet, True),
            (" M.setup", theme.accent, False),
            ("(", punct, False),
            ("opts", theme.amber, False),
            (")", punct, False),
        ],
        [
            ("  vim", theme.cyan, False),
            (".cmd.colorscheme", theme.accent, False),
            ("(", punct, False),
            (f'"{theme.slug}"', theme.green, False),
            (")", punct, False),
        ],
        [("end", theme.violet, True)],
    ]
    for line_no, segments in enumerate(code_rows):
        cx = code_x
        for text, fg, italic in segments:
            cv.put(cx, panel_y + line_no, text, fg=fg, italic=italic)
            cx += len(text)

    # component chips
    chips_y = CONTENT_Y + 13
    cv.put(RIGHT_X + 1, chips_y, "UI SAMPLE", fg=section)
    chip_x = RIGHT_X + 12
    chips = [
        ("Normal", theme.bg, theme.fg),
        ("Visual", theme.selection, theme.fg),
        ("Search", theme.search, theme.fg),
        ("Error", mix(theme.surface, theme.bg, 0.16), theme.red),
        ("Hint", mix(theme.surface, theme.bg, 0.16), theme.cyan),
    ]
    for i, (label, bg, fg) in enumerate(chips):
        chip_x += pill(cv, chip_x, chips_y, label, fg, bg)
        if i != len(chips) - 1:
            chip_x += 1


def draw_footer(cv: Canvas, theme: Theme) -> None:
    divider_y = MY + MH - 3
    for x in range(LEFT_X, 105):
        t = (x - LEFT_X) / max(1, 104 - LEFT_X)
        left = mix(mix(theme.accent, theme.border, 0.55),
                   mix(theme.border, theme.bg, 0.55), t)
        cv.put(x, divider_y, "─", fg=left)

    y = divider_y + 1
    x = LEFT_X
    for key, label in (("j/k", "move"), ("/", "search"),
                       ("enter", "apply"), ("esc", "close")):
        x += keycap(cv, x, y, key, label, theme) + 2

    tagline = "a quieter way to choose color"
    cv.put(104 - len(tagline) + 1, y, tagline,
           fg=mix(theme.fg, theme.bg, 0.60))


# ---------------------------------------------------------------------------
# discovery -> composition
# ---------------------------------------------------------------------------

def choose_schemes(detected: Dict[str, Path]) -> Tuple[str, List[str]]:
    available = [name for name in DISPLAY_ORDER if name in detected] or list(DISPLAY_ORDER)
    selected = next(
        (name for name in ("kanagawa-wave", "catppuccin", "default") if name in available),
        available[0],
    )
    display = [selected] + [name for name in DISPLAY_ORDER if name != selected]
    display = [name for name in display if name in THEMES][:15]
    return selected, display


def scheme_counts(detected: Dict[str, Path], display: Sequence[str]) -> Tuple[int, int, int]:
    if detected:
        all_count = len(detected)
        light_count = sum(
            1 for name, path in detected.items() if scheme_is_light(name, path)
        )
    else:
        all_count = len(display)
        light_count = sum(1 for name in display if THEMES[name].light)
    return all_count, all_count - light_count, light_count


def origin_of(path: Optional[Path]) -> str:
    if path is None:
        return "CATALOG"
    label = source_label(path)
    if label == "nvim runtime":
        return "CORE"
    if label == "local colors":
        return "USER"
    return "PLUGIN"


def build() -> str:
    detected = discover_schemes()
    selected, display = choose_schemes(detected)
    all_count, dark_count, light_count = scheme_counts(detected, display)
    theme = THEMES[selected]
    path = detected.get(selected)
    source = source_label(path) if path is not None else "curated palette"
    origin = origin_of(path)

    cv = Canvas(WIDTH, HEIGHT)
    draw_backdrop(cv, theme)
    draw_shadow(cv)
    draw_modal(cv, theme)
    draw_header(cv, theme, len(detected), nvim_version() or "neovim")
    draw_search(cv, theme, all_count, dark_count, light_count)
    draw_headers(cv, theme, len(display), all_count)
    draw_list(cv, theme, display, selected)
    draw_preview(cv, theme, source, origin)
    draw_footer(cv, theme)
    return cv.render()


def main() -> None:
    size = shutil.get_terminal_size((WIDTH, HEIGHT))
    if sys.stdout.isatty() and (size.columns < WIDTH or size.lines < HEIGHT):
        sys.stderr.write(
            f"csoul: this study is {WIDTH}x{HEIGHT} cells; "
            f"your terminal is {size.columns}x{size.lines}. "
            "Widen the window for the intended composition.\n"
        )

    frame = build()
    sys.stdout.write("\x1b[?25l")
    try:
        sys.stdout.write(frame)
        sys.stdout.flush()
    finally:
        sys.stdout.write("\x1b[?25h")
        sys.stdout.flush()


if __name__ == "__main__":
    main()
