# Z-image生图20260605

> 原工作流作者：Bilibili UP 主 **DragonBro**。

本目录包含两种格式：

- `workflow.ui.json`：已移除本机路径和预览记录的 ComfyUI 画布工作流，可直接导入 ComfyUI。
- `workflow.json`：供 Comfy Bridge Agent 调用的 API 格式工作流。

- 提示词写入节点 `22.text`。
- 宽高写入节点 `7.width` 和 `7.height`。
- 最终图片读取节点 `429` 的 `images` 历史字段。
- 模型、采样、放大与分块设置保持源工作流默认值。

工作流版权归原作者所有，不自动适用本项目 MIT 许可证；详见 [第三方声明](../../THIRD_PARTY_NOTICES.md)。如能提供原始发布页的固定链接，欢迎补充。
