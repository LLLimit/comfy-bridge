from __future__ import annotations

from datetime import UTC, datetime
from enum import StrEnum
from typing import Any, Literal
from uuid import UUID, uuid4

from pydantic import BaseModel, ConfigDict, Field
from pydantic.alias_generators import to_camel


class ApiModel(BaseModel):
    model_config = ConfigDict(
        alias_generator=to_camel,
        populate_by_name=True,
        serialize_by_alias=True,
        extra="forbid",
    )


class TaskStatus(StrEnum):
    PENDING = "pending"
    UPLOADING = "uploading"
    QUEUED = "queued"
    RUNNING = "running"
    PROCESSING = "processing"
    COMPLETED = "completed"
    FAILED = "failed"
    CANCELLED = "cancelled"


class TaskProgress(ApiModel):
    stage: str
    value: int | None = None
    maximum: int | None = None
    percent: float | None = Field(default=None, ge=0, le=100)
    indeterminate: bool = False


class TaskOutput(ApiModel):
    id: UUID = Field(default_factory=uuid4)
    key: str
    media_type: Literal["image", "video"]
    mime_type: str
    file_name: str
    url: str
    thumbnail_url: str | None = None


class TaskError(ApiModel):
    code: str
    message: str
    retryable: bool = False
    debug_id: str | None = None


class TaskSnapshot(ApiModel):
    id: UUID = Field(default_factory=uuid4)
    client_request_id: UUID
    workflow_id: str
    workflow_revision: int
    workflow_name: str
    category: Literal["image", "video"]
    prompt_id: str | None = None
    status: TaskStatus = TaskStatus.PENDING
    progress: TaskProgress = Field(
        default_factory=lambda: TaskProgress(stage="等待提交", indeterminate=True)
    )
    created_at: datetime = Field(default_factory=lambda: datetime.now(UTC))
    updated_at: datetime = Field(default_factory=lambda: datetime.now(UTC))
    completed_at: datetime | None = None
    inputs: dict[str, Any]
    outputs: list[TaskOutput] = Field(default_factory=list)
    error: TaskError | None = None


class CreateTaskRequest(ApiModel):
    client_request_id: UUID
    workflow_id: str
    workflow_revision: int
    inputs: dict[str, Any]


class AssetResponse(ApiModel):
    id: UUID
    file_name: str
    mime_type: str
    size: int


class InputOption(ApiModel):
    value: str | int | float | bool
    label: str


class BindingTarget(ApiModel):
    node_id: str
    input_name: str
    expected_class_type: str | None = None


class LookupAssignment(ApiModel):
    node_id: str
    input_name: str
    value: Any
    expected_class_type: str | None = None


class MappingDefinition(ApiModel):
    strategy: Literal["direct", "uploadedFile", "lookup"]
    targets: list[BindingTarget] = Field(default_factory=list)
    cases: dict[str, list[LookupAssignment]] = Field(default_factory=dict)
    remove_when_empty: list[BindingTarget] = Field(default_factory=list)


class InputDefinition(ApiModel):
    key: str
    label: str
    description: str | None = None
    value_type: Literal["string", "integer", "number", "boolean", "asset", "assetList"]
    widget: Literal[
        "text",
        "textarea",
        "number",
        "slider",
        "switch",
        "select",
        "chips",
        "seed",
        "imagePicker",
        "audioPicker",
    ]
    required: bool = False
    advanced: bool = False
    default: Any = None
    options: list[InputOption] = Field(default_factory=list)
    constraints: dict[str, Any] = Field(default_factory=dict)
    mapping: MappingDefinition | None = None


class OutputCondition(ApiModel):
    input: str
    equals: Any


class OutputDefinition(ApiModel):
    key: str
    label: str
    media_type: Literal["image", "video"]
    node_id: str | None = None
    history_field: str | None = None
    when: OutputCondition | None = None

    def is_enabled(self, values: dict[str, Any]) -> bool:
        return self.when is None or values.get(self.when.input) == self.when.equals


class StageDefinition(ApiModel):
    node_id: str
    label: str


class WorkflowFile(ApiModel):
    file: str
    sha256: str | None = None


class WorkflowPresentation(ApiModel):
    submit_label: str
    icon: str = "auto_awesome"


class WorkflowConfig(ApiModel):
    schema_version: Literal[1]
    id: str
    revision: int = Field(ge=1)
    name: str
    description: str = ""
    category: Literal["image", "video"]
    provider: Literal["mock", "comfyui"]
    workflow: WorkflowFile | None = None
    presentation: WorkflowPresentation
    inputs: list[InputDefinition]
    outputs: list[OutputDefinition]
    stages: list[StageDefinition] = Field(default_factory=list)

    def public_manifest(self) -> dict[str, Any]:
        inputs = [item.model_dump(by_alias=True, exclude={"mapping"}) for item in self.inputs]
        return {
            "schemaVersion": self.schema_version,
            "id": self.id,
            "revision": self.revision,
            "name": self.name,
            "description": self.description,
            "category": self.category,
            "presentation": self.presentation.model_dump(by_alias=True),
            "inputs": inputs,
            "outputTypes": sorted({output.media_type for output in self.outputs}),
        }


class AgentEvent(ApiModel):
    schema_version: Literal[1] = 1
    event_id: UUID = Field(default_factory=uuid4)
    sequence: int
    type: Literal[
        "agent.snapshot",
        "task.created",
        "task.updated",
        "task.completed",
        "task.failed",
        "task.deleted",
    ]
    task_id: UUID | None = None
    occurred_at: datetime = Field(default_factory=lambda: datetime.now(UTC))
    payload: dict[str, Any]
