# Windows + 普通 Apple 账号安装 LinguaMate

本压缩包中的 `LinguaMate-0.1.0-unsigned.ipa` 是由 macOS CI 编译的 arm64 iPhone 设备包。它尚未签名，需要你在自己的电脑上签名并安装；不能直接在 iPhone 点文件安装，也不是 TestFlight 或 App Store 版本。Apple 账号和凭据不需要交给开发者或 Codex。

## 1. 准备 Windows 电脑和 iPhone

1. 从 [Sideloadly 官网](https://sideloadly.io/) 下载 Windows 版。
2. 按其官网的安装要求准备 Apple 驱动和组件。当前官网要求使用网页安装版 iTunes 和 iCloud，并提供官方下载链接；安装前检查电脑已有版本，避免重复安装冲突。
3. 用数据线连接已解锁的 iPhone。在手机提示时选择“信任此电脑”，确认电脑能识别设备。

## 2. 签名并安装

1. 解压下载的 GitHub Artifact ZIP，取出 `.ipa` 文件。
2. 打开 Sideloadly，选中自己的 iPhone，将 `.ipa` 拖入窗口。
3. 输入自己的 Apple 账号并按软件提示完成登录和双重认证。密码和验证码只在你自己的安装工具中输入，不发聊天。
4. 如需自动续签，打开自动刷新选项，然后点击 Start 等待安装。
5. 如系统提示，前往 iPhone“设置 → 隐私与安全性 → 开发者模式”开启并按提示重启、确认。如果此入口尚未出现，先完成一次签名安装尝试，再返回查看。
6. 如提示开发者不受信任，在“设置 → 通用 → VPN 与设备管理”中找到自己账号对应的开发者并信任，然后打开 LinguaMate。

普通账号的免费签名有效期为 7 天。自动刷新需要电脑上的 Sideloadly Daemon 运行，且手机通过 USB 或已配置的 Wi-Fi 配对可被检测。更新或重新签名时使用相同 Apple 账号和 Bundle ID，覆盖安装，不要先卸载；本地学习记录可在 App“我的 → 导出本地学习数据”备份。详见 [Sideloadly FAQ](https://sideloadly.io/faq)。

## 3. 连接已部署的 AI

首次打开先完成学习偏好设置。底部“我的 → AI 服务”中：

- HTTPS 后端地址：`https://linguamate-api-t80d.onrender.com`
- 个人后端访问令牌：填写你自己在 Render `linguamate-api → Environment` 中保存的 `LINGUAMATE_CLIENT_TOKEN`，点击“保存访问令牌”。不是 DeepSeek 的 `LLM_API_KEY`。
- 开启“允许将会话文字发往 AI 服务”，将“新会话使用”切换到“云端 AI 教师”。
- 点击“检查后端连接”，再进入“对话”开启一轮新会话。

免费签名的 7 天有效期与后端令牌不同：当前个人后端令牌不需要定期续期。词汇和专项可以离线使用；免费 Render 实例唤醒时 AI 首次请求可能较慢。

## 当前验证边界

设备包由实际 Xcode iPhoneOS 构建产生，打包脚本检查平台、arm64 架构和 ZIP 完整性。模拟器学习流程已通过；用户设备的签名、安装、Keychain 保存、布局以及原生客户端到公网 AI 的完整体验，需要在安装后实际验证。

压缩包内含 `SHA256SUMS.txt` 和 `build-info.txt`，用于核对文件与源代码提交。包中不包含 Apple 凭据、DeepSeek 密钥或个人后端令牌。
