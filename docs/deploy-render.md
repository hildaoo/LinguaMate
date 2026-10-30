# 将私人 AI 后端部署到 Render

本步骤发布供原生 App 调用的 HTTPS API，不会生成可安装的 iPhone App 或网页学习界面。iPhone 安装仍需要 Apple 签名 / TestFlight。

## 从手机完成首次部署

1. 注册或登录 [Render](https://dashboard.render.com/)，连接有权访问 `hildaoo/LinguaMate` 的 GitHub 账号。
2. 在 Render 新建 **Blueprint**，选择该仓库及 **`codex/linguamate-mvp` 分支**，配置文件为仓库根目录的 `render.yaml`。当前 `main` 尚未合并 MVP，不要选错分支。
3. 确认只创建一个名为 `linguamate-api` 的 Web Service，方案为 **Free**。配置禁用自动部署，避免开发分支的每次提交自动改变正在使用的服务。若平台不提供 Free 或要求升级付费，先停下并核对账户实际条款。
4. 在 Render 的安全环境变量表单填入：

   | 名称 | 填写内容 |
   | --- | --- |
   | `LLM_API_KEY` | 你在 DeepSeek 开放平台创建的真实 API 密钥。只填 Render 环境变量，不发聊天，不提交到 Git。 |

   `LINGUAMATE_CLIENT_TOKEN` 由 Render 自动生成，一次配置后持续有效，不需要到期时间或定期续期；模型地址、`deepseek-flash` 和每日 200 次限制已在配置中设置。不要把 DeepSeek 密钥当成 App 的访问令牌。

5. 创建服务并等待部署完成。复制 Render 实际分配的 `https://…onrender.com` 地址；不要自行猜域名。在浏览器打开该地址加 `/health`，应看到 `"status":"ok"`、`"aiConfigured":true`。这只检查配置是否就绪，仍需要一次实际模型请求验收。
6. 在 Render 的 Environment 页面查看自动生成的 `LINGUAMATE_CLIENT_TOKEN`，保存到自己的密码管理器。App 可安装后，在「我的」填写后端 HTTPS 地址与这个令牌，开启文字上传授权，再选择「云端 AI 教师」。

没有 Mac 不影响以上后端部署步骤。将**公开服务地址**发回即可继续检查；不要发送任何密钥或令牌。

Render 免费实例可能休眠，唤醒时首次访问较慢；先访问 `/health` 等待就绪，再从 App 发送对话。免费额度、可用区域及账单条件以 Render 当前控制台为准。DeepSeek 模型调用仍按其 API 账户计费。

## 已部署服务升级与令牌更新

已有服务在 Render 顶部选择 **Manual Deploy → Deploy latest commit**，等待部署完成后使用新行为。保留原有 `LINGUAMATE_CLIENT_TOKEN` 和 `LLM_API_KEY` 即可；不需要重新生成令牌或同步 Blueprint。旧的 `LINGUAMATE_TOKEN_EXPIRES_AT` 已不再读取，即使为空或已经到期也不会阻止新版本运行，可保留或删除。

个人令牌持续有效，重新部署或重启不会自动轮换它。需要撤销访问时，在 Render 中更换随机访问令牌，保存并重新部署，然后在 App 更新令牌；旧令牌不再被接受。未配置或不足 32 字符的令牌仍会阻止 AI 接口运行，未携带正确令牌的请求仍返回 401。

`/health` 在模型密钥或个人令牌缺失时仍返回 HTTP 200、`aiConfigured: false`，方便区分进程健康与 AI 配置是否可用。平台显示 Live 不等于真实 AI 验收通过。

## 开发者验证

镜像使用锁定的 Python 依赖、非 root 用户和单 worker。构建上下文白名单只包含运行必需文件，不会打包 `.env`、开发缓存和测试 fixture。

```bash
docker build -t linguamate-api ./server
docker run --rm -p 127.0.0.1:8000:8000 linguamate-api
```

未配置密钥时只用于内部启动检查：`/health` 的 `aiConfigured` 为 false，对话接口返回 503。真实部署由 Render 配置环境变量并终止 HTTPS。不要把本地回环地址当作手机访问地址。

在实际公网服务创建后，从仓库根目录运行：

```bash
uv run --directory server python scripts/check_deployment.py https://实际服务域名
uv run --directory server python scripts/check_deployment.py https://实际服务域名 --live
```

第一条验证 HTTPS、配置就绪及未鉴权请求被拒绝；第二条从隐藏输入提示读取私人访问令牌，使用人工样例执行英韩回复与反馈，共 4 次计费调用。也可通过安全的 `LINGUAMATE_CLIENT_TOKEN` 运行时变量提供令牌。检查程序不打印密钥、响应正文或错误正文，不跟随重定向，保持 TLS 验证。供应商密钥不需要交给检查程序。

当前 Codex 云环境的代理密钥只能用于已绑定目的地 `api.deepseek.com`，不能当作真实值复制到 Render。自动操作 Render 也需要独立的账号授权；GitHub 仓库访问权并不等于 Render 部署权。

参考：[Render Blueprint](https://render.com/docs/blueprint-spec)、[免费服务说明](https://render.com/docs/free)。
