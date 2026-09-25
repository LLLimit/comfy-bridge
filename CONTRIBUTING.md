# 贡献指南

感谢你愿意改进 Comfy Bridge。小型修复可以直接提交 Pull Request；较大的功能或接口变更，建议先创建 Issue 说明使用场景与设计方向，避免重复工作。

## 开发准备

1. Fork 本仓库并从默认分支创建功能分支。
2. 按照 [本地开发指南](docs/local-development.md) 配置 Windows Agent 与 Flutter App。
3. 不要提交设备 Token、FRP 凭据、签名文件、生成媒体、虚拟环境或本机 SDK 路径。

## 提交前检查

```powershell
cd apps/agent
.\.venv\Scripts\python.exe -m ruff check .
.\.venv\Scripts\python.exe -m mypy src
.\.venv\Scripts\python.exe -m pytest

cd ..\mobile
flutter analyze
flutter test
```

如果变更涉及 UI，请在 Pull Request 中附上截图或录屏；如果变更工作流协议，请同步更新 `contracts/`、相关测试及文档。

## Pull Request 约定

- 一个 PR 聚焦一个主题，并清楚说明动机、实现和验证方式。
- 保持提交信息简洁，例如 `Add workflow import validation`。
- 新功能应包含测试；修复缺陷时尽量先添加能够复现问题的测试。
- 不要把大模型、生成媒体或构建产物提交到仓库。

提交贡献即表示你同意按照本项目的 MIT 许可证发布该贡献。
