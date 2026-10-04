#!/usr/bin/env python3
"""Generate the Codex harness config (.codex/agents/*.toml, .codex/hooks.json, .agents/skills/) from .claude/.

.claude/ is the source of truth. Run after editing an agent or a hook:

    python3 tools/sync_agent_config.py          # rewrite .codex/
    python3 tools/sync_agent_config.py --check  # exit 1 if .codex/ or .agents/skills/ is stale

.agents/ is gitignored (a skills installer manages it), so its own extra files — e.g. a skill's
agents/openai.yaml — are left alone; only files that exist under .claude/skills are written.
"""

import json
import shutil
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
CLAUDE_AGENTS = ROOT / ".claude" / "agents"
CLAUDE_SETTINGS = ROOT / ".claude" / "settings.json"
CODEX_AGENTS = ROOT / ".codex" / "agents"
CODEX_HOOKS = ROOT / ".codex" / "hooks.json"
CLAUDE_SKILLS = ROOT / ".claude" / "skills"
AGENTS_SKILLS = ROOT / ".agents" / "skills"


def parse_agent(path: Path) -> tuple[dict[str, str], str]:
    text = path.read_text()
    if not text.startswith("---\n"):
        raise SystemExit(f"{path}: missing frontmatter")
    header, body = text[4:].split("\n---\n", 1)
    fields = {}
    for line in header.splitlines():
        key, _, value = line.partition(":")
        fields[key.strip()] = value.strip()
    return fields, body.strip("\n")


def toml_string(value: str) -> str:
    return '"' + value.replace("\\", "\\\\").replace('"', '\\"') + '"'


def toml_multiline(value: str) -> str:
    return '"""\n' + value.replace("\\", "\\\\").replace('"""', '""\\"') + '"""'


def render_agent(path: Path) -> tuple[Path, str]:
    fields, body = parse_agent(path)
    name = fields["name"]
    toml = (
        f"name = {toml_string(name)}\n"
        f"description = {toml_string(fields['description'])}\n"
        f"developer_instructions = {toml_multiline(body)}\n"
    )
    return CODEX_AGENTS / f"{name}.toml", toml


def render_hooks() -> tuple[Path, str]:
    settings = json.loads(CLAUDE_SETTINGS.read_text())
    return CODEX_HOOKS, json.dumps({"hooks": settings["hooks"]}, indent=2, ensure_ascii=False) + "\n"


def render_skills() -> list[tuple[Path, str]]:
    return [
        (AGENTS_SKILLS / source.relative_to(CLAUDE_SKILLS), source.read_text())
        for source in sorted(CLAUDE_SKILLS.rglob("*"))
        if source.is_file() and source.name != ".DS_Store"
    ]


def main() -> int:
    check = "--check" in sys.argv[1:]
    outputs = [render_agent(p) for p in sorted(CLAUDE_AGENTS.glob("*.md"))] + [render_hooks()] + render_skills()
    expected = {path for path, _ in outputs}
    orphans = sorted(p for p in CODEX_AGENTS.glob("*.toml") if p not in expected)
    # A whole skill gone from .claude/skills; files the installer added inside a live skill stay.
    orphans += sorted(p for p in AGENTS_SKILLS.glob("*/") if not (CLAUDE_SKILLS / p.name).is_dir())

    stale = [path for path, text in outputs if not path.exists() or path.read_text() != text]
    if check:
        for path in stale + orphans:
            print(f"stale: {path.relative_to(ROOT)}")
        if stale or orphans:
            print("Run python3 tools/sync_agent_config.py")
            return 1
        return 0

    for path, text in outputs:
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(text)
    for path in orphans:
        shutil.rmtree(path) if path.is_dir() else path.unlink()
    for path in stale + orphans:
        print(f"updated: {path.relative_to(ROOT)}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
