<p align="center"><img src="assets/branding/comfy-bridge-master.png" width="160" alt="Comfy Bridge logo"></p>
<h1 align="center">Comfy Bridge</h1>
<p align="center">用 Android 手机安全地控制本机 ComfyUI 工作流。<br>A secure Android-to-ComfyUI workflow bridge for your Windows PC.</p>
<p align="center">
  <img alt="License" src="https://img.shields.io/badge/license-MIT-22c55e">
  <img alt="Platform" src="https://img.shields.io/badge/platform-Android%20%7C%20Windows-2563eb">
  <img alt="Flutter" src="https://img.shields.io/badge/mobile-Flutter-02569B?logo=flutter&logoColor=white">
  <img alt="Python" src="https://img.shields.io/badge/agent-Python-3776AB?logo=python&logoColor=white">
</p>

Comfy Bridge 让手机只与运行在 Windows 上的本地 Agent 通信，再由 Agent 调用本机 ComfyUI。节点 ID、工作流 JSON 和电脑文件路径都不会暴露给手机端，复杂工作流会被转换成简单、适合移动设备的动态表单。

> [!IMPORTANT]
> 本项目目前面向开发者和愿意自行构建的用户。跨公网使用时，请务必通过 HTTPS/WSS 或可信 VPN 暴露 Agent，不要直接将未加密的本地端口开放到互联网。

## 功能亮点

- 手机端动态生成工作流表单，无需在 App 内硬编码 ComfyUI 节点
- 支持提示词、Seed、尺寸、参考图片、参考音频与视频工作流
- 实时任务状态与 WebSocket 事件推送
- 图片/视频作品预览、保存到手机相册及远程删除
- Windows 图形控制台统一管理 ComfyUI、Bridge 与可选 FRP 设置
- 设备 Token 认证；工作流映射和本机路径只保留在电脑端
- 自带 mock 演示工作流，可在不启动 ComfyUI 时验证完整链路

## 工作方式

```text
Android App  ── HTTP / WebSocket ──>  Windows Agent  ── ComfyUI API ──>  ComfyUI
     │                                      │
 动态表单、作品库                     工作流映射、鉴权、媒体存储
```

详细设计请参阅 [架构说明](docs/architecture.md) 与 [安全说明](docs/security.md)。

## 快速开始

### 1. 准备环境

- Windows 10/11
- 已安装并可以正常运行的 ComfyUI Desktop
- Python 3.12+
- Flutter SDK、Android SDK、兼容 JDK 与 ADB（仅构建 Android App 时需要）

### 2. 启动 Windows Agent

保持 ComfyUI Desktop 运行，然后双击仓库根目录的 `start-agent.cmd`。首次启动会把 Python 虚拟环境安装到 `apps/agent/.venv`，下载缓存保存在仓库内的 `.tooling`。

在图形控制台中配置 ComfyUI 地址并启动 Bridge，记下显示的访问地址与设备 Token。

### 3. 构建 Android App

```powershell
cd apps/mobile
flutter pub get
flutter test
flutter build apk
```

安装 APK 后，在 App 的“设置”中填写 Agent 地址和设备 Token。物理手机与电脑需位于同一局域网；Android 模拟器访问宿主机时可使用 `http://10.0.2.2:8787`。

更完整的环境配置、测试和运行方式见 [本地开发指南](docs/local-development.md)。

## 内置工作流包

| 工作流 | 能力 |
| --- | --- |
| `demo_image` | 无需 ComfyUI 的 mock 图片生成演示 |
| `z_image_20260605` | 文生图、宽高调整 |
| `minimax_h3_low` | 参考图、参考音频、画面比例、时长及二次采样 |
| `minimax_h3_high` | 双阶段高配音视频、首尾帧和多种生成模式 |

仓库中的真实工作流可能依赖你本机未安装的模型或自定义节点。请先在 ComfyUI 中确认对应工作流能够运行。

## 添加自己的工作流

ComfyUI Desktop 的画布 JSON 不能直接提交给 `/prompt` API。接入工作流时：

1. 从 ComfyUI 导出 API 格式工作流；
2. 使用 `scripts/convert_comfy_ui_workflow.py` 转换或清理现有 UI JSON；
3. 在 `workflow-packs/<workflow-id>/` 中放置工作流与 `config.json`；
4. 映射需要显示在手机端的提示词、媒体、Seed 和尺寸字段；
5. 重启 Agent，手机端即可自动加载新表单。

完整格式与校验规则见 [工作流编写指南](docs/workflow-authoring.md)。

## 仓库结构

```text
apps/agent/       Python Windows Agent、图形控制台与 API
apps/mobile/      Flutter Android App
contracts/        OpenAPI、WebSocket 事件与工作流 Schema
workflow-packs/   示例和真实工作流包
scripts/          安装、启动与工作流转换工具
docs/             架构、安全、远程访问与开发文档
assets/           品牌素材
```

## 安全与隐私

纯净源码不包含设备 Token、FRP 凭据、桌面配置、数据库、上传素材、生成作品、日志、Android 本地 SDK 路径、签名密钥、APK、虚拟环境或构建缓存。这些内容会在被 Git 忽略的目录中生成。

发布你自己的 Android 版本前，请修改通用包名 `io.comfybridge.mobile` 并配置正式签名。发现安全问题时，请不要创建公开 Issue，按照 [安全政策](SECURITY.md) 中的方式报告。

## 参与贡献

欢迎提交 Issue 和 Pull Request。开始之前请阅读 [贡献指南](CONTRIBUTING.md) 和 [行为准则](CODE_OF_CONDUCT.md)。

## 许可证

本项目采用 [MIT License](LICENSE)。
