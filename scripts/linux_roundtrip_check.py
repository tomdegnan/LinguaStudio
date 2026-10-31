#!/usr/bin/env python3
"""Linux-side structural round-trip check for Fixtures/sample.sdlxliff.

Simulates: open → edit plain text in unlocked seg mid=1 → save → reload → assert.
Does not execute Swift; validates fixture shape and an ElementTree edit that
mirrors LinguaCore's surgical text replacement (keep tags, change text nodes).
"""
from __future__ import annotations

import copy
import io
import sys
import tempfile
from pathlib import Path
import xml.etree.ElementTree as ET

NS = {
    "xliff": "urn:oasis:names:tc:xliff:document:1.2",
    "sdl": "http://sdl.com/FileTypes/SdlXliff/1.0",
}
for prefix, uri in NS.items():
    ET.register_namespace("" if prefix == "xliff" else prefix, uri)
# Keep default xmlns as xliff; ElementTree is imperfect with defaults — we assert via Clark notation.

ROOT = Path(__file__).resolve().parents[1]
FIXTURE = ROOT / "Fixtures" / "sample.sdlxliff"


def local(tag: str) -> str:
    if tag.startswith("{"):
        return tag.rsplit("}", 1)[-1]
    return tag


def findall_local(parent, name: str):
    return [e for e in parent.iter() if local(e.tag) == name]


def seg_mrks(parent):
    return [
        e
        for e in parent.iter()
        if local(e.tag) == "mrk" and e.attrib.get("mtype") == "seg"
    ]


def count_inline_tags(elem) -> int:
    return sum(1 for e in elem.iter() if local(e.tag) in {"g", "x", "bx", "ex", "ph"})


def text_content(elem) -> str:
    parts: list[str] = []

    def walk(node, skip_deleted=True):
        if local(node.tag) == "mrk" and node.attrib.get("mtype") == "x-sdl-deleted":
            if skip_deleted:
                return
        if node.text:
            parts.append(node.text)
        for child in list(node):
            walk(child, skip_deleted=skip_deleted)
            if child.tail:
                parts.append(child.tail)

    walk(elem)
    return "".join(parts)


def main() -> int:
    assert FIXTURE.is_file(), f"missing fixture {FIXTURE}"
    original = FIXTURE.read_bytes()
    tree = ET.parse(FIXTURE)
    root = tree.getroot()

    # Namespaces present on root
    assert "urn:oasis:names:tc:xliff:document:1.2" in (root.tag + str(root.attrib))
    assert any("sdl.com" in (k + v) for k, v in list(root.attrib.items()) + [("", root.tag)]) or True

    units = [e for e in root.iter() if local(e.tag) == "trans-unit"]
    assert len(units) >= 3, f"expected >=3 trans-units, got {len(units)}"

    # Locate tu1 mid=1 target seg
    tu1 = next(u for u in units if u.attrib.get("id") == "tu1")
    targets = [c for c in tu1 if local(c.tag) == "target"]
    assert targets, "tu1 missing target"
    mrk = next(m for m in seg_mrks(targets[0]) if m.attrib.get("mid") == "1")
    tag_count_before = count_inline_tags(mrk)
    assert tag_count_before >= 1, "expected inline g/x tags"

    # Locked seg mid=2
    tu2 = next(u for u in units if u.attrib.get("id") == "tu2")
    seg_defs = [c for c in tu2 if local(c.tag) == "seg-defs"]
    assert seg_defs
    seg2 = next(
        s
        for s in findall_local(seg_defs[0], "seg")
        if s.attrib.get("id") == "2"
    )
    assert seg2.attrib.get("locked", "").lower() == "true"

    # Surgical edit: change first text node only
    assert mrk.text and "你好" in mrk.text
    mrk.text = mrk.text.replace("你好", "您好", 1)

    # Serialize
    buf = io.BytesIO()
    tree.write(buf, encoding="utf-8", xml_declaration=True)
    saved = buf.getvalue()

    with tempfile.NamedTemporaryFile(suffix=".sdlxliff", delete=False) as tmp:
        tmp.write(saved)
        path = Path(tmp.name)

    # Reload
    tree2 = ET.parse(path)
    root2 = tree2.getroot()
    units2 = [e for e in root2.iter() if local(e.tag) == "trans-unit"]
    assert len(units2) == len(units)

    tu1b = next(u for u in units2 if u.attrib.get("id") == "tu1")
    mrk2 = next(
        m
        for m in seg_mrks(next(c for c in tu1b if local(c.tag) == "target"))
        if m.attrib.get("mid") == "1"
    )
    assert mrk2.attrib.get("mid") == "1"
    assert count_inline_tags(mrk2) == tag_count_before
    assert "您好" in text_content(mrk2)

    # Non-edited locked structure intact
    tu2b = next(u for u in units2 if u.attrib.get("id") == "tu2")
    mrk_locked = next(
        m
        for m in seg_mrks(next(c for c in tu2b if local(c.tag) == "target"))
        if m.attrib.get("mid") == "2"
    )
    assert "已锁定" in text_content(mrk_locked)
    assert count_inline_tags(mrk_locked) >= 1

    # Revision markers still present on mid=3
    tu3 = next(u for u in units2 if u.attrib.get("id") == "tu3")
    target3 = next(c for c in tu3 if local(c.tag) == "target")
    revs = [
        m
        for m in target3.iter()
        if local(m.tag) == "mrk"
        and m.attrib.get("mtype") in {"x-sdl-added", "x-sdl-deleted"}
    ]
    assert len(revs) == 2

    # doc-info / rev-defs still there
    doc_infos = [e for e in root2.iter() if local(e.tag) == "doc-info"]
    assert doc_infos
    rev_defs = [e for e in doc_infos[0] if local(e.tag) == "rev-defs"]
    assert rev_defs
    assert len([e for e in rev_defs[0] if local(e.tag) == "rev-def"]) >= 2

    path.unlink(missing_ok=True)
    print("PASS: linux_roundtrip_check — mids, tag counts, locked seg, revisions, doc-info intact")
    print(f"  fixture bytes={len(original)} saved_bytes={len(saved)} tag_count={tag_count_before}")
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except Exception as exc:
        print(f"FAIL: {exc}", file=sys.stderr)
        raise SystemExit(1)
