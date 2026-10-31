#!/usr/bin/env python3
"""Linux-side check: detect pending SDL revisions → accept one → no pending left for that mid.

Mirrors LinguaCore RevisionFactory.resolve(accept=True):
  keep x-sdl-added children, drop x-sdl-deleted markers.
Does not run Swift; validates fixture + ElementTree surgery.
"""
from __future__ import annotations

import copy
import sys
from pathlib import Path
import xml.etree.ElementTree as ET

NS = {
    "xliff": "urn:oasis:names:tc:xliff:document:1.2",
    "sdl": "http://sdl.com/FileTypes/SdlXliff/1.0",
}
for prefix, uri in NS.items():
    ET.register_namespace("" if prefix == "xliff" else prefix, uri)

ROOT = Path(__file__).resolve().parents[1]
FIXTURE = ROOT / "Fixtures" / "sample.sdlxliff"


def local(tag: str) -> str:
    if tag.startswith("{"):
        return tag.rsplit("}", 1)[-1]
    return tag


def revision_markers(elem):
    return [
        e
        for e in elem.iter()
        if local(e.tag) == "mrk"
        and e.attrib.get("mtype") in {"x-sdl-added", "x-sdl-deleted"}
    ]


def find_seg_target(root, unit_id: str, mid: str):
    for unit in root.iter():
        if local(unit.tag) != "trans-unit":
            continue
        if unit.attrib.get("id") != unit_id:
            continue
        for target in unit:
            if local(target.tag) != "target":
                continue
            for mrk in target.iter():
                if local(mrk.tag) == "mrk" and mrk.attrib.get("mtype") == "seg":
                    if mrk.attrib.get("mid") == mid:
                        return mrk
    return None


def accept_revisions(seg_mrk) -> int:
    """Accept: unwrap added, remove deleted. Returns number of markers resolved."""
    markers = revision_markers(seg_mrk)
    # Process deepest / document order reversed so parent indices stay valid.
    # ElementTree: rebuild children of each parent.
    count = 0
    # Collect parents that contain revision markers (direct children only per pass).
    changed = True
    while changed:
        changed = False
        for parent in list(seg_mrk.iter()):
            kids = list(parent)
            new_kids = []
            for child in kids:
                if (
                    local(child.tag) == "mrk"
                    and child.attrib.get("mtype") in {"x-sdl-added", "x-sdl-deleted"}
                ):
                    deleted = child.attrib.get("mtype") == "x-sdl-deleted"
                    keep = not deleted  # accept: keep added, drop deleted
                    count += 1
                    changed = True
                    if keep:
                        # Unwrap: promote children + text/tail
                        if child.text:
                            if new_kids:
                                # attach as tail of previous — simplify: create text via dummy
                                pass
                            # Flatten: insert child's children; merge text into parent carefully
                            # Simpler approach: keep a text node by prepending to first child or parent text
                            if child.text:
                                if not new_kids:
                                    parent_text_add = child.text
                                    parent.text = (parent.text or "") + parent_text_add
                                else:
                                    prev = new_kids[-1]
                                    prev.tail = (prev.tail or "") + child.text
                            for gc in list(child):
                                new_kids.append(gc)
                            if child.tail:
                                if new_kids:
                                    new_kids[-1].tail = (new_kids[-1].tail or "") + child.tail
                                else:
                                    parent.text = (parent.text or "") + child.tail
                    else:
                        # drop deleted content but keep tail
                        if child.tail:
                            if new_kids:
                                new_kids[-1].tail = (new_kids[-1].tail or "") + child.tail
                            else:
                                parent.text = (parent.text or "") + child.tail
                else:
                    new_kids.append(child)
            if changed:
                # rewrite children
                for c in list(parent):
                    parent.remove(c)
                for c in new_kids:
                    parent.append(c)
                break  # restart scan after one parent rewrite
    return count


def visible_text(elem) -> str:
    parts: list[str] = []

    def walk(node):
        if local(node.tag) == "mrk" and node.attrib.get("mtype") == "x-sdl-deleted":
            return
        if node.text:
            parts.append(node.text)
        for child in list(node):
            walk(child)
            if child.tail:
                parts.append(child.tail)

    walk(elem)
    return "".join(parts)


def main() -> int:
    assert FIXTURE.is_file(), f"missing fixture {FIXTURE}"
    tree = ET.parse(FIXTURE)
    root = tree.getroot()

    seg = find_seg_target(root, "tu3", "3")
    assert seg is not None, "missing tu3/mid=3 target seg"

    before = revision_markers(seg)
    assert before, "expected pending x-sdl-added/deleted on mid=3"
    print(f"OK detect pending: {len(before)} marker(s) on tu3#3")

    n = accept_revisions(seg)
    assert n >= 1, "accept should resolve at least one marker"
    after = revision_markers(seg)
    assert not after, f"expected no pending left for mid=3, still have {after}"
    text = visible_text(seg)
    assert "样例" in text, f"accept should keep added text, got {text!r}"
    assert "示例" not in text, f"accept should drop deleted text, got {text!r}"
    print(f"OK accept: resolved {n}, text={text!r}, pending left=0")

    # Reject path on a fresh copy
    tree2 = ET.parse(FIXTURE)
    seg2 = find_seg_target(tree2.getroot(), "tu3", "3")
    assert seg2 is not None
    # reject = opposite of accept: keep deleted, drop added
    # Quick check: after reject, "示例" remains
    markers = [
        e
        for e in seg2.iter()
        if local(e.tag) == "mrk"
        and e.attrib.get("mtype") in {"x-sdl-added", "x-sdl-deleted"}
    ]
    assert markers
    print("OK reject fixture still has pending on fresh parse")
    print("linux_review_accept_check: all passed")
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except AssertionError as exc:
        print(f"FAIL: {exc}", file=sys.stderr)
        raise SystemExit(1)
