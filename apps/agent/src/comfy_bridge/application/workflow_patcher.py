from __future__ import annotations

import copy
import secrets
from typing import Any

from comfy_bridge.core.errors import AppError
from comfy_bridge.domain.models import InputDefinition, WorkflowConfig


class WorkflowPatcher:
    def validate_values(self, config: WorkflowConfig, values: dict[str, Any]) -> dict[str, Any]:
        definitions = {item.key: item for item in config.inputs}
        unknown = sorted(set(values) - set(definitions))
        if unknown:
            raise AppError("UNKNOWN_INPUT", f"包含不支持的参数：{', '.join(unknown)}")

        resolved: dict[str, Any] = {}
        for key, definition in definitions.items():
            value = values.get(key, definition.default)
            if definition.widget == "seed" and value is None:
                value = secrets.randbelow(2**63 - 1)
            if definition.required and self._is_empty(value):
                raise AppError("REQUIRED_INPUT", f"请填写“{definition.label}”。")
            if not self._is_empty(value):
                self._validate_type(definition, value)
                self._validate_constraints(definition, value)
                self._validate_option(definition, value)
            resolved[key] = value
        return resolved

    def patch(
        self,
        config: WorkflowConfig,
        graph: dict[str, Any],
        values: dict[str, Any],
        uploaded_names: dict[str, str],
    ) -> dict[str, Any]:
        patched = copy.deepcopy(graph)
        for definition in config.inputs:
            mapping = definition.mapping
            if mapping is None:
                continue
            value = values.get(definition.key)
            if mapping.strategy == "uploadedFile":
                if self._is_empty(value):
                    for target in mapping.remove_when_empty:
                        patched[target.node_id]["inputs"].pop(target.input_name, None)
                    continue
                try:
                    value = uploaded_names[definition.key]
                except KeyError as exc:
                    raise AppError("ASSET_UPLOAD_FAILED", "参考素材上传失败。", 502, True) from exc
            if mapping.strategy in {"direct", "uploadedFile"}:
                for target in mapping.targets:
                    patched[target.node_id]["inputs"][target.input_name] = value
            elif mapping.strategy == "lookup":
                try:
                    assignments = mapping.cases[str(value)]
                except KeyError as exc:
                    raise AppError("INVALID_OPTION", f"“{definition.label}”选项无效。") from exc
                for assignment in assignments:
                    patched[assignment.node_id]["inputs"][assignment.input_name] = assignment.value
        return self._prune_to_outputs(patched, config, values)

    @classmethod
    def _prune_to_outputs(
        cls,
        graph: dict[str, Any],
        config: WorkflowConfig,
        values: dict[str, Any],
    ) -> dict[str, Any]:
        keep: set[str] = set()

        def visit(node_id: str) -> None:
            if node_id in keep:
                return
            node = graph.get(node_id)
            if not isinstance(node, dict):
                raise AppError(
                    "WORKFLOW_INVALID",
                    f"工作流引用了不存在的节点 {node_id}。",
                    500,
                )
            keep.add(node_id)
            for value in (node.get("inputs") or {}).values():
                if cls._is_connection(value):
                    visit(str(value[0]))

        for output in config.outputs:
            if output.node_id and output.is_enabled(values):
                visit(output.node_id)
        return {node_id: node for node_id, node in graph.items() if node_id in keep}

    @staticmethod
    def _is_connection(value: Any) -> bool:
        return isinstance(value, list) and len(value) == 2 and isinstance(value[1], int)

    @staticmethod
    def _is_empty(value: Any) -> bool:
        return value is None or value == "" or value == []

    @staticmethod
    def _validate_type(definition: InputDefinition, value: Any) -> None:
        expected = definition.value_type
        valid = {
            "string": isinstance(value, str),
            "integer": isinstance(value, int) and not isinstance(value, bool),
            "number": isinstance(value, (int, float)) and not isinstance(value, bool),
            "boolean": isinstance(value, bool),
            "asset": isinstance(value, str),
            "assetList": isinstance(value, list) and all(isinstance(item, str) for item in value),
        }[expected]
        if not valid:
            raise AppError("INVALID_INPUT_TYPE", f"“{definition.label}”的值类型不正确。")

    @staticmethod
    def _validate_constraints(definition: InputDefinition, value: Any) -> None:
        rules = definition.constraints
        if isinstance(value, str) and "maxLength" in rules and len(value) > rules["maxLength"]:
            raise AppError("INPUT_TOO_LONG", f"“{definition.label}”内容过长。")
        if isinstance(value, (int, float)) and not isinstance(value, bool):
            if "min" in rules and value < rules["min"]:
                raise AppError("INPUT_TOO_SMALL", f"“{definition.label}”低于允许范围。")
            if "max" in rules and value > rules["max"]:
                raise AppError("INPUT_TOO_LARGE", f"“{definition.label}”超过允许范围。")

    @staticmethod
    def _validate_option(definition: InputDefinition, value: Any) -> None:
        if definition.options and value not in {option.value for option in definition.options}:
            raise AppError("INVALID_OPTION", f"“{definition.label}”选项无效。")
