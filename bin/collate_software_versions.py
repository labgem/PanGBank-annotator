#!/usr/bin/env python3

from pathlib import Path
import argparse
import json


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
        process, tools = parse_simple_yaml(version_file)
        if process in versions and versions[process] != tools:
            raise SystemExit(
                f"conflicting software versions for {process}: "
                f"{versions[process]} != {tools}"
            )
        versions[process] = tools

    with args.out.open("w") as out:
        for process in sorted(versions):
            out.write(f"{quote(process)}:\n")
            for tool, version in sorted(versions[process].items()):
                out.write(f"    {quote(tool)}: {quote(version)}\n")


if __name__ == "__main__":
    main()
