#!/usr/bin/env python3
"""Linux-side check for Fixtures/formatting.sdlxliff (SDL fmt-defs / tag-defs).

1. Mirrors LinguaCore.FormattingResolver: tag-def id -> fmt (Bold/Italic/Underline/
   TextPosition/TextColor/...), with bpt original-text fallback, nested combine.
2. Byte-safety: a surgical text edit inside a formatted <g> changes only those bytes;
   the header (fmt-defs / tag-defs) and every other byte stay identical, and the
   result re-parses with the same tag structure and formats.
Does not execute Swift (AppKit UI is Mac-only).
"""
from __future__ import annotations

import re
import sys
import xml.etree.ElementTree as ET
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
FIXTURE = ROOT / "Fixtures" / "formatting.sdlxliff"


def local(tag: str) -> str:
    return tag.rsplit("}", 1)[-1] if tag.startswith("{") else tag


def truthy(value: str) -> bool | None:
    v = value.strip().lower()
    if v in {"true", "1", "yes", "on", "single", ""}:
        return True
    if v in {"false", "0", "no", "off", "none", "normal"}:
        return False
    return None


def apply_value(fmt: dict, key: str, value: str) -> None:
    k = key.lower().replace("_", "").replace("-", "")
    if k in {"bold", "b"}:
        fmt["bold"] = truthy(value)
    elif k in {"italic", "i"}:
        fmt["italic"] = truthy(value)
    elif k in {"underline", "u"}:
        b = truthy(value)
        fmt["underline"] = True if b is None and value else b
    elif k in {"strikethrough", "strike"}:
        fmt["strike"] = truthy(value)
    elif k in {"textposition", "superscript", "subscript"}:
        v = value.lower()
        if k == "superscript" and truthy(value):
            fmt["position"] = "superscript"
        elif k == "subscript" and truthy(value):
            fmt["position"] = "subscript"
        elif v.startswith("super"):
            fmt["position"] = "superscript"
        elif v.startswith("sub"):
            fmt["position"] = "subscript"
    elif k in {"textcolor", "color"}:
        fmt["color"] = value
    elif k in {"backgroundcolor", "highlight"}:
        fmt["background"] = value
    elif k in {"fontname", "font"}:
        fmt["fontName"] = value
    elif k in {"fontsize", "size"}:
        fmt["fontSize"] = float(value)


def parse_original(text: str) -> dict:
    fmt: dict = {}
    m = re.match(r"^<([^\s/>]+)(.*?)/?>$", text.strip(), re.S)
    if not m:
        return fmt
    name = m.group(1).lower()
    {"b": lambda: fmt.__setitem__("bold", True), "i": lambda: fmt.__setitem__("italic", True),
     "u": lambda: fmt.__setitem__("underline", True), "sup": lambda: fmt.__setitem__("position", "superscript"),
     "sub": lambda: fmt.__setitem__("position", "subscript")}.get(name, lambda: None)()
    for key, value in re.findall(r"([\w:-]+)(?:=(\"[^\"]*\"|'[^']*'|\S+))?", m.group(2)):
        apply_value(fmt, key, value.strip("\"'"))
    return fmt


def resolve(root) -> dict[str, dict]:
    header = next(e for e in root.iter() if local(e.tag) == "header")
    fmt_defs: dict[str, dict] = {}
    for fd in (e for e in header.iter() if local(e.tag) == "fmt-def"):
        f: dict = {}
        for v in fd:
            if local(v.tag) == "value" and (v.text or "").strip():
                apply_value(f, v.attrib["key"], v.text.strip())
        fmt_defs[fd.attrib["id"]] = f
    result: dict[str, dict] = {}
    for tag_defs in (e for e in header.iter() if local(e.tag) == "tag-defs"):
        for tag in tag_defs:
            if local(tag.tag) != "tag":
                continue
            f: dict = {}
            bpt = next((c for c in tag if local(c.tag) in {"bpt", "bx"}), None)
            if bpt is not None and bpt.text:
                f.update({k: v for k, v in parse_original(bpt.text).items() if v is not None})
            for c in tag:
                if local(c.tag) == "fmt" and c.attrib.get("id") in fmt_defs:
                    f.update({k: v for k, v in fmt_defs[c.attrib["id"]].items() if v is not None})
            if f:
                result[tag.attrib["id"]] = f
    return result


def target_mrk(root, mid: str):
    for t in (e for e in root.iter() if local(e.tag) == "target"):
        for m in t.iter():
            if local(m.tag) == "mrk" and m.attrib.get("mid") == mid:
                return m
    raise AssertionError(f"no target mid={mid}")


def combined_chain(mrk, formats) -> list[dict]:
    out, stack = [], []

    def walk(node):
        pushed = False
        if local(node.tag) == "g" and node.attrib.get("id") in formats:
            stack.append(formats[node.attrib["id"]])
            pushed = True
            eff: dict = {}
            for f in stack:
                eff.update(f)
            out.append(eff)
        for child in node:
            walk(child)
        if pushed:
            stack.pop()

    walk(mrk)
    return out


def header_bytes(raw: bytes) -> bytes:
    start, end = raw.index(b"<header>"), raw.index(b"</header>") + len(b"</header>")
    return raw[start:end]


def inline_shape(mrk) -> list[tuple[str, str]]:
    return [(local(e.tag), e.attrib.get("id", "")) for e in mrk.iter() if local(e.tag) in {"g", "x", "bx", "ex", "ph"}]


def main() -> int:
    raw = FIXTURE.read_bytes()
    root = ET.fromstring(raw)
    formats = resolve(root)

    assert formats["pt1"] == {"bold": True}, formats["pt1"]
    assert formats["pt2"] == {"italic": True}
    assert formats["pt3"]["underline"] is True
    assert formats["pt4"]["position"] == "superscript"
    assert formats["pt6"]["position"] == "subscript"
    assert formats["pt5"]["color"].lower() in {"0xff0000", "ff0000"}
    assert formats["pt7"]["bold"] is False and formats["pt7"]["background"].lower() == "yellow"
    assert formats["pt7"]["fontName"] == "Times New Roman" and formats["pt7"]["fontSize"] == 10.5
    assert formats["pt8"] == {"bold": True, "italic": True}, formats["pt8"]  # bpt fallback
    assert formats["pt9"]["strike"] is True
    assert "pt10" not in formats and "ph11" not in formats
    print("OK resolve: 9 formatted tag-defs (fmt-def + bpt fallback); hyperlink/ph unformatted")

    chain = combined_chain(target_mrk(root, "3"), formats)
    assert chain[0].get("bold") is True and not chain[0].get("italic")
    assert chain[1].get("bold") is True and chain[1].get("italic") is True
    assert chain[2].get("bold") is False and chain[2].get("italic") is True
    print("OK nested: bold → bold+italic → (Bold=False) italic+yellow")

    # Byte-level surgical edit inside <g id="pt1"> of target mid=1.
    old = '<g id="pt1">粗体</g>'.encode()
    new = '<g id="pt1">加粗</g>'.encode()
    assert raw.count(old) == 1
    edited = raw.replace(old, new, 1)
    pos = raw.index(old)
    assert edited[:pos] == raw[:pos], "bytes before edit changed"
    assert edited[pos + len(new):] == raw[pos + len(old):], "bytes after edit changed"
    assert header_bytes(edited) == header_bytes(raw), "header changed"

    root2 = ET.fromstring(edited)
    assert resolve(root2) == formats, "formats changed after edit"
    for mid in ["1", "2", "3", "4", "5"]:
        assert inline_shape(target_mrk(root2, mid)) == inline_shape(target_mrk(root, mid)), mid
    assert "加粗" in "".join(target_mrk(root2, "1").itertext())
    print("OK byte-safe: only edited bytes differ; header + inline tag shape identical; re-parse OK")
    print("linux_formatting_check: all passed")
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except Exception as exc:  # noqa: BLE001
        print(f"FAIL: {exc!r}", file=sys.stderr)
        raise SystemExit(1)
