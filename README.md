# LinguaMate AI

面向英语与韩语学习的原生 iPhone App。当前实现聚焦：独立学习空间 → 文字练习与纠错 → 词汇复习 → 专项判分 → 学习记录。

**状态：已实现首版客户端、核心与后端；核心/接口测试和真实 DeepSeek 英韩回复/纠错已通过。iOS 构建、真机安装尚待验证，不能视为已经发布的 App。**

可阅读 [真实 AI 对话 Demo](docs/demo-ai.md)：使用开发者编写的样例，实际调用 `deepseek-flash`，不是固定回复或 iPhone 运行截图。

## 功能范围

- 英语与韩语分别保存目标、计划、词汇、会话、错误和练习结果。
- 对话支持 DeepSeek API 后端与明确标注的本地规则模式；地址和模型可覆盖。没有服务配置时，不会把固定脚本冒充 AI。
- 词汇本支持新增、搜索、收藏和间隔复习；种子释义标记为原创教学示例。
- 4 组原创专项、12 道客观题：提交、自动判分、解析和记录；不是官方真题或完整模考。
- 本地数据使用版本化快照原子保存，可导出、清除与处理损坏文件。

## 项目入口

| 位置 | 内容 |
| --- | --- |
| `ios/LinguaMate.xcodeproj` | 可用 Xcode 打开的 App 工程，未在当前环境执行 iOS 编译 |
| `ios/project.yml` | XcodeGen 2.44.1 工程声明 |
| `ios/LinguaMate/` | SwiftUI 页面、AppStore 和 Keychain |
| `Sources/LinguaMateCore/` | 可在 Linux / macOS 测试的 Swift 核心 |
| `server/` | FastAPI 私人 AI 网关、独立教学提示词和供应商适配器 |
| `Tests/`、`server/tests/`、`ios/LinguaMateUITests/` | 核心、接口与 UI 测试 |

## 本地验证

```bash
uv sync --directory server --locked
uv run --directory server pytest -q
uv run --directory server ruff check app tests
```

Mac 使用 Xcode 自带 Swift。Linux x86_64 可以运行 `bash scripts/setup-swift-linux.sh` 安装签名校验过的 Swift 工具链，然后：

```bash
bash scripts/test-core.sh
bash scripts/test-contract.sh
```

单独执行 `test-core.sh` 时，HTTP 合约测试会明确跳过；`test-contract.sh` 启动隔离测试后端后执行全部核心与合约测试。测试后端不是实际 AI。

## 开始运行

- 原生 App：见 [iPhone / macOS / TestFlight 运行说明](docs/setup-ios.md)。你没有 Mac 时，可使用借用/租用 Mac 或 macOS CI；Linux 不能完成 iOS SDK 编译和签名。
- 真实 AI：见 [服务端配置](docs/setup-server.md)。需要模型 API 密钥、可达的 HTTPS 后端及个人短期访问令牌。不要把供应商密钥放入 iOS 或提交到 Git。
- 已实现与未验证事项：见 [实现状态](docs/implementation-status.md)。
- 产品规划：见 [第一阶段设计](docs/phase-1-product-and-architecture.md)。设计描述中的后续功能不代表已实现。

当前无语音、音素评分、完整官方模考或跨设备同步。练习正确率、规则反馈和 AI 建议均不等于官方考试成绩。
