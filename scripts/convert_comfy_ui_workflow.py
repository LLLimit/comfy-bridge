from __future__ import annotations

import argparse
import json
import urllib.request
from pathlib import Path
from typing import Any


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Convert a ComfyUI UI workflow into a pruned API prompt graph."
    )
    parser.add_argument("source", type=Path)
    parser.add_argument("destination", type=Path)
    parser.add_argument("--output-node", action="append", required=True)
    parser.add_argument(
        "--set",
        action="append",
        default=[],
        metavar="NODE.INPUT=JSON",
        help="Replace one API input with a JSON value after conversion.",
    )
    parser.add_argument(
        "--object-info-url",
        default="http://127.0.0.1:8188/object_info",
    )
    parser.add_argument(
        "--activate-all-bypassed",
        action="store_true",
        help="Treat all mode=4 nodes as active before conversion.",
    )
    return parser.parse_args()


class WorkflowConverter:
    def __init__(self, workflow: dict[str, Any], object_info: dict[str, Any]) -> None:
        self.workflow = workflow
        self.object_info = object_info
        self.nodes = {str(node["id"]): node for node in workflow.get("nodes", [])}
        self.links = {str(link[0]): link for link in workflow.get("links", [])}
        self.setters: dict[str, dict[str, Any]] = {}
        for node in workflow.get("nodes", []):
            if node.get("type") != "SetNode":
                continue
            values = node.get("widgets_values") or []
            if values:
                self.setters[str(values[0])] = node

    def convert(self, output_nodes: list[str]) -> dict[str, Any]:
        converted: dict[str, Any] = {}
        for node_id, node in self.nodes.items():
            if node.get("mode", 0) != 0 or node.get("type") not in self.object_info:
                continue
            converted[node_id] = self._convert_node(node)

        keep: set[str] = set()

        def visit(node_id: str) -> None:
            if node_id in keep:
                return
            if node_id not in converted:
                raise ValueError(f"Output dependency {node_id} is not an active backend node")
            keep.add(node_id)
            for value in converted[node_id]["inputs"].values():
                if self._is_connection(value):
                    visit(str(value[0]))

        for output_node in output_nodes:
            visit(str(output_node))
        return {node_id: converted[node_id] for node_id in converted if node_id in keep}

    def _convert_node(self, node: dict[str, Any]) -> dict[str, Any]:
        node_type = str(node["type"])
        definition = self.object_info[node_type]
        valid_names, dynamic_prefixes, metadata = self._input_schema(definition)
        inputs: dict[str, Any] = {}
        widget_values = node.get("widgets_values")

        if isinstance(widget_values, dict):
            for name, value in widget_values.items():
                if name != "videopreview":
                    inputs[str(name)] = value

        list_values = widget_values if isinstance(widget_values, list) else []
        value_index = 0
        for ui_input in node.get("inputs") or []:
            name = str(ui_input.get("name") or "")
            widget = ui_input.get("widget")
            widget_value: Any = None
            has_widget_value = False
            if widget is not None and value_index < len(list_values):
                widget_value = list_values[value_index]
                value_index += 1
                has_widget_value = True
                input_meta = metadata.get(name, {})
                has_control = input_meta.get("control_after_generate")
                next_is_control = (
                    name in {"seed", "noise_seed"}
                    and value_index < len(list_values)
                    and list_values[value_index]
                    in {"fixed", "randomize", "increment", "decrement"}
                )
                if (has_control or next_is_control) and value_index < len(list_values):
                    value_index += 1

            is_backend_input = name in valid_names or any(
                name.startswith(f"{prefix}.") for prefix in dynamic_prefixes
            )
            if not is_backend_input:
                continue

            link_id = ui_input.get("link")
            if link_id is not None:
                connection = self._resolve_link(str(link_id), set())
                if connection is not None:
                    inputs[name] = connection
                    continue
            if has_widget_value:
                inputs[name] = widget_value

        title = node.get("title") or node_type
        return {
            "inputs": inputs,
            "class_type": node_type,
            "_meta": {"title": str(title)},
        }

    @staticmethod
    def _input_schema(
        definition: dict[str, Any],
    ) -> tuple[set[str], set[str], dict[str, dict[str, Any]]]:
        valid: set[str] = set()
        dynamic: set[str] = set()
        metadata: dict[str, dict[str, Any]] = {}
        groups = definition.get("input") or {}
        for group_name in ("required", "optional"):
            group = groups.get(group_name) or {}
            for name, spec in group.items():
                valid.add(str(name))
                if isinstance(spec, list) and len(spec) > 1 and isinstance(spec[1], dict):
                    metadata[str(name)] = spec[1]
                if (
                    isinstance(spec, list)
                    and spec
                    and isinstance(spec[0], str)
                    and spec[0] in {"COMFY_AUTOGROW_V3", "COMFY_DYNAMICCOMBO_V3"}
                ):
                    dynamic.add(str(name))
        return valid, dynamic, metadata

    def _resolve_link(
        self, link_id: str, seen: set[tuple[str, int]]
    ) -> list[Any] | None:
        link = self.links.get(link_id)
        if link is None:
            return None
        return self._resolve_source(str(link[1]), int(link[2]), seen)

    def _resolve_source(
        self, node_id: str, output_slot: int, seen: set[tuple[str, int]]
    ) -> list[Any] | None:
        marker = (node_id, output_slot)
        if marker in seen:
            raise ValueError(f"Cycle while resolving virtual node {node_id}")
        seen = {*seen, marker}
        node = self.nodes.get(node_id)
        if node is None:
            return None

        node_type = str(node.get("type") or "")
        if node_type == "GetNode":
            values = node.get("widgets_values") or []
            setter = self.setters.get(str(values[0])) if values else None
            return self._resolve_passthrough(setter, output_slot, seen)
        if node_type == "SetNode":
            return self._resolve_passthrough(node, output_slot, seen)
        if node.get("mode", 0) == 4:
            return self._resolve_passthrough(node, output_slot, seen)
        if node.get("mode", 0) != 0:
            return None
        if node_type not in self.object_info:
            return self._resolve_passthrough(node, output_slot, seen)
        return [node_id, output_slot]

    def _resolve_passthrough(
        self,
        node: dict[str, Any] | None,
        output_slot: int,
        seen: set[tuple[str, int]],
    ) -> list[Any] | None:
        if node is None:
            return None
        inputs = node.get("inputs") or []
        outputs = node.get("outputs") or []
        output_type = None
        if 0 <= output_slot < len(outputs):
            output_type = outputs[output_slot].get("type")

        candidates = [
            item
            for item in inputs
            if item.get("link") is not None
            and (output_type is None or item.get("type") == output_type)
        ]
        if not candidates:
            candidates = [item for item in inputs if item.get("link") is not None]
        if not candidates:
            return None
        candidate = candidates[min(output_slot, len(candidates) - 1)]
        return self._resolve_link(str(candidate["link"]), seen)

    @staticmethod
    def _is_connection(value: Any) -> bool:
        return (
            isinstance(value, list)
            and len(value) == 2
            and isinstance(value[0], (str, int))
            and isinstance(value[1], int)
        )


def apply_overrides(graph: dict[str, Any], raw_overrides: list[str]) -> None:
    for raw in raw_overrides:
        target, separator, encoded_value = raw.partition("=")
        if not separator or "." not in target:
            raise ValueError(f"Invalid --set value: {raw}")
        node_id, input_name = target.split(".", 1)
        if node_id not in graph:
            raise ValueError(f"Override references missing node {node_id}")
        graph[node_id]["inputs"][input_name] = json.loads(encoded_value)


def main() -> None:
    args = parse_args()
    workflow = json.loads(args.source.read_text(encoding="utf-8"))
    if not isinstance(workflow, dict) or "nodes" not in workflow:
        raise ValueError("Source is not a ComfyUI UI workflow")
    if args.activate_all_bypassed:
        for node in workflow.get("nodes", []):
            if node.get("mode") == 4:
                node["mode"] = 0
    with urllib.request.urlopen(args.object_info_url, timeout=60) as response:
        object_info = json.load(response)
    graph = WorkflowConverter(workflow, object_info).convert(args.output_node)
    apply_overrides(graph, args.set)
    args.destination.parent.mkdir(parents=True, exist_ok=True)
    args.destination.write_text(
        json.dumps(graph, ensure_ascii=False, indent=2) + "\n", encoding="utf-8"
    )
    print(f"Wrote {len(graph)} API nodes to {args.destination}")


if __name__ == "__main__":
    main()
