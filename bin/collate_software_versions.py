#!/usr/bin/env python3

from pathlib import Path
import argparse
import json


SKIP_TOOLS = {
    "awk",
    "bash",
    "cat",
    "cp",
    "coreutils",
    "find",
    "findutils",
    "gawk",
    "gzip",
    "mkdir",
    "mv",
    "rm",
    "sed",
    "sort",
}


def quote(value):
    return json.dumps(str(value))


def parse_simple_yaml(path):
    process = None
    tools = {}
    for raw_line in Path(path).read_text().splitlines():
        if not raw_line.strip():
            continue
        if not raw_line.startswith(" "):
            process = raw_line.strip().rstrip(":").strip('"').strip("'")
            continue
        if ":" not in raw_line:
            continue
        key, value = raw_line.strip().split(":", 1)
        tools[key.strip()] = value.strip().strip('"').strip("'")
    if not process:
        process = Path(path).stem
    return process.split(":")[-1], tools


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("version_files", nargs="+", type=Path)
    parser.add_argument("--out", type=Path, default=Path("software_versions.yml"))
    args = parser.parse_args()

    versions = {}
    for version_file in sorted(args.version_files):
        _process, tools = parse_simple_yaml(version_file)
        for tool, version in tools.items():
            tool = tool.strip().lower()
            version = str(version).strip()
            if not tool or tool in SKIP_TOOLS or not version:
                continue
            versions.setdefault(tool, set()).add(version)

    with args.out.open("w") as out:
        out.write('"software_versions":\n')
        for tool in sorted(versions):
            tool_versions = sorted(versions[tool])
            if len(tool_versions) == 1:
                out.write(f"    {quote(tool)}: {quote(tool_versions[0])}\n")
            else:
                out.write(f"    {quote(tool)}:\n")
                for version in tool_versions:
                    out.write(f"        - {quote(version)}\n")


if __name__ == "__main__":
    main()
