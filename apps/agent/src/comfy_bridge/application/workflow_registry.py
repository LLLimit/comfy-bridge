from __future__ import annotations

import hashlib
import json
from pathlib import Path
from typing import Any

from pydantic import ValidationError

from comfy_bridge.core.errors import AppError
from comfy_bridge.domain.models import BindingTarget, LookupAssignment, WorkflowConfig


class WorkflowRegistry:
    def __init__(self, root: Path) -> None:
        self._root = root
        self._configs: dict[str, WorkflowConfig] = {}
        self._pack_dirs: dict[str, Path] = {}
        self.reload()

    def reload(self) -> None:
        configs: dict[str, WorkflowConfig] = {}
        pack_dirs: dict[str, Path] = {}
        for config_file in sorted(self._root.glob("*/config.json")):
            try:
                raw = json.loads(config_file.read_text(encoding="utf-8"))
                config = WorkflowConfig.model_validate(raw)
                if config.id in configs:
                    raise ValueError(f"duplicate workflow id {config.id}")
                if config.provider == "comfyui":
                    self._validate_comfy_pack(config, config_file.parent)
                configs[config.id] = config
                pack_dirs[config.id] = config_file.parent
            except (OSError, ValueError, ValidationError, json.JSONDecodeError) as exc:
                raise RuntimeError(f"Invalid workflow pack at {config_file}: {exc}") from exc
        self._configs = configs
        self._pack_dirs = pack_dirs

    def list_public(self) -> list[dict[str, Any]]:
        return [config.public_manifest() for config in self._configs.values()]

    def get(self, workflow_id: str) -> WorkflowConfig:
        try:
            return self._configs[workflow_id]
        except KeyError as exc:
            raise AppError("WORKFLOW_NOT_FOUND", "找不到这个生成模式。", 404) from exc

    def load_graph(self, workflow_id: str) -> dict[str, Any]:
        config = self.get(workflow_id)
        if config.provider != "comfyui" or config.workflow is None:
            raise AppError("WORKFLOW_HAS_NO_GRAPH", "演示工作流不包含 ComfyUI 图。", 409)
        graph_file = self._safe_child(self._pack_dirs[workflow_id], config.workflow.file)
        graph = json.loads(graph_file.read_text(encoding="utf-8"))
        if not isinstance(graph, dict):
            raise AppError("WORKFLOW_INVALID", "工作流 API JSON 格式无效。", 500)
        return graph

    @staticmethod
    def _safe_child(pack_dir: Path, relative: str) -> Path:
        target = (pack_dir / relative).resolve()
        if pack_dir.resolve() not in target.parents:
            raise ValueError("workflow file escapes its pack directory")
        return target

    def _validate_comfy_pack(self, config: WorkflowConfig, pack_dir: Path) -> None:
        if config.workflow is None:
            raise ValueError("ComfyUI workflow requires a workflow file")
        graph_file = self._safe_child(pack_dir, config.workflow.file)
        raw_bytes = graph_file.read_bytes()
        graph = json.loads(raw_bytes)
        if "nodes" in graph and "links" in graph:
            raise ValueError("UI-format workflow rejected; export API format")
        if not isinstance(graph, dict) or not graph:
            raise ValueError("API workflow must be a non-empty object")
        if config.workflow.sha256:
            actual = hashlib.sha256(raw_bytes).hexdigest()
            if actual != config.workflow.sha256:
                raise ValueError("workflow SHA-256 does not match config")

        for item in config.inputs:
            mapping = item.mapping
            if mapping is None:
                raise ValueError(f"input {item.key} has no mapping")
            targets: list[BindingTarget | LookupAssignment] = list(mapping.targets)
            targets.extend(mapping.remove_when_empty)
            for assignments in mapping.cases.values():
                targets.extend(assignments)
            for target in targets:
                self._validate_target(graph, target)

        for output in config.outputs:
            if not output.node_id or not output.history_field:
                raise ValueError(f"output {output.key} needs nodeId and historyField")
            if output.node_id not in graph:
                raise ValueError(f"output {output.key} references missing node {output.node_id}")

    @staticmethod
    def _validate_target(graph: dict[str, Any], target: BindingTarget | LookupAssignment) -> None:
        node = graph.get(target.node_id)
        if not isinstance(node, dict):
            raise ValueError(f"mapping references missing node {target.node_id}")
        inputs = node.get("inputs")
        if not isinstance(inputs, dict) or target.input_name not in inputs:
            raise ValueError(
                f"mapping references missing input {target.node_id}.{target.input_name}"
            )
        if target.expected_class_type and node.get("class_type") != target.expected_class_type:
            raise ValueError(
                f"node {target.node_id} expected {target.expected_class_type}, "
                f"found {node.get('class_type')}"
            )
