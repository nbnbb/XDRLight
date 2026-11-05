# 代码来源与宣传边界

核对日期：2026-11-05。本项目不是所有代码和算法都独立原创，也不使用“100% 自研亮度引擎”的表述。

## 来源

| 部分 | 来源与核对结果 |
| --- | --- |
| HDR 触发与 gamma 桌面增强 | 参考并以 Objective-C 实现 BrightIntosh 的技术路线：微小 HDR 窗口触发 EDR，再调整显示色彩表。不是独立发明。 |
| 增益计算与校准 | 本项目 main.m 的 gain 公式与 BrightIntosh GammaTechnique.gammaFactor 数学等价；500-nit 参数 3.2 / 0.59、600-nit 参数 2.66 / 0.50 与上游 getScreenRefGamma 一致。 |
| 支持机型列表 | 参考 BrightIntosh 的 supportedDevices / sdr600nitsDevices。 |
| 温度读取 | Stats 提供 SMC 读取及传感器标识参考；本项目另写只读 Objective-C 封装。SMC 命令号、结构布局也属于接口兼容所需信息，不能据此声称接口本身为本项目原创。 |
| 在线更新 | 直接集成 Sparkle 2.10.0 预编译框架与发布工具，不是本项目编写的更新框架。 |
| 产品实现与整合 | 本项目实现菜单、面板、图标呈现、偏好保存、目标背光保持、热保护及恢复策略、单实例、测试和打包等。功能实现并不等于独立发明相关概念。 |

## 可复查的上游证据

本次对照的 BrightIntosh 快照：`f6806b893926d3ed47424396d9f45575713b8709`。

- [GammaTechnique.swift：gammaFactor](https://github.com/niklasr22/BrightIntosh/blob/f6806b893926d3ed47424396d9f45575713b8709/BrightIntosh/GammaTechnique.swift#L397)
- [Utils.swift：getScreenRefGamma](https://github.com/niklasr22/BrightIntosh/blob/f6806b893926d3ed47424396d9f45575713b8709/BrightIntosh/Utils.swift#L208)
- [Constants.swift：机型列表](https://github.com/niklasr22/BrightIntosh/blob/f6806b893926d3ed47424396d9f45575713b8709/BrightIntosh/Constants.swift#L35)
- [OverlayWindow.swift：1×1 叠加窗与 1.6 HDR 请求值](https://github.com/niklasr22/BrightIntosh/blob/f6806b893926d3ed47424396d9f45575713b8709/BrightIntosh/OverlayWindow.swift#L22)
- [Stats SMC 实现](https://github.com/exelban/stats/blob/27fa75a53d57072ec06adc730dcfe67633d639d2/SMC/smc.swift)
- [Sparkle 2.10.0](https://github.com/sparkle-project/Sparkle/tree/2.10.0)

当前上游快照用于核对可见相似之处，并不能完整还原开发时的每一次参考。本次没有进行全网代码查重，不给出“原创比例”，也不保证新写的实现没有相似代码。

## 发布与宣传

推荐表述：**释放 Mac XDR 屏幕的高亮潜力。**

说明：利用系统允许的 HDR 余量增强普通桌面显示，提供亮度调节与恢复功能。适用于支持的内置 XDR 屏幕机型。没有进行物理尼特测量，不能保证始终达到硬件峰值、全屏持续 1600 尼特或突破系统保护。

项目按 GPL-3.0 发布；保留 BrightIntosh 的 GPL 说明，以及 Stats、Sparkle 的相应许可与版权声明。具体文件见 THIRD_PARTY.md；这不是法律保证。
