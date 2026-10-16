#!/usr/bin/env python3
"""Static consistency checks for the EVERAFTER Godot 4 project.

This script does NOT replace the engine. It complements the headless test suite
by catching, without Godot installed, the class of mistakes that would only
show up as a black screen or a "cannot open scene" dialog at runtime:

  * paths referenced from `project.godot` (main scene, autoloads, icon);
  * `res://` references in scripts, scenes and resources;
  * `ext_resource` / `sub_resource` wiring inside `.tscn` files;
  * the node tree of every scene versus the `$Node/Path` lookups written in the
    scripts attached to it (this is what catches a typo like `$Terrain/Meshh`);
  * input actions used by scripts versus actions declared in `project.godot`;
  * `.gitignore` accidentally excluding a file that is tracked by git.

Usage:
    python3 tools/check_project.py            # from the repository root
    python3 tools/check_project.py --verbose

Exit code: 0 when no error was found, 1 otherwise.
"""

from __future__ import annotations

import argparse
import re
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
IGNORED_DIRS = {".git", ".godot", ".venv", "venv", "__pycache__", ".pytest_cache"}

# `res://` paths whose basename starts with "__" are deliberate placeholders
# used by the tests (for example a config file that must not exist).
PLACEHOLDER_PREFIX = "__"

BUILTIN_ACTIONS = {
    "ui_accept",
    "ui_cancel",
    "ui_focus_next",
    "ui_focus_prev",
    "ui_left",
    "ui_right",
    "ui_up",
    "ui_down",
    "ui_home",
    "ui_end",
    "ui_page_up",
    "ui_page_down",
    "ui_text_submit",
}

RES_PATH_RE = re.compile(r"res://[A-Za-z0-9_./\-]+")
EXT_RESOURCE_RE = re.compile(
    r'\[ext_resource\s+(?P<attrs>[^\]]*)\]', re.IGNORECASE
)
ATTR_RE = re.compile(r'(\w+)="([^"]*)"')
SUB_RESOURCE_RE = re.compile(r'\[sub_resource\s+type="(?P<type>[^"]+)"\s+id="(?P<id>[^"]+)"')
NODE_RE = re.compile(r'\[node\s+name="(?P<name>[^"]+)"(?:\s+type="(?P<type>[^"]+)")?'
                     r'(?:\s+parent="(?P<parent>[^"]*)")?(?:\s+instance=(?P<instance>[^ \]]+))?')
SCRIPT_PROP_RE = re.compile(r'^script = ExtResource\("(?P<id>[^"]+)"\)')
ONREADY_RE = re.compile(r'@onready\s+var\s+\w+[^\n]*=\s*\$"?([A-Za-z0-9_/%]+)"?')
GET_NODE_RE = re.compile(r'get_node\(\s*\$?"?([A-Za-z0-9_/%]+)"?\s*\)')
ACTION_RE = re.compile(r'is_action_(?:just_)?(?:pressed|released)\(\s*"([^"]+)"')
GET_VECTOR_RE = re.compile(r'get_vector\(\s*"([^"]+)"\s*,\s*"([^"]+)"\s*,\s*"([^"]+)"\s*,\s*"([^"]+)"')
CLASS_NAME_RE = re.compile(r'^class_name\s+(\w+)', re.MULTILINE)


class Report:
    def __init__(self, verbose: bool) -> None:
        self.errors: list[str] = []
        self.notes: list[str] = []
        self.verbose = verbose

    def error(self, message: str) -> None:
        self.errors.append(message)

    def note(self, message: str) -> None:
        self.notes.append(message)

    def ok(self, message: str) -> None:
        if self.verbose:
            print(f"  ok   {message}")


def iter_project_files(suffix: str) -> list[Path]:
    return sorted(
        path
        for path in ROOT.rglob(f"*{suffix}")
        if not any(part in IGNORED_DIRS for part in path.relative_to(ROOT).parts)
    )


def read(path: Path) -> str:
    return path.read_text(encoding="utf-8", errors="replace")


def rel(path: Path) -> str:
    return path.relative_to(ROOT).as_posix()


def res_to_fs(res_path: str) -> Path:
    return ROOT / res_path[len("res://"):]


# --------------------------------------------------------------------------- #
# project.godot
# --------------------------------------------------------------------------- #
def parse_project_godot(report: Report) -> dict[str, dict[str, str]]:
    """Minimal INI reader.

    Godot writes input actions as multi-line dictionaries, which a strict INI
    parser rejects. We only need the single-line `key=value` pairs plus the
    names of the actions, so we track brace depth and skip dictionary bodies.
    """
    path = ROOT / "project.godot"
    if not path.exists():
        report.error("project.godot is missing")
        return {}
    sections: dict[str, dict[str, str]] = {}
    current: dict[str, str] = {}
    depth = 0
    for raw in read(path).splitlines():
        line = raw.strip()
        if depth > 0:
            depth += line.count("{") + line.count("[") - line.count("}") - line.count("]")
            # The action name was already recorded when the block opened.
            continue
        if not line or line.startswith(";") or line.startswith("#"):
            continue
        if line.startswith("[") and line.endswith("]"):
            sections.setdefault(line[1:-1], {})
            current = sections[line[1:-1]]
            continue
        if "=" not in line:
            continue
        key, value = line.split("=", 1)
        current[key.strip()] = value.strip()
        depth = value.count("{") + value.count("[") - value.count("}") - value.count("]")
    report.ok(f"project.godot parsed ({len(sections)} sections)")
    return sections


def check_project_settings(sections: dict[str, dict[str, str]], report: Report) -> None:
    application = sections.get("application", {})
    for key in ("config/name", "run/main_scene"):
        if not application.get(key):
            report.error(f"project.godot: application/{key} is missing")

    main_scene = application.get("run/main_scene", "").strip('"')
    if main_scene:
        if not res_to_fs(main_scene).exists():
            report.error(f"project.godot: main scene does not exist: {main_scene}")
        elif not main_scene.endswith(".tscn"):
            report.error(f"project.godot: main scene is not a .tscn: {main_scene}")
        else:
            report.ok(f"main scene exists: {main_scene}")

    icon = application.get("config/icon", "").strip('"')
    if icon and not res_to_fs(icon).exists():
        report.error(f"project.godot: icon does not exist: {icon}")

    for name, value in sorted(sections.get("autoload", {}).items()):
        # Values look like "*res://path/script.gd" (leading quotes, then the
        # optional '*' that marks the autoload as enabled).
        script = value.strip().strip('"').lstrip("*").strip('"')
        if not script.startswith("res://"):
            report.error(f"project.godot: autoload {name} has an unexpected value: {value}")
            continue
        if not res_to_fs(script).exists():
            report.error(f"project.godot: autoload {name} script does not exist: {script}")
        else:
            report.ok(f"autoload {name} -> {script}")


def declared_actions(sections: dict[str, dict[str, str]]) -> set[str]:
    return set(sections.get("input", {}).keys())


# --------------------------------------------------------------------------- #
# files
# --------------------------------------------------------------------------- #
def check_res_references(report: Report) -> None:
    for path in iter_project_files(".gd") + iter_project_files(".tscn") + iter_project_files(".tres"):
        for match in RES_PATH_RE.finditer(read(path)):
            res_path = match.group(0)
            name = res_path.rsplit("/", 1)[-1]
            if name.startswith(PLACEHOLDER_PREFIX):
                report.ok(f"{rel(path)}: placeholder reference ignored ({res_path})")
                continue
            if not res_to_fs(res_path).exists():
                report.error(f"{rel(path)}: references a missing file: {res_path}")


def check_scripts_used_by_scenes(report: Report) -> set[str]:
    """Collects the scripts attached to scenes (used later for the autoload check)."""
    used: set[str] = set()
    for path in iter_project_files(".tscn"):
        text = read(path)
        for match in SCRIPT_PROP_RE.finditer(text):
            ext_id = match.group("id")
            ext = find_ext_resource(text, ext_id)
            if ext is None:
                report.error(f"{rel(path)}: script = ExtResource(\"{ext_id}\") has no ext_resource")
                continue
            used.add(ext["path"])
    return used


def find_ext_resource(text: str, ext_id: str) -> dict[str, str] | None:
    for match in EXT_RESOURCE_RE.finditer(text):
        attrs = dict(ATTR_RE.findall(match.group("attrs")))
        if attrs.get("id") == ext_id:
            return attrs
    return None


def check_scenes(report: Report) -> None:
    for path in iter_project_files(".tscn"):
        text = read(path)
        name = rel(path)

        ext_ids: set[str] = set()
        for match in EXT_RESOURCE_RE.finditer(text):
            attrs = dict(ATTR_RE.findall(match.group("attrs")))
            ext_id = attrs.get("id", "")
            if not ext_id:
                report.error(f"{name}: ext_resource without id: {match.group(0)}")
                continue
            ext_ids.add(ext_id)
            res_path = attrs.get("path", "")
            if not res_path.startswith("res://"):
                report.error(f"{name}: ext_resource {ext_id} has no res:// path")
                continue
            if not res_to_fs(res_path).exists():
                report.error(f"{name}: ext_resource {ext_id} does not exist: {res_path}")
            expected = ".tscn" if attrs.get("type") == "PackedScene" else ".gd" \
                if attrs.get("type") == "Script" else ""
            if expected and not res_path.endswith(expected):
                report.error(
                    f"{name}: ext_resource {ext_id} is declared {attrs.get('type')} "
                    f"but points to {res_path}"
                )

        sub_ids = {match.group("id") for match in SUB_RESOURCE_RE.finditer(text)}

        for match in re.finditer(r'(?:ExtResource|SubResource)\("(?P<id>[^"]+)"\)', text):
            ref = match.group("id")
            kind = match.group(0).split("(")[0]
            pool = ext_ids if kind == "ExtResource" else sub_ids
            if ref not in pool:
                report.error(f"{name}: {kind}(\"{ref}\") is not declared in the file")

        nodes = parse_scene_nodes(text)
        for node in nodes:
            parent = node["parent"]
            if parent is None:
                continue
            if parent != "." and parent not in {n["path"] for n in nodes}:
                report.error(f"{name}: node \"{node['name']}\" has unknown parent \"{parent}\"")

        check_scene_script_node_paths(name, text, nodes, report)
        report.ok(f"{name}: {len(nodes)} nodes, {len(ext_ids)} ext, {len(sub_ids)} sub resources")


def parse_scene_nodes(text: str) -> list[dict[str, str | None]]:
    nodes: list[dict[str, str | None]] = []
    for match in NODE_RE.finditer(text):
        parent = match.group("parent")
        node_name = match.group("name")
        if parent is None:
            node_path = ""  # scene root
        elif parent == ".":
            node_path = node_name
        else:
            node_path = f"{parent}/{node_name}"
        nodes.append(
            {
                "name": node_name,
                "parent": parent,
                "path": node_path,
                "instance": match.group("instance"),
            }
        )
    return nodes


def check_scene_script_node_paths(
    scene_name: str, text: str, nodes: list[dict[str, str | None]], report: Report
) -> None:
    """Every `$Path` written in an attached script must exist in the scene."""
    lines = text.splitlines()
    current_node: dict[str, str | None] | None = None
    node_by_path = {n["path"]: n for n in nodes}
    for line in lines:
        node_match = NODE_RE.match(line.strip())
        if node_match:
            current_node = node_by_path.get(
                build_node_path(node_match, nodes), None
            ) or current_node
            continue
        script_match = SCRIPT_PROP_RE.match(line.strip())
        if script_match and current_node is not None:
            ext = find_ext_resource(text, script_match.group("id"))
            if ext is None:
                continue
            script_path = res_to_fs(ext["path"])
            if not script_path.exists():
                continue
            check_script_node_paths(scene_name, current_node["path"], script_path, node_by_path, report)


def build_node_path(match: re.Match, nodes: list[dict[str, str | None]]) -> str:
    parent = match.group("parent")
    node_name = match.group("name")
    if parent is None:
        return ""
    if parent == ".":
        return node_name
    return f"{parent}/{node_name}"


def check_script_node_paths(
    scene_name: str,
    node_path: str | None,
    script_path: Path,
    node_by_path: dict[str, dict[str, str | None]],
    report: Report,
) -> None:
    for pattern in (ONREADY_RE, GET_NODE_RE):
        for match in pattern.finditer(read(script_path)):
            lookup = match.group(1)
            if lookup.startswith("%"):
                report.ok(f"{rel(script_path)}: unique-name lookup skipped ({lookup})")
                continue
            target = lookup if not node_path else f"{node_path}/{lookup}"
            if target not in node_by_path:
                report.error(
                    f"{rel(script_path)} (on {scene_name}:{node_path or '<root>'}): "
                    f"node path \"${lookup}\" does not exist in the scene"
                )
            else:
                report.ok(f"{rel(script_path)}: ${lookup} resolves")


def check_actions(sections: dict[str, dict[str, str]], report: Report) -> None:
    declared = declared_actions(sections) | BUILTIN_ACTIONS
    for path in iter_project_files(".gd"):
        text = read(path)
        used: set[str] = set()
        for match in ACTION_RE.finditer(text):
            used.add(match.group(1))
        for match in GET_VECTOR_RE.finditer(text):
            used.update(match.groups())
        for action in sorted(used):
            if action not in declared:
                report.error(f"{rel(path)}: uses undeclared input action \"{action}\"")
            else:
                report.ok(f"{rel(path)}: action \"{action}\" is declared")
    # Reverse direction: an action nobody uses is a documentation lie waiting to happen.
    all_used: set[str] = set()
    for path in iter_project_files(".gd"):
        text = read(path)
        all_used.update(m.group(1) for m in ACTION_RE.finditer(text))
        for match in GET_VECTOR_RE.finditer(text):
            all_used.update(match.groups())
    for action in sorted(declared_actions(sections)):
        if action not in all_used:
            report.note(f"input action \"{action}\" is declared but never used in any script")


def check_class_names(report: Report) -> None:
    autoload_scripts = set()
    for value in parse_project_godot(report).get("autoload", {}).values():
        autoload_scripts.add(value.strip().strip('"').lstrip("*").strip('"'))
    seen: dict[str, str] = {}
    for path in iter_project_files(".gd"):
        match = CLASS_NAME_RE.search(read(path))
        res_path = "res://" + rel(path)
        if match:
            class_name = match.group(1)
            if class_name in seen:
                report.error(f"class_name {class_name} declared twice: {seen[class_name]} and {rel(path)}")
            seen[class_name] = rel(path)
            if res_path in autoload_scripts:
                report.error(f"{rel(path)}: autoload scripts must not declare a class_name")
    report.ok(f"{len(seen)} global class names, no duplicates")


def check_gitignore(report: Report) -> None:
    try:
        tracked = subprocess.run(
            ["git", "ls-files"], cwd=ROOT, capture_output=True, text=True, check=True
        ).stdout.splitlines()
    except (OSError, subprocess.CalledProcessError) as exc:
        report.note(f"git check skipped: {exc}")
        return
    ignored = []
    for file_name in tracked:
        result = subprocess.run(
            ["git", "check-ignore", "-q", file_name], cwd=ROOT, capture_output=True
        )
        if result.returncode == 0:
            ignored.append(file_name)
    if ignored:
        for file_name in ignored:
            report.error(f".gitignore excludes a tracked file: {file_name}")
    else:
        report.ok(f".gitignore does not exclude any of the {len(tracked)} tracked files")


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--verbose", action="store_true", help="print every successful check")
    args = parser.parse_args()

    report = Report(args.verbose)
    print("EVERAFTER static project checks")
    print(f"root: {ROOT}")
    print("-" * 60)

    sections = parse_project_godot(report)
    check_project_settings(sections, report)
    check_scenes(report)
    check_scripts_used_by_scenes(report)
    check_res_references(report)
    check_actions(sections, report)
    check_class_names(report)
    check_gitignore(report)

    print("-" * 60)
    for note in report.notes:
        print(f"NOTE  {note}")
    for error in report.errors:
        print(f"ERROR {error}")
    print("-" * 60)
    if report.errors:
        print(f"RESULT: {len(report.errors)} error(s)")
        return 1
    print("RESULT: OK")
    return 0


if __name__ == "__main__":
    sys.exit(main())
