# Changelog

本项目遵循 [Keep a Changelog](https://keepachangelog.com/zh-CN/1.1.0/)，并采用 [Semantic Versioning](https://semver.org/lang/zh-CN/)。

## [Unreleased]

### Added
- 支持通过 Tailcat 只读分享文件，并在连接设备上选择和接收文件。
- 显示文件传输总进度与当前文件进度。
- 增加桌面窗口尺寸下的响应式布局检查。
- 增加 Windows 构建脚本 `scripts/build-desktop.ps1`。

### Changed
- 优化文件分享表单、文件清单和连接卡布局。
- macOS 窗口最小内容尺寸设为 720 × 600 logical pixels。
- Android 构建会检查目标 ABI 对应的原生核心是否可用。
