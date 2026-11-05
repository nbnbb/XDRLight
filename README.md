# XDRLight

macOS 菜单栏亮度工具：调节系统背光，并在系统允许时利用内置 XDR 屏幕的 HDR 余量增强桌面。

## 下载

[下载 1.5.3 测试版（macOS arm64 DMG）](https://github.com/nbnbb/XDRLight/releases/download/v1.5.3/XDRLight-1.5.3.dmg) · [发布页与源码包](https://github.com/nbnbb/XDRLight/releases/tag/v1.5.3) · [测试记录](VALIDATION.md)

## 支持范围

- macOS 13 或更新，Apple Silicon 14 / 16 英寸 Liquid Retina XDR MacBook Pro。
- 本次实际验证仅覆盖 M2 Max MacBook Pro；其他已列机型尚未逐台验证。新机型可能需要适配。
- 不支持外接显示器或没有内置 XDR 屏幕的 Mac。本机构建产物为 arm64。
- 百分比表示调节强度；没有用亮度计验证尼特值。持续模式仍受系统散热、供电与 HDR 余量限制。

## 使用

安装包内将 App 拖到 Applications。点击菜单栏棱镜，调节屏幕亮度与增强强度；打开顶部开关持续保持。设置 → 控制面板可打开独立窗口。关闭窗口继续后台运行，退出并恢复会还原背光与色彩。

整机热状态达到较高或严重时暂停；睡眠唤醒与降温后尝试恢复。电池温度不是屏幕温度。不要同时运行其他色彩或亮度增强工具。

## 与其他软件同时使用

开启前请退出 Vivid、BrightIntosh、Lunar、f.lux、BetterDisplay 等亮度或色彩工具。XDRLight 会保守拒绝已识别的同类程序及已有增强的色彩曲线；运行中检测到新的外部色彩曲线会暂停，并保留该外部调整。无法保证识别所有工具或运行模式。

保持模式会持续恢复面板目标背光；请使用 App 内滑块调节，或先关闭保持再用系统亮度键/自动亮度。HDR 视频可能截断高光，修图和校色时请关闭增强。

## 从源码构建

需要 Xcode Command Line Tools（`xcode-select --install`）和 Python 3。

```sh
./source/build.sh
open XDRLight.app
```

使用下载页中的 DMG 无需安装 Xcode 或编译。

仓库包含构建必需的 Sparkle 2.10.0 framework，保留其符号链接。部分 ZIP 解压工具会把框架符号链接变为普通文件；推荐 `git clone` 或 Release 提供的 source.tar.gz（用 `tar -xzf` 解压）。source.zip 已使用 macOS `unzip` 解压并构建验证。App 使用本地 ad hoc 签名，未完成 Apple Developer ID 签名和公证；首次打开可能需要在系统设置 → 隐私与安全性中允许。无需关闭 SIP 或全局安全保护。

```sh
./tests/run-integration.sh       # 会短暂改变本机亮度；测试后恢复
./build-release.command         # dist/ 中生成 App ZIP、DMG、完整源码 ZIP / tar.gz 和 SHA256SUMS
```

测试前退出正在运行的 XDRLight。诊断模式不保存亮度偏好；不要在测试中启动另一份 App。测试会检查 5 分钟连续增强、色彩重置恢复、背光/色彩恢复，以及模拟睡眠、过热保护与运行中渲染停滞。实际睡眠、长时间运行和其他机型需另外验证。

## 更新与隐私

当前未配置在线更新地址，不自动联网检查。后续配置 HTTPS feed 后由 Sparkle 验证 Ed25519 更新签名，并按配置每天自动检查。仓库中的公钥可公开；发布私钥由发布者自行保管，不包含在仓库中。当前未完成真实线上跨版本升级验收。

程序使用 DisplayServices 私有接口和只读 SMC 温度接口，可能随 macOS 更新失效。强制结束、系统崩溃时不保证清理成功；可运行恢复色彩.command 重置 ColorSync，背光用系统亮度键调整。

## 开源许可

GPL-3.0，见 [LICENSE](LICENSE)。技术来源与第三方许可见 [THIRD_PARTY.md](THIRD_PARTY.md)。当前版本保留 GPL 及技术来源标注。
