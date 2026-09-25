# Local development

## Windows Agent

From `apps/agent`:

```powershell
python -m venv .venv
.\.venv\Scripts\python.exe -m pip install -e ".[dev]"
.\.venv\Scripts\python.exe -m comfy_bridge
```

启动图形控制台：

```powershell
.\.venv\Scripts\python.exe -m comfy_bridge.gui
```

项目根目录的 `start-agent.cmd` 默认启动图形控制台；需要传统控制台模式时使用
`start-agent-cli.cmd`。

On first start the Agent generates a random device token in
`apps/agent/data/device-token.txt` and prints it once. Use that token in the
mobile Settings screen.

Configuration is read from environment variables:

- `COMFY_BRIDGE_HOST` (default `0.0.0.0`)
- `COMFY_BRIDGE_PORT` (default `8787`)
- `COMFY_BRIDGE_COMFY_URL` (default `http://127.0.0.1:8188`)
- `COMFY_BRIDGE_DATA_DIR`
- `COMFY_BRIDGE_WORKFLOW_DIR`
- `COMFY_BRIDGE_TOKEN`
- `COMFY_BRIDGE_DEBUG`

The built-in `demo_image` workflow has provider `mock`, so the first app flow
can be tested before ComfyUI is started.

## Flutter app

Install Flutter, the Android SDK, a compatible JDK, and ADB. From
`apps/mobile`:

```powershell
flutter pub get
flutter analyze
flutter test
flutter run
```

For an Android emulator use `http://10.0.2.2:8787`. For a physical phone use
the Windows computer's LAN address, for example `http://192.168.x.x:8787`.
Enter the generated Agent token in Settings.

Cleartext HTTP is allowed only for Phase 1 local development. A distributable
build must use HTTPS/WSS and certificate pinning.

## Real workflow import

Export a workflow from ComfyUI in API format. Do not use the normal UI-format
JSON containing top-level `nodes` and `links`.

Create `workflow-packs/<workflow-id>/workflow.api.json` and `config.json`. The
Agent validates every mapped node ID, input name, expected class type, and
workflow SHA-256 before exposing the workflow to the app.

