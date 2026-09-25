from __future__ import annotations

import argparse
import json
from pathlib import Path
from typing import Any


def is_connection(value: Any) -> bool:
    return (
        isinstance(value, list)
        and len(value) == 2
        and isinstance(value[0], (str, int))
        and isinstance(value[1], int)
    )


def main() -> None:
    parser = argparse.ArgumentParser(description="Prune an API prompt to output ancestors.")
    parser.add_argument("workflow", type=Path)
    parser.add_argument("--output-node", action="append", required=True)
    args = parser.parse_args()

    graph = json.loads(args.workflow.read_text(encoding="utf-8"))
    keep: set[str] = set()

    def visit(node_id: str) -> None:
        if node_id in keep:
            return
        node = graph.get(node_id)
        if node is None:
            raise ValueError(f"Prompt references missing node {node_id}")
        keep.add(node_id)
        for value in node.get("inputs", {}).values():
            if is_connection(value):
                visit(str(value[0]))

    for output_node in args.output_node:
        visit(str(output_node))
    pruned = {node_id: node for node_id, node in graph.items() if node_id in keep}
    args.workflow.write_text(
        json.dumps(pruned, ensure_ascii=False, indent=2) + "\n", encoding="utf-8"
    )
    print(f"Kept {len(pruned)} API nodes in {args.workflow}")


if __name__ == "__main__":
    main()
