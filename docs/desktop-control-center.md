# Windows 图形控制台

双击项目根目录的 `start-agent.cmd` 打开 Comfy Bridge 图形控制台。界面使用官方
PySide6 + Qt Quick/QML，并启用 Qt 的 FluentWinUI3 风格。界面支持矢量绘制、动画、
高分屏缩放和 Windows 11 风格控件，不使用 Tk/ttk 或 Electron。

PySide6 运行库安装在项目的 `apps/agent/.venv` 中，不写入 C 盘项目环境。Qt for
Python 社区版采用 LGPLv3/GPLv3 双重开源许可；发布二进制版本时应同时附带对应的
Qt/PySide6 许可证与第三方许可声明。

## 控制中心

- 实时显示 Bridge、ComfyUI、FRP 和公网入口状态。
- 点击仪表盘图标时，图标会旋转，四项服务同步进入“检查中”，完成后分别显示结果。
- 一键启动 Bridge + FRP，或分别启动其中一个。
- 一键停止由当前控制台启动的服务。
- 显示本机 Agent 地址、公网手机地址和 FRP 端口映射。
- 显示、复制或重新生成手机设备密钥。

退出控制台时，会先询问是否停止由控制台启动的服务。控制台不会结束在它打开前
已经由其他程序启动的进程。

## 配置

Bridge / ComfyUI 配置包括：

- Agent 监听地址和端口；
- ComfyUI API 地址；
- 数据目录、工作流目录；
- 可选的 ComfyUI 日志文件；
- 调试日志开关。

FRP 配置包括：

- 是否启用 FRP；
- `frpc.exe` 和 `frpc.toml` 路径；
- FRP 服务器地址、控制端口和验证 Token；
- 服务器公网端口；
- 手机使用的公网 IP/域名；
- TLS、隧道加密和压缩开关。

保存时会同步生成 `frpc.toml`，并保证公网端口转发到当前 Agent 端口。普通桌面配置
写入 `apps/agent/data/desktop-settings.json`；FRP Token 只保存在被 Git 忽略的
`frpc.toml` 中，不复制到桌面配置 JSON。

## 日志

日志页集中查看最近 500 行：

- ComfyUI 日志：优先读取用户指定文件；未指定时尝试读取 ComfyUI 日志接口；
- Bridge 服务日志：`apps/agent/data/agent.log`；
- FRP 日志：与 `frpc.toml` 位于同一目录的 `frpc.log`。

日志查看器不会清空或修改原始日志，并提供按钮直接打开 Bridge/FRP 日志目录。

## 命令行兼容

图形界面不是运行 Agent 的硬依赖。服务器或排错场景仍可使用：

```powershell
python -m comfy_bridge
```

或者双击根目录的 `start-agent-cli.cmd`。
