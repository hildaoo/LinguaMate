# 在 iPhone 上运行 LinguaMate

设备条件：用户提供 iPhone 17 / iOS 27.2，暂时没有 Mac。项目最低部署目标为 iOS 17；并不意味着已验证 iOS 27.2 或该设备。连接真机前需选用支持该系统的 Xcode / SDK。当前交付没有签名 IPA，也未上传 TestFlight。

## 当前可运行与已验证部分

- `Sources/LinguaMateCore`：跨平台 Swift 核心，包含独立语言空间、复习调度、判分、反馈记录、数据持久化与 HTTP 客户端。
- `server`：真实 FastAPI 服务，支持 OpenAI 兼容的文本模型接口；没有密钥时明确不可用。
- `ios/LinguaMate.xcodeproj`：已由 XcodeGen 2.44.1 实际生成，包含 SwiftUI App、资源和 UI 测试。当前 Linux 只做过语法解析，不能完成 SwiftUI 类型检查、SDK 编译或运行模拟器。
- 本地规则模式无需后端；这不是 AI。其固定追问和少量纠错只作练习，界面会持续标注。

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

当前环境的 GitHub API 请求返回 Forbidden，无法从这里查询/触发 Actions。Git 读取正常，不代表 Actions 权限或 macOS 额度已验证。环境网络配置需要允许 `api.github.com` 才能进一步排查 API；用户还需拥有相应仓库权限及可用 runner 额度。本次未推送分支、未触发 Actions。

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

这些真机与 UI 项目在当前 Linux 环境尚未执行；不得用核心单元测试替代它们。
