# 跨网络连接 Windows Agent

手机端已经支持以下 Agent 地址：

- 局域网：`http://192.168.1.20:8787`
- 公网 IP：`http(s)://公网地址:端口`
- FRP TCP 域名：`http://agent.example.com:18188`
- HTTPS 域名：`https://agent.example.com`

## 当前 FRP TCP 配置

FRP 的端口不是同一种用途：

- `7000` 是 `frpc` 登录 `frps` 的控制端口，手机不能填写这个端口。
- `8787` 是 Windows 电脑本机的 Agent 端口。
- `18188` 是服务器对公网开放的远程端口，手机在当前配置下应填写
  `http://你的域名:18188`。

`frpc.toml` 的代理必须指向 Agent，而不是 ComfyUI：

```toml
[[proxies]]
name = "windows-agent"
type = "tcp"
localIP = "127.0.0.1"
localPort = 8787
remotePort = 18188
```

使用顺序：双击项目根目录的 `start-agent.cmd`，在图形控制台中保存配置并点击
“一键启动 Bridge + FRP”，随后保持控制台运行。`start-frpc.cmd` 仍可作为单独启动
FRP 的备用入口。服务器防火墙或安全组需要允许 TCP `18188` 入站。域名只负责解析到
服务器 IP，不会自动把 80/443 转到 18188。
如果 DNS 使用了不支持任意 TCP 端口的代理/CDN，请先切换为“仅 DNS”。

直接使用 `http://域名:18188` 适合先验证连通性，但手机到服务器这一段没有 HTTPS
保护。长期使用时，建议在服务器上使用 Nginx/Caddy 把
`https://agent.example.com`（包括 WebSocket Upgrade）反向代理到
`http://127.0.0.1:18188`，手机再填写不带端口的 HTTPS 域名。

推荐使用反向隧道把域名的 HTTPS/WSS 流量转发到本机
`http://127.0.0.1:8787`。这种方式不需要把 8787 端口直接暴露在路由器上，
同一域名可以同时承载 Agent 的 HTTP API 和 WebSocket 实时通道。

## 推荐部署方式

1. 准备一个已接入 Cloudflare 的域名。
2. 在电脑上安装 `cloudflared`， 创建命名 Tunnel。
3. 建立公网主机名，例如 `agent.example.com`，源服务填写
   `http://127.0.0.1:8787`。
4. 把 Tunnel 注册为 Windows 服务，使它和 Agent 都能随电脑启动。
5. 在手机设置中填写 `https://agent.example.com` 和 Agent 的设备 Token。

不要直接把 ComfyUI 的 8188 端口发布到公网。Agent 的业务接口需要设备 Token，
但仍应只通过 HTTPS/WSS 传输；Token 泄露后应立即更换。Cloudflare Access 的网页登录
不能直接套在当前原生 App 前面；若要再加一层 Access，需要后续实现服务令牌头。

直接使用公网 IP 也可以，但需要路由器端口转发、防火墙规则、固定公网 IP 或动态 DNS，
以及有效 TLS 证书，维护成本和暴露风险都高于反向隧道。
