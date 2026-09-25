# Workflow pack authoring

A workflow pack is a directory containing:

```text
workflow-packs/<workflow-id>/
  config.json
  workflow.api.json
  README.md
```

`workflow.api.json` must be the object accepted by ComfyUI's `/prompt`
endpoint. A normal UI workflow is intentionally rejected.

## Mapping strategies

- `direct`: write a validated scalar value to one or more node inputs.
- `uploadedFile`: upload an Agent asset to ComfyUI and write the filename
  returned by ComfyUI.
- `lookup`: map a user-facing option to a fixed, declarative set of node input
  values.

Executable expressions and arbitrary JSON paths are not supported.

The Agent returns a sanitized public manifest. Mapping and output extraction
node IDs never leave the Agent.

