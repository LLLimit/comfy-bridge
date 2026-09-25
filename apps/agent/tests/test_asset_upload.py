from pathlib import Path

from fastapi.testclient import TestClient

from comfy_bridge.api.app import create_app
from comfy_bridge.core.settings import Settings


def test_wav_asset_is_saved_in_agent_asset_directory(tmp_path: Path) -> None:
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
    wav = b"RIFF" + (4).to_bytes(4, "little") + b"WAVE"

    with TestClient(create_app(settings)) as client:
        response = client.post(
            "/api/v1/assets",
            headers={"Authorization": "Bearer test-token"},
            files={"file": ("voice.wav", wav, "audio/wav")},
        )

    assert response.status_code == 201
    assert response.json()["mimeType"] == "audio/wav"
    assert len(list((tmp_path / "data" / "assets").glob("*.wav"))) == 1


def test_reencoded_picker_image_uses_detected_type(tmp_path: Path) -> None:
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
    jpeg = b"\xff\xd8\xff\xe0" + b"mobile-picker-reencoded"

    with TestClient(create_app(settings)) as client:
        response = client.post(
            "/api/v1/assets",
            headers={"Authorization": "Bearer test-token"},
            files={"file": ("scaled_reference.png", jpeg, "image/png")},
        )

    assert response.status_code == 201
    assert response.json()["mimeType"] == "image/jpeg"
    assert len(list((tmp_path / "data" / "assets").glob("*.jpg"))) == 1
