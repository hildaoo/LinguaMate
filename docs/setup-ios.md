# 在 iPhone 上运行 LinguaMate

设备条件：用户提供 iPhone 17 / iOS 27.2，暂时没有 Mac。项目最低部署目标为 iOS 17；并不意味着已验证 iOS 27.2 或该设备。连接真机前需选用支持该系统的 Xcode / SDK。当前交付没有签名 IPA，也未上传 TestFlight。

## 当前可运行与已验证部分

- `Sources/LinguaMateCore`：跨平台 Swift 核心，包含独立语言空间、复习调度、判分、反馈记录、数据持久化与 HTTP 客户端。
- `server`：真实 FastAPI 服务，支持 OpenAI 兼容的文本模型接口；没有密钥时明确不可用。
- `ios/LinguaMate.xcodeproj`：已由 XcodeGen 2.44.1 实际生成，包含 SwiftUI App、资源和 UI 测试。Linux 不能执行 iOS SDK 编译，但已通过 GitHub 的 macOS runner 实际完成模拟器构建和学习流程 UI 测试。
- 本地规则模式无需后端；这不是 AI。其固定追问和少量纠错只作练习，界面会持续标注。

## 路径零：Windows + 普通 Apple 账号免费自用

macOS CI 在模拟器测试后执行 `scripts/build-ios-ipa.sh`，编译真正的 iPhoneOS / arm64 Release 包，并将待签名的 `.ipa`、安装说明、SHA-256 和构建信息上传为 `LinguaMate-unsigned-ipa` 附件。无需在 GitHub 配置 Apple 凭据。用户在自己的 Windows 电脑使用自己的账号签名安装，见 [逐步安装说明](install-windows.md)。普通账号签名有 7 天有效期，可通过安装工具在电脑可连接手机时自动刷新；这与后端令牌的长期有效无关。

此方式使用第三方安装工具，不属于 TestFlight 或 App Store 分发。CI 打包成功后还需用户在自己的手机完成签名安装和真机验收。

## 路径一：借用 / 租用 Mac

1. 在 Mac 上安装支持目标设备系统的 Xcode；完成 Xcode 首次启动和 iOS 平台组件安装。
2. 获取完整仓库，直接打开 `ios/LinguaMate.xcodeproj`。无需安装后端就能使用本地模式。
3. 选择 `LinguaMate` scheme 和一个可用的 iPhone 模拟器，执行 Build / Run；先运行 `LinguaMateUITests`。
4. 真机运行时，在 App target 的 Signing & Capabilities 中选择自己的 Team，并将 `app.linguamate.personal` 改成团队内唯一的 Bundle Identifier。若再次生成项目，需将相同选择写入 `ios/project.yml` 或本地签名配置。
5. 用 Xcode 支持的设备连接方式安装；按系统要求开启 Developer Mode 并信任开发者。远程租用的 Mac 不一定支持直连本地 iPhone，优先通过 TestFlight 分发。

需要重新生成工程时，在已安装 XcodeGen 2.44.1 的 Mac 上运行：

```bash
cd LinguaMate
xcodegen generate --spec ios/project.yml
xcodebuild -list -project ios/LinguaMate.xcodeproj
```

`project.yml` 是工程结构的维护入口。工程包一并保存在仓库中，避免首次打开依赖工程生成工具。

## 路径二：macOS CI + TestFlight

仓库包含 `.github/workflows/checks.yml`。提交到 GitHub 后，PR / main push 可触发；也支持手动运行。macOS job 会生成工程、选择已安装的 iPhone 模拟器，然后执行构建和完整本地学习流程的 UI 测试；失败时保留 `.xcresult`。

GitHub 网络权限恢复后，代码已推送到 `codex/linguamate-mvp` 并创建 [草稿 PR #1](https://github.com/hildaoo/LinguaMate/pull/1)。[首次完整 CI](https://github.com/hildaoo/LinguaMate/actions/runs/40691035492) 在提交 `8815fd9` 上通过了 backend-and-core 与 ios 两个 job，包括原生构建和 UI 测试。后续修改以各自提交的检查为准。

该运行的附件 `ios-demo-screenshots` 包含真实模拟器截图（约 2 MB），`ios-test-results` 包含 `.xcresult`。当前执行环境下载附件的存储域名 `productionresultssa16.blob.core.windows.net` 仍被网络策略拦截，可先在 GitHub 的运行页面下载。截图来自原生测试中的本地学习流程，不能作为真机或原生端云 AI 全链路的完成证明。

CI 的模拟器构建关闭签名，**生成的测试产物不能直接安装到 iPhone**。TestFlight 还需要：

1. Apple Developer Program 与 App Store Connect 中的 App 记录。
2. 唯一 Bundle ID、签名身份和 provisioning profile，或受控的自动签名流程。
3. 在 macOS 执行面向真机的 Archive、校验和上传。
4. 配置测试人员，在 iPhone 的 TestFlight 接收版本。

证书、私钥、App Store Connect 凭据只通过安全设置提供，不提交 Git、不发聊天。当前未添加带生产凭据的自动上传工作流；首次构建通过后再配置签名与分发。

## 真机验收清单

- 首次引导创建英韩空间；切换语言时词汇、会话、计划与统计隔离。
- 本地对话输入 `I am agree`，结束后看到 `I agree` 与说明；韩语可用 `친구을 만나요` 检查助词规则。
- 新增词条、收藏、显示释义、选择记忆结果，退出并重开验证保存。
- 完成三词复习、一轮对话反馈、一组专项，今日任务自动完成；不能通过重复提交增加成绩。
- 专项答案在离开页面和重启后恢复；提交后能看到原文、正确答案与干扰项解释。
- 云端配置失败、断网和取消请求后，消息仍保留且可重试；不会静默切为假 AI。
- 英韩纠错本和学习记录显示来源；首次启动不出现虚构成绩。
- 清除会话或删除全部数据后，相应记录与派生统计清除。
- 大字号、VoiceOver、浅色/深色、键盘遮挡和 iPhone 安全区域均需实机检查。

自动化已在 macOS 模拟器覆盖引导、对话结束反馈、词汇复习、专项判分、重启持久化和语言隔离。上面的真机、云端连接、权限、删除、VoiceOver 和大字号等其余项目仍需分别验收，不能用一次 UI 测试代替全部检查。
