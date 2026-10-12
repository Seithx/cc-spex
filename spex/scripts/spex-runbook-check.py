#!/usr/bin/env python3
"""spex-runbook-check.py - Mechanical structure, placeholder, and secret checks
for a RUNBOOK.md (research R8).

Output: RUNBOOK_CHECK_PASS, or one `RUNBOOK_CHECK_FAIL <kind> line=<n> <detail>`
per finding, where kind is frontmatter, structure, placeholder, or secret.
Exit 0 clean, 1 findings, 2 usage or file missing.
"""
import re
import sys

STEP_HEADING = re.compile(r"^### Step \d+ of \d+:")

STRUCTURE_MARKERS = [
    ("**Why this step:**", "Why this step"),
    ("**What you should see:**", "What you should see"),
    ("**If you see something else:**", "If you see something else"),
]

PLACEHOLDER_PATTERNS = [
    r"<[A-Za-z0-9_-]+>",
    r"/path/to/",
    r"\bTODO\b",
    r"\bPLACEHOLDER\b",
    r"\bYOUR_[A-Z0-9_]+",
]

SECRET_PATTERNS = [
    r"ghp_[A-Za-z0-9]{20,}",
    r"gho_[A-Za-z0-9]{20,}",
    r"github_pat_[A-Za-z0-9_]{20,}",
    r"glpat-[A-Za-z0-9_-]{20,}",
    # sk- includes '-' so modern sk-proj-… keys are caught, not just legacy sk-….
    r"sk-[A-Za-z0-9-]{20,}",
    r"xox[baprs]-[A-Za-z0-9-]{10,}",
    r"AKIA[0-9A-Z]{16}",
    r"AIza[0-9A-Za-z_\-]{35}",
    r"eyJ[A-Za-z0-9_-]+\.eyJ[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+",
    # PEM/OpenSSH private key blocks (TLS, SSH) - a BEGIN marker means a real key.
    r"-----BEGIN [A-Z0-9 ]*PRIVATE KEY-----",
    # kubeconfig embedded cert/key material (value form, not the already-redacted form).
    r"(?i)(?:client-key-data|client-certificate-data)\s*:\s*(?!\[redacted\])[A-Za-z0-9+/=]{20,}",
    r"(?i)bearer\s+[A-Za-z0-9._-]{20,}",
    r"(?i)(?:password|token|secret|api_key)\s*[=:]\s*(?!\[redacted\])\S{8,}",
]


def parse_frontmatter(text):
    """Return (ok, steps_total_or_None)."""
    if not text.startswith("---"):
        return False, None
    m = re.match(r"^---\n(.*?)\n---\n?", text, re.DOTALL)
    if not m:
        return False, None
    steps_total = None
    for line in m.group(1).splitlines():
        if not line.strip():
            continue
        mm = re.match(r"^([A-Za-z0-9_]+):\s?(.*)$", line)
        if not mm:
            return False, None
        if mm.group(1) == "steps_total":
            try:
                steps_total = int(mm.group(2))
            except ValueError:
                return True, None
    return True, steps_total


def main(argv):
    if len(argv) != 1:
        sys.stderr.write("usage: spex-runbook-check.sh <runbook>\n")
        return 2
    path = argv[0]
    try:
        with open(path, encoding="utf-8") as f:
            text = f.read()
    except OSError:
        sys.stderr.write("runbook file not found: {}\n".format(path))
        return 2

    lines = text.split("\n")
    findings = []  # (kind, line_no, detail)

    # 1. Frontmatter + steps_total vs heading count
    heading_idx = [i for i, l in enumerate(lines) if STEP_HEADING.match(l)]
    fm_ok, steps_total = parse_frontmatter(text)
    if not fm_ok:
        findings.append(("frontmatter", 1, "missing or unparseable frontmatter"))
    elif steps_total is None:
        findings.append(("frontmatter", 1, "steps_total missing or not an integer"))
    elif steps_total != len(heading_idx):
        findings.append(("frontmatter", 1, "steps_total {} does not match {} step headings".format(
            steps_total, len(heading_idx))))

    # 2. Structure, per step block
    for bi, start in enumerate(heading_idx):
        end = heading_idx[bi + 1] if bi + 1 < len(heading_idx) else len(lines)
        block = "\n".join(lines[start:end])
        hd_line = start + 1
        for marker, label in STRUCTURE_MARKERS:
            if marker not in block:
                findings.append(("structure", hd_line, "step missing '{}'".format(label)))
        has_run_fence = "**Run:**" in block and "```" in block
        has_do = "**Do:**" in block
        if not (has_run_fence or has_do):
            findings.append(("structure", hd_line,
                             "step has neither a Run with a fenced block nor a Do list"))

    # 3. Placeholders inside command blocks only (FR-036). A command block is a
    #    fence that directly follows a **Run:** marker; output/result fences
    #    (e.g. ```text with real command output) are not placeholder-checked.
    in_fence = False
    scan_fence = False
    last_marker = ""
    for i, l in enumerate(lines):
        if l.lstrip().startswith("```"):
            if not in_fence:
                in_fence = True
                scan_fence = last_marker == "**Run:**"
            else:
                in_fence = False
                scan_fence = False
            continue
        if in_fence:
            if scan_fence:
                for pat in PLACEHOLDER_PATTERNS:
                    if re.search(pat, l):
                        findings.append(("placeholder", i + 1,
                                         "placeholder token in command block: {}".format(l.strip())))
                        break
        elif l.strip():
            last_marker = l.strip()

    # 4. Secrets anywhere
    for i, l in enumerate(lines):
        for pat in SECRET_PATTERNS:
            if re.search(pat, l):
                findings.append(("secret", i + 1, "possible unredacted credential"))
                break

    if not findings:
        print("RUNBOOK_CHECK_PASS")
        return 0
    findings.sort(key=lambda f: (f[1], f[0]))
    for kind, ln, detail in findings:
        print("RUNBOOK_CHECK_FAIL {} line={} {}".format(kind, ln, detail))
    return 1


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
