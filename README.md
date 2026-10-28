# AION 2 日文入口简繁汉化 · Foohi 二次升级版

基于原作者 **B站@吃素的佩奇** 在 **2026 年 10 月 14 日发布的 v1.2.1** 进行升级，二次升级作者为 **Foohi**。

- 原项目：[duoluoyuji/Aion2-Steam-CN](https://github.com/duoluoyuji/Aion2-Steam-CN)
- 基础版本：[v1.2.1 · 2026-10-14](https://github.com/duoluoyuji/Aion2-Steam-CN/releases/tag/v1.2.1)
- 基础脚本提交：[`962f17d`](https://github.com/duoluoyuji/Aion2-Steam-CN/commit/962f17db387709a54bf4e0554e06ec26c945623d)
- 二次升级项目：[Foohi666/Aion2-CN-Foohi](https://github.com/Foohi666/Aion2-CN-Foohi)
- [下载汉化包](https://github.com/Foohi666/Aion2-CN-Foohi/releases/latest) · [版本更新记录](CHANGELOG.md)

## 功能

- 将游戏的 **日本語文字语言**替换为简体或繁体中文。语音使用游戏原有设置。
- 原文件备份使用 `.bak` 扩展名，避免游戏在切换语言时加载原版备份；切回日本語后继续显示中文。
- 安装和还原均保留原文件及校验记录。
- 更新备份前核对新版原文件哈希，保留旧备份历史；缺少新版原文件时停止，防止旧资源覆盖新版本。
- **检查更新**读取本仓库的最新正式 Release，显示版本号与更新内容。发现新版本后，点击“确定”才会打开本仓库对应版本的下载页；点击“取消”不跳转。

## 当前版本与验证范围

当前版本 **v1.2.1.8**，文字数据对应 **Steam build 26262663（2026-10-28）**。

每份文字表包含 **153,297 条界面文本**。基础中文沿用原项目，新增及变更内容按当前客户端核对补译，部分文本仍待补齐。

| 检查项目 | 已完成的验证 |
| --- | --- |
| 日文入口简繁文字表 | 独立解码、文本内容、原文件与 Steam 清单哈希 |
| 安装和还原 | PowerShell 7.6.5 下的日文简繁安装、还原、版本迁移及失败回滚；旧版英文、韩文备份还原 |
| 日文简体入口 | 当前客户端菜单、两条反馈异常的任务目标在重启后显示中文；切到英文再切回两次保持中文 |
| 繁体数据 | 完成离线检查，未单独进行本版游戏内显示实测 |

安装或还原任一入口时，也会将原项目遗留的英文备份改为 `.bak`，避免切换语言时被游戏加载。未来客户端更新后仍需重新核对适配。

## 使用

1. 从 [Releases](https://github.com/Foohi666/Aion2-CN-Foohi/releases) 下载 `Aion2-CN-Foohi-v版本号.zip` 并完整解压。文字表仅随此下载包提供；GitHub 的 `Source code` 源码包不能直接用于汉化。
2. 完全退出游戏，双击 `启动汉化工具.bat`。
3. 选择客户端，工具固定使用日文入口。
4. 阅读界面声明后，选择“简体中文”或“繁体中文”。
5. 游戏内文字语言设为 **日本語**。
6. 要还原时，退出游戏并点击“还原【日文】”。

备份位于游戏目录的 `Aion2_Text_Backup/语言代码`；升级归档位于 `Aion2_Text_Backup/History`，请保留。不要把备份改回 `.pak` 等可加载扩展名。

游戏更新前建议先还原已安装入口。已更新客户端可以使用对应新版汉化包；若工具提示缺少新版原文件，请先通过 Steam 验证游戏文件。不同 Steam build 的数据不会强行套用。PURPLE 路径识别沿用原项目，但本版验证对象是上述 Steam build。

## 旧版迁移

从 v1.2.1.8 起仅维护日文入口，停止英文、韩文汉化。曾安装这两个入口的用户，可在退出游戏后用命令行分别还原：

```powershell
.\Aion2CNTool.ps1 -Restore -TargetLanguage en-US
.\Aion2CNTool.ps1 -Restore -TargetLanguage ko-KR
```

还原使用原有备份及版本校验，不影响日文汉化。

## 更新与发布

每次版本变更均记录在 [CHANGELOG.md](CHANGELOG.md)，GitHub Release 正文同步该版本记录，供界面的“检查更新”展示。

构建时需要本地的 `zh/ja-JP/L10NString.dat` 和 `zh-TW/ja-JP/L10NString.dat`，以及匹配的 `payloads.json` 校验记录。修改 `version.json` 并补齐对应的更新日志后运行：

```powershell
.\scripts\Build-Release.ps1
```

脚本核验版本、更新日志和两份日文入口数据的哈希，生成 ZIP、SHA256 校验文件及该版 Release 正文。构建不会自动发布或修改游戏文件。

## 署名与使用声明

原作者署名保留为 **B站@吃素的佩奇**；**Foohi** 负责维护与二次升级。基础工具和中文资源来源见上方链接。

沿用原项目声明：免费分享，仅供交流学习，严禁倒卖牟利。游戏资源及相关名称归其权利人所有。本项目为社区修改工具，不属于官方客户端功能；使用前请阅读界面声明。
