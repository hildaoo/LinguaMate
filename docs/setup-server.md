# AI 后端配置与验证

本后端面向个人封闭试用，默认只监听回环地址。不提供账户系统或公开多用户服务。模型 API 密钥始终留在服务端；iOS 填写的是独立的短期后端访问令牌。

公网托管可使用 [Render 部署步骤](deploy-render.md)。仓库提供 Docker 镜像定义和 Blueprint 配置；本地开发的默认回环监听与容器内的 `0.0.0.0:$PORT` 监听分开配置。

## 安装和启动

需要 Python 3.12+ 与 uv。依赖版本和包哈希在 `server/uv.lock` 中锁定。

```bash
cd LinguaMate
uv sync --directory server --locked
uv run --directory server uvicorn app.main:app --host 127.0.0.1 --port 8000 --no-access-log
```

另一个终端检查：

```bash
curl --fail http://127.0.0.1:8000/health
```

未配置模型时返回 `status: ok, aiConfigured: false`，对话请求返回 503。进程启动与真实 AI 可用是两件事。此地址只用于内部验证，iPhone 无法通过它访问云环境。

## 启用真实 AI

当前选择 **DeepSeek API**，后端默认值是：

```dotenv
LLM_BASE_URL=https://api.deepseek.com/v1
LLM_MODEL=deepseek-flash
```

`deepseek-flash` 是本项目选用的对话模型别名，使用 Chat Completions + JSON object 输出。2026-10-28 已实际读取当前账户模型列表，返回 `deepseek-flash` 和 `deepseek-v4-pro`；同时核对了 [官方文档](https://api-docs.deepseek.com/) 和 [thinking 设置](https://api-docs.deepseek.com/guides/thinking_mode)。当前模型默认启用 thinking，后端对 DeepSeek 显式关闭它，以适配短对话、JSON 输出预算和交互超时；其他兼容供应商不接收该专用参数。

若环境仍保留之前的 `LLM_MODEL=deepseek-chat`，请在设置改成 `deepseek-flash` 后重启后端。本次真实联调通过进程变量显式选择了 `deepseek-flash`，没有把测试结果归因于旧模型。

在 [DeepSeek 开放平台](https://platform.deepseek.com/) 创建 API 密钥并确认 API 账户额度。将密钥安全配置为服务端 `LLM_API_KEY`，不填入 App、不发聊天。API 调用按平台规则计费，具体以账户和当前官方价格为准。

Codex 云环境已声明 `LLM_API_KEY` secret，代理目标仅为 `api.deepseek.com`；代理注入的值可能是占位符，应通过正常 HTTPS 请求使用，不能将它复制为部署到其他服务器的真实密钥。其他托管环境需要在其自己的秘密管理中配置实际密钥。

网络设置需允许 `api.deepseek.com`，核对文档还需 `api-docs.deepseek.com`。草稿中保留原有 `api.github.com`，不替换已有预设。保存草稿不会立即改变当前网络；在环境设置填写密钥、审阅并保存配置，再发布环境后重新检查。

在后端运行环境的安全设置中配置以下项目，或在本地创建被 Git 忽略的 `server/.env`（参考 `.env.example`，不要覆盖已有文件）：

| 配置 | 用途 |
| --- | --- |
| `LLM_BASE_URL` | 默认 `https://api.deepseek.com/v1`，需支持 `/chat/completions` 和 JSON object 输出 |
| `LLM_MODEL` | 默认 `deepseek-flash`；以账户实际可调用的模型为准 |
| `LLM_API_KEY` | DeepSeek API 密钥，只在服务端通过安全配置提供 |
| `LINGUAMATE_CLIENT_TOKEN` | 个人试用的独立随机访问令牌，至少 32 字符；不要复用供应商密钥 |
| `LINGUAMATE_TOKEN_EXPIRES_AT` | 令牌到期时间，带时区的 ISO-8601；设置时有效期最多 7 天，建议 24 小时 |
| `LINGUAMATE_DAILY_LIMIT` | 每日最大请求数，默认 200；回复和反馈分别计次 |

不要在聊天或终端日志中显示真实密钥。使用密码管理器生成个人访问令牌，通过安全渠道配置到服务器和 iOS Keychain。测试代码中的 `test-only-...` 字符串只属于隔离测试，不能用于部署。

后端通过 HTTPS 反向代理部署到 iPhone 能访问的域名，保持 TLS 校验；模型 API 也只接受 HTTPS，不跟随重定向携带密钥。在 App「我的」中填写后端地址和短期令牌，开启文字上传授权，选择「云端 AI 教师」，然后开启新会话。当前云开发环境不是已发布的生产后端。

实际供应商需要验证：模型权限、账单、JSON 输出、英韩内容、超时与网络目的地。接口适配完成不代表所有 OpenAI 兼容服务已经兼容。暂不支持 Responses-only API、流式输出、工具调用或音频。

## 个人试用的限制

- 使用单进程、单 worker。配额、请求去重和限流状态在内存中；多 worker 或进程重启会使计数不连续，不能作为生产计费控制。
- 成功结果最多保留 10 分钟且最多 128 项，用于相同请求 ID 的重试。没有持久化会话数据库，不记录正文访问日志；供应商保留策略需另行核实。
- 限制为每分钟 20 次与每日可配置额度；模型失败也计次。客户端不进行无限自动重试。
- 相同请求 ID 对应不同正文会返回 409，避免误把旧响应当成新响应；客户端保留待回复和待反馈的请求 ID。
- 当前个人令牌需手动更新；没有公开注册、自动刷新或跨设备撤销管理。对外发布前接入真正的用户认证、持久化配额与删除策略。
- 生产 HTTPS 代理也应设置正文大小和请求超时上限。不要开放测试 fixture 或把测试凭据部署到公网。

## 验证

```bash
uv run --directory server pytest -q
uv run --directory server ruff check app tests
bash scripts/test-contract.sh
```

最后一个命令启动独立的回环测试后端，验证真实 Swift URLSession 到 FastAPI 的请求、编码、重试和鉴权，再停止它。模型供应商在此测试中被明确替换为固定 fixture；它不验证真实模型能力或账单权限。

真实 AI 的英韩回复和结束反馈已于 2026-10-28 通过，示例见 [Demo 记录](demo-ai.md)。初次联调和教学反馈优化后各验证一次，每轮为两种语言各一条回复和一条反馈，共 8 次模型调用。测试输入是开发者编写的句子，未上传用户私密会话。当前尚未配置个人后端访问令牌和到期时间，因此原生客户端到已部署 HTTPS 后端的整条链路仍需验证；取消/重试已有本地测试，尚需真机检查。

DeepSeek 的请求参数、两种语言的回复/反馈解析、空输出及截断输出均由本地 HTTP transport 测试覆盖；这类测试不会访问或计费于 DeepSeek，不能代替真实模型验收。
