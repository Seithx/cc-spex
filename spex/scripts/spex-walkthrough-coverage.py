#!/usr/bin/env python3
"""spex-walkthrough-coverage.py - Parse a feature spec for walkthrough synthesis.

Emits, deterministically (Constitution VII), the inputs the walkthrough skill
needs: user stories in priority order, each story's acceptance scenarios and the
functional requirements it references, the FR->story coverage map, orphan FRs
(declared but referenced by no story), and the skip-gate signal.

Usage:
    spex-walkthrough-coverage.py <spec-file> [--json]

Coverage model (FR-003/FR-004):
    An FR is "covered" by a user story when that story's section text references
    the FR's id (e.g. "(FR-001)"). FRs declared in the spec but referenced by no
    story are reported as orphans rather than dropped. This is a deterministic
    baseline; the skill may still exercise orphans at runtime.

Skip gate (FR-006):
    skip is true only when the spec has no user stories AND no acceptance
    scenarios.

Exit codes:
    0   Success (including skip: true)
    1   Parse error (file missing or unreadable)
    2   Usage error
"""

import argparse
import json
import re
import sys

# A user story heading: "### User Story 1 - Title (Priority: P1)"
STORY_RE = re.compile(
    r"^###\s+User Story\s+(\d+)\s*[-–:]\s*(.*?)\s*\(Priority:\s*(P\d+)\)",
    re.IGNORECASE,
)
# A declared functional requirement: "- **FR-001**: ..." (colon marks a definition).
FR_DEF_RE = re.compile(r"\*\*FR-(\d+[a-z]?)\*\*\s*:")
# Any reference to an FR id anywhere in a span.
FR_REF_RE = re.compile(r"FR-(\d+[a-z]?)")
# A numbered acceptance-scenario item: "1. **Given** ..."
SCENARIO_ITEM_RE = re.compile(r"^\s*\d+\.\s+(.*)")
ACCEPTANCE_HEADER_RE = re.compile(r"\*\*Acceptance Scenarios\*\*", re.IGNORECASE)
SECTION_BOUNDARY_RE = re.compile(r"^(#{1,6}\s|---\s*$)")


def fr_sort_key(fr_id):
    """Sort FR ids numerically, keeping a trailing letter suffix stable (11 < 11a < 12)."""
    m = re.search(r"(\d+)([a-z]?)", fr_id)
    return (int(m.group(1)), m.group(2))


def _count_acceptance_scenarios(lines):
    """Count numbered acceptance-scenario items across the whole document.

    Independent of user-story parsing: an "**Acceptance Scenarios**" header
    followed by numbered items counts even when it is not nested under a
    recognized story heading. A section boundary (heading or ---) ends a block.
    """
    count = 0
    in_acceptance = False
    for line in lines:
        if ACCEPTANCE_HEADER_RE.search(line):
            in_acceptance = True
            continue
        if in_acceptance:
            if SECTION_BOUNDARY_RE.match(line):
                in_acceptance = False
                continue
            if SCENARIO_ITEM_RE.match(line):
                count += 1
    return count


def parse_spec(text):
    lines = text.splitlines()

    # Declared FRs (definitions), in declaration order, de-duplicated.
    declared_frs = []
    seen = set()
    for line in lines:
        for m in FR_DEF_RE.finditer(line):
            fr = "FR-" + m.group(1)
            if fr not in seen:
                seen.add(fr)
                declared_frs.append(fr)

    # Locate user story headings and their section spans.
    story_heads = []  # (line_index, num, title, priority)
    for i, line in enumerate(lines):
        m = STORY_RE.match(line)
        if m:
            story_heads.append((i, int(m.group(1)), m.group(2).strip(), m.group(3).upper()))

    stories = []
    for idx, (start, num, title, priority) in enumerate(story_heads):
        # Section span: from this heading to the next section boundary line.
        end = len(lines)
        for j in range(start + 1, len(lines)):
            if SECTION_BOUNDARY_RE.match(lines[j]):
                end = j
                break
        span = lines[start + 1:end]

        # Acceptance scenarios: numbered items following the Acceptance header.
        scenarios = []
        in_acceptance = False
        for sl in span:
            if ACCEPTANCE_HEADER_RE.search(sl):
                in_acceptance = True
                continue
            if in_acceptance:
                sm = SCENARIO_ITEM_RE.match(sl)
                if sm:
                    scenarios.append(sm.group(1).strip())

        # FRs referenced within this story's span (only declared ones count).
        span_text = "\n".join(span)
        story_frs = []
        for m in FR_REF_RE.finditer(span_text):
            fr = "FR-" + m.group(1)
            if fr in seen and fr not in story_frs:
                story_frs.append(fr)

        stories.append({
            "id": f"US{num}",
            "title": title,
            "priority": priority,
            "scenarios": scenarios,
            "frs": sorted(story_frs, key=fr_sort_key),
        })

    # Priority order: P1 before P2 ...; ties broken by story number.
    stories.sort(key=lambda s: (int(s["priority"][1:]), int(s["id"][2:])))

    # FR -> covering stories (preserve priority order of stories).
    fr_coverage = {fr: [] for fr in declared_frs}
    for s in stories:
        for fr in s["frs"]:
            if fr in fr_coverage and s["id"] not in fr_coverage[fr]:
                fr_coverage[fr].append(s["id"])

    orphan_frs = [fr for fr in declared_frs if not fr_coverage[fr]]

    # Skip gate (FR-006): skip only when there are NO user stories AND NO
    # acceptance scenarios. Count acceptance scenarios document-wide, not just
    # within story spans, so a spec whose scenarios are not nested under a
    # matching "### User Story N (Priority: Pn)" heading is NOT wrongly skipped.
    doc_scenarios = _count_acceptance_scenarios(lines)
    skip = len(stories) == 0 and doc_scenarios == 0

    return {
        "skip": skip,
        "stories": stories,
        "fr_coverage": fr_coverage,
        "orphan_frs": orphan_frs,
    }


def main(argv):
    parser = argparse.ArgumentParser(
        prog="spex-walkthrough-coverage.py",
        description="Parse a feature spec for walkthrough synthesis and coverage.",
    )
    parser.add_argument("spec_file", help="Path to the feature spec.md")
    parser.add_argument("--json", action="store_true", help="Emit JSON to stdout")
    args = parser.parse_args(argv)

    try:
        with open(args.spec_file, "r", encoding="utf-8") as f:
            text = f.read()
    except OSError as e:
        print(f"Cannot read spec file: {e}", file=sys.stderr)
        return 1

    result = parse_spec(text)

    if args.json:
        print(json.dumps(result, indent=2))
    else:
        print(f"skip: {result['skip']}")
        for s in result["stories"]:
            print(f"{s['id']} ({s['priority']}) {s['title']} "
                  f"-- scenarios={len(s['scenarios'])} frs={','.join(s['frs']) or '-'}")
        print(f"orphan_frs: {','.join(result['orphan_frs']) or '-'}")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
