from pathlib import Path

from comfy_bridge.application.workflow_patcher import WorkflowPatcher
from comfy_bridge.application.workflow_registry import WorkflowRegistry


def _registry() -> WorkflowRegistry:
    repo_root = Path(__file__).resolve().parents[3]
    return WorkflowRegistry(repo_root / "workflow-packs")


def test_minimax_disconnects_and_prunes_empty_reference_slots() -> None:
    registry = _registry()
    config = registry.get("minimax_h3_low")
    patcher = WorkflowPatcher()
    values = patcher.validate_values(
        config,
        {
            "reference1": "00000000-0000-0000-0000-000000000001",
            "prompt": "Picture 1 缓慢转头看向镜头。",
            "aspectRatio": "16:9 (Widescreen)",
            "megapixels": 2.0,
            "duration": 5.0,
        },
    )

    graph = patcher.patch(
        config,
        registry.load_graph(config.id),
        values,
        {"reference1": "mobile/reference-1.png"},
    )

    reference_inputs = graph["338"]["inputs"]
    assert reference_inputs["ref_images.ref_image_0"] == ["482", 0]
    assert not any(
        key in reference_inputs
        for key in (
            "ref_images.ref_image_1",
            "ref_images.ref_image_2",
            "ref_images.ref_image_3",
            "ref_images.ref_image_4",
            "ref_images.ref_image_5",
        )
    )
    assert graph["526"]["inputs"]["image"] == "mobile/reference-1.png"
    assert "521" in graph
    assert "555" not in graph
    assert "563" not in graph
    assert "527" not in graph
    assert "475" not in graph
    assert "469" not in graph


def test_z_image_patches_prompt_dimensions_and_random_seed() -> None:
    registry = _registry()
    config = registry.get("z_image_20260605")
    patcher = WorkflowPatcher()
    values = patcher.validate_values(
        config,
        {"prompt": "雨夜街道", "width": 768, "height": 1024},
    )

    graph = patcher.patch(config, registry.load_graph(config.id), values, {})

    assert graph["22"]["inputs"]["text"] == "雨夜街道"
    assert graph["7"]["inputs"]["width"] == 768
    assert graph["7"]["inputs"]["height"] == 1024
    assert isinstance(graph["18"]["inputs"]["seed"], int)


def test_minimax_second_pass_selects_the_refined_output_branch() -> None:
    registry = _registry()
    config = registry.get("minimax_h3_low")
    patcher = WorkflowPatcher()
    values = patcher.validate_values(
        config,
        {
            "reference1": "00000000-0000-0000-0000-000000000001",
            "prompt": "Picture 1 缓慢转头。",
            "aspectRatio": "16:9 (Widescreen)",
            "megapixels": 2.0,
            "duration": 5.0,
            "secondPass": True,
            "secondPassScale": 1.75,
        },
    )

    graph = patcher.patch(
        config,
        registry.load_graph(config.id),
        values,
        {"reference1": "mobile/reference-1.png"},
    )

    assert "521" not in graph
    assert "555" in graph
    assert "563" in graph
    assert graph["555"]["inputs"]["mode.scale"] == 1.75


def test_minimax_high_prunes_unused_assets_and_patches_both_conditioners() -> None:
    registry = _registry()
    config = registry.get("minimax_h3_high")
    patcher = WorkflowPatcher()
    values = patcher.validate_values(
        config,
        {
            "prompt": "夜景中的双人对白。",
            "taskType": "T2VA",
        },
    )

    graph = patcher.patch(config, registry.load_graph(config.id), values, {})

    for node_id in ("7", "14"):
        inputs = graph[node_id]["inputs"]
        assert inputs["task_type"] == "T2VA"
        assert not any(key.startswith("ref_images.") for key in inputs)
        assert not any(key.startswith("ref_audios.") for key in inputs)
    assert "238" not in graph
    assert "225" not in graph
