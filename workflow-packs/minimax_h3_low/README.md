# 【MINIMAX-H3】八月最强文戏-低配版

> 原工作流作者：Bilibili UP 主 **Work-Fisher**。  
> 来源：[MiniMax H3 文戏工作流分享](https://www.bilibili.com/video/BV1EytW6BEia/)

本目录包含两种格式：

- `workflow.ui.json`：已移除本机路径和预览记录的 ComfyUI 画布工作流，可直接导入 ComfyUI。
- `workflow.json`：供 Comfy Bridge Agent 调用的 API 格式工作流。

参考图编号映射：

- 1 → `526`
- 2 → `527`
- 3 → `525`
- 4 → `515`
- 5 → `475`
- 6 → `469`

参考音频 1–3 分别写入 `522`、`523`、`473`；未上传的图片或音频会从 `338` 的动态输入中移除。

提示词写入 `528.prompt`，比例/像素量写入 `456`，时长写入 `529.value`。关闭二次采样时读取 `521.gifs`；开启后执行原工作流的 `555 → 553 → 563` 细化分支并读取 `563.gifs`。

工作流版权归原作者所有，不自动适用本项目 MIT 许可证；详见 [第三方声明](../../THIRD_PARTY_NOTICES.md)。
