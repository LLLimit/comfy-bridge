from __future__ import annotations

import time
from pathlib import Path
from uuid import uuid4

from fastapi.testclient import TestClient

from comfy_bridge.api.app import create_app
from comfy_bridge.core.settings import Settings


def _settings(tmp_path: Path) -> Settings:
    repo_root = Path(__file__).resolve().parents[3]
    return Settings(
        host="127.0.0.1",
        port=8787,
        comfy_url="http://127.0.0.1:9",
        data_dir=tmp_path / "data",
        workflow_dir=repo_root / "workflow-packs",
        configured_token="test-token",
        debug=True,
    )


def test_mock_task_runs_to_completion(tmp_path: Path) -> None:
    app = create_app(_settings(tmp_path))
    headers = {"Authorization": "Bearer test-token"}
    with TestClient(app) as client:
        workflow_response = client.get("/api/v1/workflows", headers=headers)
        assert workflow_response.status_code == 200
        workflow = workflow_response.json()["items"][0]

        response = client.post(
            "/api/v1/tasks",
            headers=headers,
            json={
                "clientRequestId": str(uuid4()),
                "workflowId": workflow["id"],
                "workflowRevision": workflow["revision"],
                "inputs": {
                    "prompt": "test prompt",
                    "style": "cinematic",
                    "width": 256,
                    "height": 256,
                },
            },
        )
        assert response.status_code == 202
        task_id = response.json()["id"]

        completed = None
        for _ in range(80):
            snapshot = client.get(f"/api/v1/tasks/{task_id}", headers=headers).json()
            if snapshot["status"] in {"completed", "failed"}:
                completed = snapshot
                break
            time.sleep(0.05)

        assert completed is not None
        assert completed["status"] == "completed"
        assert completed["progress"]["percent"] == 100
        assert len(completed["outputs"]) == 1

        media = client.get(completed["outputs"][0]["url"], headers=headers)
        assert media.status_code == 200
        assert media.content.startswith(b"\x89PNG\r\n\x1a\n")

        media_url = completed["outputs"][0]["url"]
        deleted = client.delete(media_url, headers=headers)
        assert deleted.status_code == 204
        assert client.get(media_url, headers=headers).status_code == 404
        refreshed = client.get(f"/api/v1/tasks/{task_id}", headers=headers).json()
        assert refreshed["outputs"] == []
        deleted_task = client.delete(f"/api/v1/tasks/{task_id}", headers=headers)
        assert deleted_task.status_code == 204
        assert client.get(f"/api/v1/tasks/{task_id}", headers=headers).status_code == 404


def test_authentication_is_required(tmp_path: Path) -> None:
    app = create_app(_settings(tmp_path))
    with TestClient(app) as client:
        assert client.get("/health").status_code == 200
        assert client.get("/api/v1/workflows").status_code == 401


def test_agent_logs_are_token_protected_and_tailed(tmp_path: Path) -> None:
    settings = _settings(tmp_path)
    settings.ensure_directories()
    (settings.data_dir / "agent.log").write_text(
        "first line\nsecond line\nthird line\n", encoding="utf-8"
    )
    app = create_app(settings)
    headers = {"Authorization": "Bearer test-token"}

    with TestClient(app) as client:
        assert client.get("/api/v1/logs").status_code == 401
        response = client.get("/api/v1/logs?limit=2", headers=headers)

    assert response.status_code == 200
    assert response.json() == {"items": ["second line", "third line"]}
