from __future__ import annotations

from pathlib import Path
from uuid import uuid4

from fastapi.testclient import TestClient

from comfy_bridge.api.app import create_app
from comfy_bridge.core.settings import Settings


def test_websocket_streams_task_updates(tmp_path: Path) -> None:
    repo_root = Path(__file__).resolve().parents[3]
    settings = Settings(
        host="127.0.0.1",
        port=8787,
        comfy_url="http://127.0.0.1:9",
        data_dir=tmp_path / "data",
        workflow_dir=repo_root / "workflow-packs",
        configured_token="test-token",
        debug=True,
    )
    app = create_app(settings)
    headers = {"Authorization": "Bearer test-token"}

    with TestClient(app) as client:
        with client.websocket_connect("/api/v1/events?token=test-token") as socket:
            snapshot = socket.receive_json()
            assert snapshot["type"] == "agent.snapshot"

            response = client.post(
                "/api/v1/tasks",
                headers=headers,
                json={
                    "clientRequestId": str(uuid4()),
                    "workflowId": "demo_image",
                    "workflowRevision": 1,
                    "inputs": {
                        "prompt": "websocket test",
                        "style": "photo",
                        "width": 256,
                        "height": 256,
                    },
                },
            )
            task_id = response.json()["id"]

            seen_types: list[str] = []
            while "task.completed" not in seen_types:
                event = socket.receive_json()
                if event.get("taskId") == task_id:
                    seen_types.append(event["type"])

            assert "task.created" in seen_types
            assert "task.updated" in seen_types
            assert seen_types[-1] == "task.completed"
