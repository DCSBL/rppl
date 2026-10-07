#!/usr/bin/env python3
"""Rewrite park YAML from JSON-style flow collections to native block style.

Usage:
    python3 scripts/format_parks.py [--check] [park.yaml ...]

    location: { lat: 52.0, lon: 5.0 }    becomes    location:
    days: [sat, sun]                                    lat: 52.0
                                                        lon: 5.0
                                                      days:
                                                        - sat
                                                        - sun

With no files, every park under RpplCore/Sources/RpplCore/Resources/Parks/*.yaml is
rewritten in place. `--check` only reports and exits 1 when a file would change.

Only the flow collections are replaced; comments, blank lines, quoting and block scalars
elsewhere are untouched. Empty `{}` / `[]` stay as they are (block style cannot express them).
The result must parse to the same data as the input, otherwise the file is left alone.
`scripts/validate_parks.py` reports flow style through `flow_spots`.
"""

from __future__ import annotations

import json
import sys
from pathlib import Path

try:
    import yaml
except ImportError:
    print("error: PyYAML is required (pip install pyyaml)", file=sys.stderr)
    sys.exit(2)

PARKS_DIR = Path(__file__).resolve().parent.parent / "RpplCore" / "Sources" / "RpplCore" / "Resources" / "Parks"

Collection = yaml.MappingNode | yaml.SequenceNode


def flow_nodes(text: str) -> list[tuple[Collection, Collection | None, yaml.Node | None]]:
    """(node, parent, key) for each outermost non-empty flow collection, in file order.

    `key` is the mapping key the node is the value of; None for a sequence item or the document root.
    """
    found = []

    def walk(node, parent, key):
        if not isinstance(node, (yaml.MappingNode, yaml.SequenceNode)):
            return
        if node.flow_style and node.value:
            found.append((node, parent, key))
        elif isinstance(node, yaml.MappingNode):
            for k, v in node.value:
                walk(v, node, k)
        else:
            for item in node.value:
                walk(item, node, None)

    root = yaml.compose(text)
    if root is not None:
        walk(root, None, None)
    return found


def flow_spots(text: str) -> list[tuple[int, str]]:
    """(line, "mapping" or "sequence") for each flow collection a park file should not have."""
    return [
        (node.start_mark.line + 1, "mapping" if isinstance(node, yaml.MappingNode) else "sequence")
        for node, _, _ in flow_nodes(text)
    ]


def scalar_text(node: yaml.ScalarNode, text: str) -> str:
    """The scalar as written in the source, so quoting survives; a scalar spanning lines is re-quoted."""
    source = text[node.start_mark.index : node.end_mark.index]
    return json.dumps(node.value, ensure_ascii=False) if "\n" in source else source


def block_lines(node: yaml.Node, text: str) -> list[str]:
    """`node` as block-style lines at indent 0."""
    if isinstance(node, yaml.ScalarNode):
        return [scalar_text(node, text)]
    if not node.value:
        return ["{}" if isinstance(node, yaml.MappingNode) else "[]"]
    lines: list[str] = []
    if isinstance(node, yaml.MappingNode):
        for key, value in node.value:
            nested = block_lines(value, text)
            if isinstance(value, yaml.ScalarNode) or not value.value:
                lines.append(f"{scalar_text(key, text)}: {nested[0]}".rstrip())
            else:
                lines.append(f"{scalar_text(key, text)}:")
                lines += ["  " + line for line in nested]
    else:
        for item in node.value:
            nested = block_lines(item, text)
            lines.append(f"- {nested[0]}")
            lines += ["  " + line for line in nested[1:]]
    return lines


def scalars(node: yaml.Node):
    if isinstance(node, yaml.ScalarNode):
        yield node
    elif isinstance(node, yaml.MappingNode):
        for key, value in node.value:
            yield from scalars(key)
            yield from scalars(value)
    else:
        for item in node.value:
            yield from scalars(item)


def has_comment(node: Collection, text: str) -> bool:
    """A `#` outside every scalar of a flow collection is a comment, which block style would drop."""
    start = node.start_mark.index
    chars = list(text[start : node.end_mark.index])
    for scalar in scalars(node):
        for index in range(scalar.start_mark.index - start, scalar.end_mark.index - start):
            chars[index] = " "
    return "#" in chars


def to_block(text: str) -> str:
    """`text` with every flow collection rewritten as block style; ValueError when that is not safe."""
    result = text
    # Last first, so earlier offsets stay valid.
    for node, parent, key in reversed(flow_nodes(text)):
        if has_comment(node, text):
            raise ValueError(f"line {node.start_mark.line + 1}: a comment inside the flow collection would be lost")
        lines = block_lines(node, text)
        start, end = node.start_mark.index, node.end_mark.index
        if key is not None:
            # Under its key: drop the gap after `key:`, children one level deeper than the key.
            indent = " " * (key.start_mark.column + 2)
            start = len(text[:start].rstrip())
            replacement = "".join("\n" + indent + line for line in lines)
        elif parent is not None:
            # A list item: the first line follows the `- `, the rest line up under it.
            indent = " " * node.start_mark.column
            replacement = lines[0] + "".join("\n" + indent + line for line in lines[1:])
        else:
            replacement = "\n".join(lines)
        # ponytail: a trailing `# comment` after a flow collection ends up behind the last converted line.
        result = result[:start] + replacement + result[end:]
    if flow_nodes(result) or yaml.safe_load(result) != yaml.safe_load(text):
        raise ValueError("conversion did not reproduce the same data")
    return result


def main(argv: list[str]) -> int:
    check = "--check" in argv
    files = [Path(arg) for arg in argv if arg != "--check"] or sorted(PARKS_DIR.glob("*.yaml"))
    exit_code = 0
    for path in files:
        text = path.read_text(encoding="utf-8")
        try:
            converted = to_block(text)
        except (ValueError, yaml.YAMLError) as exc:
            print(f"❌ {path}: {exc}")
            exit_code = 1
            continue
        if converted == text:
            continue
        if check:
            print(f"❌ {path}: flow style on lines {', '.join(str(line) for line, _ in flow_spots(text))}")
            exit_code = 1
        else:
            path.write_text(converted, encoding="utf-8")
            print(f"✍️  {path}")
    return exit_code


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))
