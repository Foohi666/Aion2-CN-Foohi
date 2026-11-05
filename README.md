# AION 2 日文入口简繁汉化 · Foohi 二次升级版

基于原作者 **B站@吃素的佩奇** 在 **2026 年 10 月 14 日发布的 v1.2.1** 进行升级，二次升级作者为 **Foohi**。

- 原项目：[duoluoyuji/Aion2-Steam-CN](https://github.com/duoluoyuji/Aion2-Steam-CN)
- 基础版本：[v1.2.1 · 2026-10-14](https://github.com/duoluoyuji/Aion2-Steam-CN/releases/tag/v1.2.1)
- 基础脚本提交：[`962f17d`](https://github.com/duoluoyuji/Aion2-Steam-CN/commit/962f17db387709a54bf4e0554e06ec26c945623d)
- 二次升级项目：[Foohi666/Aion2-CN-Foohi](https://github.com/Foohi666/Aion2-CN-Foohi)
- [下载汉化包](https://github.com/Foohi666/Aion2-CN-Foohi/releases/latest) · [版本更新记录](CHANGELOG.md)

## 当前版本

**v1.2.1.10**，适配 **Steam build 26429009（2026-11-04 更新）**，2026-11-05 发布。

仅维护 **日本語文字语言 → 简体或繁体中文**，语音沿用游戏设置。每份文字表含 **153,419 条界面文本**；11 月 4 日数据更新补入 125 条新增文本、9,574 条历史漏译，另修订 70 条已有说明，并移除 3 条客户端已删除的文本。

本版文字和字体数据沿用 v1.2.1.9，配套修复更新后全界面 `???`、部分字符无法显示，以及能力页面的标题和分页异常。v1.2.1.9 的简繁中文分别完成游戏内菜单、背包、任务和语言切换验证；繁体冷启动验证通过，简体安装后由用户重新启动并确认正常。验证范围为实际抽查界面，不代表逐条完成游戏内检查。v1.2.1.10 的安装迁移修正通过离线测试，未新增游戏内实测。

## 使用与还原

1. 下载 [Release ZIP](https://github.com/Foohi666/Aion2-CN-Foohi/releases/latest)，完整解压。
2. 完全退出游戏，双击 `启动汉化工具.bat`。
3. 选择 Steam 客户端，阅读使用说明，安装“简体中文”或“繁体中文”。
4. 游戏内文字语言设为 **日本語**。
5. 切换简繁版本或还原前均须退出游戏；还原请点击“还原【日文】”。

还原同时恢复日文文字资源和本版修改的字体资源。备份保存在游戏目录 `Aion2_Text_Backup/ja-JP/PackedFontAlias`，文件扩展名为 `.bak`，请保留。旧版备份与历史归档仍保留在 `Aion2_Text_Backup` 中，不要改回游戏可加载的扩展名。

安装时若发现 `Aion2/Content/L10N/Text/ja-JP/L10NString.dat` 外置文字表，工具会在核验当前资源后，将它原样移至上述备份目录的 `ExternalText` 子目录，文件名以 `.dat.bak` 结尾。安装失败会恢复该表；安装成功后，使用还原功能恢复当前版本原版资源，外置表保留在备份中。

安装前核对客户端 build 和原文件哈希，写入前验证完整候选资源；失败时回滚。已安装过旧版且更新后原文件不完整时，请先通过 Steam 验证游戏文件。不得用旧备份覆盖新版本。后续游戏更新需要重新适配，不能保证永久兼容；当前版本不支持 PURPLE 安装。

## 文字使用限制

本版通过字符映射与配套字体显示中文，内部文本与屏幕字形可能不同。复制出的文字、使用正常中文输入的搜索，以及含这些字符的玩家昵称或聊天，可能受到影响；相关行为尚未逐项完成游戏内验证。需要原版文字行为时，请使用还原功能。

字体修改依据 SIL Open Font License 1.1 分发，见 [OFL.txt](font/OFL.txt) 与 [字体说明](font/NOTICE.txt)。

## 旧版英文、韩文还原

英文、韩文已停止汉化维护，仅保留旧版备份还原兼容：

```powershell
.\Aion2CNTool.ps1 -Restore -TargetLanguage en-US
.\Aion2CNTool.ps1 -Restore -TargetLanguage ko-KR
```

退出游戏后执行，工具仍会核对备份与客户端版本。安装或还原时，会将原项目遗留的可加载英文备份改为 `.bak`；发生备份冲突时停止操作。

## 更新与验证

“检查更新”只读取 `Foohi666/Aion2-CN-Foohi` 的正式 Release，显示版本说明；点击“确定”后打开该版本下载页，不自动下载或安装。

本版离线验证包括文字表独立解码与字形映射、当前文本键覆盖、占位符/格式检查、资源哈希，以及 Windows PowerShell 5.1 下的简繁安装、双向切换、五文件还原、旧备份兼容和写入失败回滚。

每次发布更新 `version.json` 和 [CHANGELOG.md](CHANGELOG.md)，运行 `scripts/Build-Release.ps1` 生成 ZIP、SHA256 与同版 Release 正文。发布包只收录运行所需脚本、文字数据、字体补丁和必要说明。

## 署名与使用声明

原作者 **B站@吃素的佩奇**；二次升级作者 **Foohi**。基础为原作者 2026-10-14 的 v1.2.1，来源链接见页首。

免费分享，仅供交流学习，严禁倒卖牟利。游戏资源及相关名称归其权利人所有。本项目为社区修改工具，不属于官方客户端功能；使用前请阅读界面声明。
