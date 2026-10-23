# CodexUsage

一个轻量的 macOS 菜单栏工具，用于查看 Codex 订阅额度的剩余百分比和重置时间。使用 Swift 与 AppKit 编写，无第三方依赖。

![菜单栏效果示意，百分比为演示数据](docs/menubar-preview.png)

菜单栏使用小机器人头像，后面依次显示第一组额度的 primary / secondary 剩余百分比。点击菜单可查看全部额度组、窗口长度、重置时间和最近成功更新时间。

## 功能

- 每 60 秒自动刷新，也支持手动刷新和唤醒后刷新。
- 根据服务端返回值展示额度窗口，不固定假设为五小时或一周。
- 读取失败时保留上次成功数据，并标记可能已过期。
- 自动查找 Codex CLI，也可手动选择可执行文件。
- 仅显示菜单栏图标，不占用 Dock。

## 环境要求

- macOS 13 或更高版本。
- 可用的 Codex CLI，且已使用 ChatGPT 账号登录。工具也会尝试使用 ChatGPT / Codex 桌面应用内置的 CLI。
- 构建需要 Xcode 15 或更高版本，或包含 Swift 5.9+ 的 Command Line Tools。

API Key 登录不保证能返回订阅额度。若菜单提示无法读取，请先在 Codex 中检查登录状态与网络，再手动刷新。

## 构建与运行

```bash
git clone https://github.com/huangyangme/CodexUsage.git
cd CodexUsage
./build.sh
open dist/CodexUsage.app
```

构建脚本生成 `dist/CodexUsage.app` 和 `dist/CodexUsage.zip`。可以将应用拖到“应用程序”，退出旧版本后再启动。当前只构建本机架构，不生成通用二进制。

也可以使用 Xcode 打开 `Package.swift`，选择 CodexUsage scheme 编译运行。菜单栏打包产物由 `Resources/Info.plist` 设置为后台应用，建议通过构建脚本生成日常使用的 `.app`。

目前使用本机临时签名，未做 Developer ID 签名或 Apple 公证。项目暂不提供自动更新或开机启动设置。

## 工作原理与隐私

通过官方 [Codex App Server](https://learn.chatgpt.com/docs/app-server) 的 stdio 协议执行 `initialize` → `initialized` → `account/rateLimits/read`，查询结束后关闭子进程。不会创建对话或启动模型任务。

认证由本机 Codex CLI 管理；本工具不直接读取、复制或记录登录令牌。用量查询由 CLI 连接 Codex 服务完成。本工具没有额外的遥测服务，只在本机偏好设置中保存手动选择的 CLI 路径。

这属于定时查询，不能保证秒级同步；数据和更新时间以 Codex 服务端为准。独立查询进程不会自动收到其他 Codex 进程的用量通知。接口或桌面应用内置 CLI 路径变化可能影响兼容性。

菜单中的重置时间使用 macOS 当前时区；缺失的数据不会被当作剩余 100%。预览图片中的百分比仅为演示数据。

## 项目结构

```text
Package.swift                 Swift Package / Xcode 入口
Sources/CodexUsage/main.swift  菜单栏界面、图标绘制与用量查询
Resources/Info.plist           macOS 应用配置
scripts/build-app.sh          编译、签名与打包
```

## 贡献与许可证

欢迎通过 Issue 报告问题或提交 Pull Request。请注明 macOS 和 Codex CLI 版本；提交日志前删除账号、令牌、私人路径等信息。

[MIT License](LICENSE)。本项目为独立社区工具，与 OpenAI 无隶属关系。小机器人图标由代码绘制，参考 Codex companion 的造型，并非官方图像资源；Codex 和 OpenAI 相关名称及商标归各自权利人所有。
