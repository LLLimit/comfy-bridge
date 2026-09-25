from pathlib import Path

from comfy_bridge.application.workflow_registry import WorkflowRegistry


def test_public_manifest_does_not_expose_private_mapping() -> None:
    repo_root = Path(__file__).resolve().parents[3]
    registry = WorkflowRegistry(repo_root / "workflow-packs")

    manifests = registry.list_public()

    assert manifests[0]["id"] == "demo_image"
    assert "provider" not in manifests[0]
    assert "workflow" not in manifests[0]
    assert all("mapping" not in item for item in manifests[0]["inputs"])
