#!/usr/bin/env python3
"""ContinuityOS — structural validation for the Eww shell.

There is no `eww` binary on the machine this repo is developed on, so a typo in
eww.yuck cannot be caught by running it. This catches the failures that matter:

  * unbalanced parentheses (the usual cause of "eww: parse error")
  * a call to a widget that was never defined (or was renamed)
  * a duplicated widget/window definition
  * a window with no :geometry (Eww then picks a useless default size)
  * the window names the rest of the repo depends on going missing

Usage: check-eww.py [--quiet] [path/to/eww.yuck]
Exit:  0 clean, 1 problems found.
"""
from __future__ import annotations

import re
import sys
from pathlib import Path

# Forms Eww understands natively. Anything called that is not in this set must be
# a widget defined in the same file.
BUILTINS = {
    "box", "label", "button", "scale", "scroll", "image", "eventbox", "revealer",
    "overlay", "progress", "input", "calendar", "colorbutton", "comboboxtext",
    "circle", "graph", "literal", "transform", "slider", "expander", "tooltip",
    "defwidget", "defwindow", "defpoll", "deflisten", "defvar", "include",
    "geometry", "for", "composite",
}

# Window names other components open by name (see bin/continuity-panel and
# bin/continuity-wizard show_page). Renaming one silently breaks a button.
REQUIRED_WINDOWS = {
    "dock", "drawer", "notifications",
    "wizard", "wizard-steam", "wizard-windows", "wizard-mode", "wizard-done",
}


def strip_comments_and_strings(text: str) -> str:
    """Remove ; comments (outside strings) and the contents of "..." strings.

    Parentheses inside user-facing text are not structural, and a stray
    semicolon in a label must not be read as a comment.
    """
    out = []
    in_string = False
    escaped = False
    i = 0
    while i < len(text):
        ch = text[i]
        if in_string:
            if escaped:
                escaped = False
            elif ch == "\\":
                escaped = True
            elif ch == '"':
                in_string = False
                out.append('""')
            i += 1
            continue
        if ch == '"':
            in_string = True
            i += 1
            continue
        if ch == ";":
            # comment to end of line
            j = text.find("\n", i)
            i = len(text) if j == -1 else j
            continue
        out.append(ch)
        i += 1
    return "".join(out)


def main() -> int:
    args = [a for a in sys.argv[1:] if not a.startswith("-")]
    quiet = "--quiet" in sys.argv
    default = Path(__file__).resolve().parent.parent / "config" / "eww" / "eww.yuck"
    path = Path(args[0]) if args else default
    if not path.is_file():
        print(f"check-eww: no such file: {path}")
        return 1

    problems: list[str] = []
    text = path.read_text(encoding="utf-8")

    if text.count('"') % 2 != 0:
        problems.append("an odd number of double quotes — a string is unterminated")

    clean = strip_comments_and_strings(text)

    opens, closes = clean.count("("), clean.count(")")
    if opens != closes:
        problems.append(f"unbalanced parentheses: {opens} '(' vs {closes} ')'")

    widgets = re.findall(r"\(defwidget\s+([A-Za-z0-9_-]+)", clean)
    windows = re.findall(r"\(defwindow\s+([A-Za-z0-9_-]+)", clean)
    polls = re.findall(r"\(defpoll\s+([A-Za-z0-9_-]+)", clean)
    variables = re.findall(r"\(defvar\s+([A-Za-z0-9_-]+)", clean)

    for label, names in (("widget", widgets), ("window", windows), ("poll", polls)):
        seen: set[str] = set()
        for name in names:
            if name in seen:
                problems.append(f"duplicate {label} definition: {name}")
            seen.add(name)

    defined = set(widgets) | set(windows) | set(polls) | set(variables)

    used = set(re.findall(r"\(([A-Za-z][A-Za-z0-9_-]*)", clean))
    unknown = sorted(n for n in used if n not in BUILTINS and n not in defined)
    for name in unknown:
        problems.append(f"call to undefined widget/function: {name}")

    # Unused widget definitions are a smell, not an error: report as a note.
    unused = sorted(w for w in set(widgets) if len(re.findall(rf"\({re.escape(w)}\s", clean)) < 2)

    missing = sorted(REQUIRED_WINDOWS - set(windows))
    for name in missing:
        problems.append(f"required window is missing: {name}")

    for name in windows:
        body = re.search(rf"\(defwindow\s+{re.escape(name)}(.*?)(?=\(defwindow|\Z)", clean, re.S)
        if body and ":geometry" not in body.group(1)[:1500]:
            problems.append(f"window '{name}' has no :geometry (Eww will size it oddly)")

    if not quiet:
        print(f"  eww.yuck: {len(windows)} windows, {len(widgets)} widgets, {len(polls)} polls")
        if unused:
            print(f"  note: defined but never called: {', '.join(unused)}")

    if problems:
        for p in problems:
            print(f"  FAIL {path.name}: {p}")
        return 1

    print(f"  PASS eww.yuck structure ({len(windows)} windows, {len(widgets)} widgets)")
    return 0


if __name__ == "__main__":
    sys.exit(main())
