using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.IO;
using System.Linq;
using System.Security.Cryptography;
using System.Text;
using System.Text.RegularExpressions;
using System.Threading;
using System.Web.Script.Serialization;
using Microsoft.Win32;

namespace Foohi.Aion2
{
    public sealed class InstallationInfo
    {
        public string BuildId, Status, ClientLabel;
        public bool ContentMatches;
    }

    internal sealed class ProductMetadata { public string version; public string steamBuildId; public string repository; }
    internal sealed class NativeFile { public string Name; public string Hash; public long Size; }
    internal sealed class TextFile { public string Language; public string SHA256; }
    internal sealed class PackedFile { public string SHA256; public long Size; public long PayloadOffset; public int PayloadLength; public long PayloadHashOffset; }
    internal sealed class TextManifest
    {
        public string InstallationMode, SteamBuildId, FontPatchManifest;
        public List<TextFile> Files;
        public Dictionary<string, List<NativeFile>> OriginalFiles;
        public PackedFile PackedFile;
        public List<string> PreviousPackedHashes;
    }
    internal sealed class FontOrigin { public string Path, SHA256; public long Size; }
    internal sealed class FontRegion { public long Offset; public int Length; public string BeforeSHA256, AfterSHA256, DataFile; }
    internal sealed class FontAsset { public string Path, SHA256; public long Size; }
    internal sealed class FontManifest
    {
        public int SchemaVersion;
        public string SteamBuildId, PatchedSHA256;
        public FontOrigin OriginalFile;
        public List<FontRegion> Regions;
        public List<FontAsset> AssetFiles;
    }
    internal sealed class BackupFile { public string Relative, Hash, Backup; public long Size; }
    internal sealed class BackupState { public int SchemaVersion; public string BuildId; public List<BackupFile> Files; }
    internal sealed class LegacyState { public string Language, BuildId, DatHash; public bool HadDat; public List<NativeFile> Files; }
    internal sealed class Profile { public string Variant; public TextManifest Text; public FontManifest Font; public List<BackupFile> Native; }
    internal sealed class GameLocation { public string Root, Build, Client; }
    internal sealed class Replacement { public string Target, Input, Expected, Before, Stage, Undo; public long Size; public bool Applied; }
    internal sealed class ArchiveMove { public string Source, Destination, Hash; public bool Applied; }

    internal static class Disk
    {
        internal static T ReadJson<T>(string path)
        {
            if (!File.Exists(path) || new FileInfo(path).Length > 1024 * 1024)
                throw new IOException("配置文件缺失或过大：" + path);
            return new JavaScriptSerializer { MaxJsonLength = 1024 * 1024 }.Deserialize<T>(File.ReadAllText(path, Encoding.UTF8));
        }

        internal static string Under(string root, string relative)
        {
            string boundary = Path.GetFullPath(root).TrimEnd(Path.DirectorySeparatorChar) + Path.DirectorySeparatorChar;
            string full = Path.GetFullPath(Path.Combine(boundary, relative.Replace('/', Path.DirectorySeparatorChar)));
            if (!full.StartsWith(boundary, StringComparison.OrdinalIgnoreCase)) throw new IOException("文件路径超出所选目录。");
            string cursor = full;
            while (cursor != null)
            {
                if ((File.Exists(cursor) || Directory.Exists(cursor)) && (File.GetAttributes(cursor) & FileAttributes.ReparsePoint) != 0)
                    throw new IOException("请使用真实文件目录，不支持符号链接：" + cursor);
                cursor = Path.GetDirectoryName(cursor);
            }
            return full;
        }

        internal static string Hash(string path)
        {
            using (var stream = File.OpenRead(path))
            using (var algorithm = SHA256.Create()) return Hex(algorithm.ComputeHash(stream));
        }

        internal static string Hex(byte[] bytes) { return BitConverter.ToString(bytes).Replace("-", "").ToLowerInvariant(); }
        internal static bool Same(string a, string b) { return String.Equals(a, b, StringComparison.OrdinalIgnoreCase); }
        internal static void Verify(string path, string hash, long size)
        {
            if (!File.Exists(path)) throw new IOException("缺少文件：" + path);
            if ((size >= 0 && new FileInfo(path).Length != size) || !Same(Hash(path), hash))
                throw new IOException("文件与已适配资源不一致：" + path + "。请先修复客户端文件或使用匹配的汉化版本。");
        }

        internal static void SaveState(string path, BackupState state)
        {
            string temp = path + "." + Guid.NewGuid().ToString("N") + ".tmp.bak";
            try
            {
                File.WriteAllText(temp, new JavaScriptSerializer().Serialize(state), new UTF8Encoding(false));
                File.Move(temp, path);
            }
            finally { if (File.Exists(temp)) File.Delete(temp); }
        }
    }

    public sealed class PatchService
    {
        private const string NativeFont = "Aion2/Content/Paks/pakchunk0-Windows.pak";
        private const string BackupFolder = "Aion2_Text_Backup/ja-JP/PackedFontAlias";
        private readonly string package;
        private readonly Func<bool> gameIsRunning;
        private readonly ProductMetadata metadata;

        public PatchService(string packageRoot) : this(packageRoot, IsGameRunning) { }
        internal PatchService(string packageRoot, Func<bool> running)
        {
            package = Path.GetFullPath(packageRoot);
            gameIsRunning = running;
            metadata = Disk.ReadJson<ProductMetadata>(Disk.Under(package, "version.json"));
            if (metadata.repository != "Foohi666/Aion2-CN-Foohi" || String.IsNullOrEmpty(metadata.steamBuildId))
                throw new IOException("工具版本信息不完整，请重新解压完整下载包。");
        }

        private static bool IsGameRunning()
        {
            foreach (string name in new[] { "AION2", "Aion2-Win64-Shipping" })
            {
                Process[] processes = Process.GetProcessesByName(name);
                bool found = processes.Length > 0;
                foreach (Process process in processes) process.Dispose();
                if (found) return true;
            }
            return false;
        }

        private void RequireGameClosed()
        {
            if (gameIsRunning()) throw new InvalidOperationException("请完全退出 AION 2 后再安装或还原。");
        }

        private static string ManifestValue(string data, string key)
        {
            Match match = Regex.Match(data, "\"" + Regex.Escape(key) + "\"\\s+\"([^\"]+)\"");
            return match.Success ? match.Groups[1].Value : null;
        }

        private GameLocation Locate(string path)
        {
            string root = Path.GetFullPath(path.Trim()).TrimEnd(Path.DirectorySeparatorChar);
            if (!Directory.Exists(Disk.Under(root, "Aion2/Content/Paks")))
                throw new IOException("请选择包含 Aion2 文件夹的游戏安装目录。");
            var location = new GameLocation { Root = root, Client = "NC / 其他启动器", Build = null };
            DirectoryInfo parent = Directory.GetParent(root);
            if (parent != null && parent.Parent != null)
            {
                foreach (string app in new[] { "3393110", "4972320" })
                {
                    string manifest = Path.Combine(parent.Parent.FullName, "appmanifest_" + app + ".acf");
                    if (!File.Exists(manifest) || new FileInfo(manifest).Length > 1024 * 1024) continue;
                    string text = File.ReadAllText(manifest);
                    if (!Disk.Same(ManifestValue(text, "installdir"), Path.GetFileName(root))) continue;
                    location.Client = "Steam";
                    location.Build = ManifestValue(text, "buildid");
                    break;
                }
            }
            return location;
        }

        public List<string> DiscoverGames()
        {
            var libraries = new HashSet<string>(StringComparer.OrdinalIgnoreCase);
            foreach (RegistryKey hive in new[] { Registry.CurrentUser, Registry.LocalMachine })
                foreach (string keyPath in new[] { @"Software\Valve\Steam", @"Software\WOW6432Node\Valve\Steam" })
                    try
                    {
                        using (RegistryKey key = hive.OpenSubKey(keyPath))
                        {
                            if (key == null) continue;
                            string value = (key.GetValue("SteamPath") ?? key.GetValue("InstallPath")) as string;
                            if (!String.IsNullOrWhiteSpace(value)) libraries.Add(value.Replace('/', '\\'));
                        }
                    }
                    catch (System.Security.SecurityException) { }
            libraries.Add(Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.ProgramFilesX86), "Steam"));
            foreach (string library in libraries.ToArray())
            {
                string index = Path.Combine(library, "steamapps", "libraryfolders.vdf");
                if (!File.Exists(index) || new FileInfo(index).Length > 1024 * 1024) continue;
                foreach (Match m in Regex.Matches(File.ReadAllText(index), "\"path\"\\s+\"([^\"]+)\""))
                    libraries.Add(m.Groups[1].Value.Replace("\\\\", "\\"));
            }
            var results = new HashSet<string>(StringComparer.OrdinalIgnoreCase);
            foreach (string library in libraries)
                foreach (string app in new[] { "3393110", "4972320" })
                {
                    string manifest = Path.Combine(library, "steamapps", "appmanifest_" + app + ".acf");
                    if (!File.Exists(manifest) || new FileInfo(manifest).Length > 1024 * 1024) continue;
                    string folder = ManifestValue(File.ReadAllText(manifest), "installdir");
                    if (String.IsNullOrEmpty(folder) || folder != Path.GetFileName(folder)) continue;
                    string candidate = Path.Combine(library, "steamapps", "common", folder);
                    if (Directory.Exists(Path.Combine(candidate, "Aion2", "Content", "Paks"))) results.Add(candidate);
                }
            foreach (string candidate in FindGameDirectories(InstalledLocationHints())) results.Add(candidate);
            return results.OrderBy(x => x).ToList();
        }

        private static IEnumerable<string> InstalledLocationHints()
        {
            var hints = new HashSet<string>(StringComparer.OrdinalIgnoreCase);
            foreach (RegistryKey hive in new[] { Registry.CurrentUser, Registry.LocalMachine })
                foreach (string keyPath in new[] { @"Software\Microsoft\Windows\CurrentVersion\Uninstall", @"Software\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall" })
                    try
                    {
                        using (RegistryKey entries = hive.OpenSubKey(keyPath))
                        {
                            if (entries == null) continue;
                            foreach (string name in entries.GetSubKeyNames())
                                using (RegistryKey entry = entries.OpenSubKey(name))
                                {
                                    if (entry == null) continue;
                                    string title = entry.GetValue("DisplayName") as string ?? "";
                                    if (!Regex.IsMatch(title, @"AION\s*2|PURPLE|NCSOFT|NC\s*Launcher", RegexOptions.IgnoreCase)) continue;
                                    string location = entry.GetValue("InstallLocation") as string;
                                    if (!String.IsNullOrWhiteSpace(location)) hints.Add(Environment.ExpandEnvironmentVariables(location.Trim().Trim('"')));
                                    string icon = entry.GetValue("DisplayIcon") as string;
                                    if (String.IsNullOrWhiteSpace(icon)) continue;
                                    Match executable = Regex.Match(icon, "^\\s*\"?(.+?\\.exe)(?:\"|,|$)", RegexOptions.IgnoreCase);
                                    if (executable.Success)
                                    {
                                        string folder = Path.GetDirectoryName(Environment.ExpandEnvironmentVariables(executable.Groups[1].Value));
                                        if (!String.IsNullOrEmpty(folder)) hints.Add(folder);
                                    }
                                }
                        }
                    }
                    catch (System.Security.SecurityException) { }
                    catch (UnauthorizedAccessException) { }
                    catch (IOException) { }
                    catch (ArgumentException) { }
            foreach (DriveInfo drive in DriveInfo.GetDrives())
            {
                if (drive.DriveType != DriveType.Fixed) continue;
                string root = drive.RootDirectory.FullName;
                foreach (string suffix in new[] { "", "Games", "NCSOFT", "NCSoft\\Games", "PURPLE", "PURPLE\\Games", "Program Files\\NCSOFT", "Program Files (x86)\\NCSOFT", "Program Files\\PURPLE", "Program Files (x86)\\PURPLE" })
                    hints.Add(Path.Combine(root, suffix));
            }
            return hints;
        }

        internal static List<string> FindGameDirectories(IEnumerable<string> hints)
        {
            var found = new HashSet<string>(StringComparer.OrdinalIgnoreCase);
            foreach (string hint in hints)
            {
                try
                {
                    string root = Path.GetFullPath(hint);
                    if (!Directory.Exists(root) || (File.GetAttributes(root) & FileAttributes.ReparsePoint) != 0) continue;
                    if (Directory.Exists(Path.Combine(root, "Aion2", "Content", "Paks"))) found.Add(root.TrimEnd('\\'));
                    foreach (string directory in Directory.EnumerateDirectories(root))
                    {
                        string name = Path.GetFileName(directory).Replace(" ", "").Replace("_", "").Replace("-", "");
                        if (name.IndexOf("AION2", StringComparison.OrdinalIgnoreCase) < 0) continue;
                        if ((File.GetAttributes(directory) & FileAttributes.ReparsePoint) == 0 && Directory.Exists(Path.Combine(directory, "Aion2", "Content", "Paks"))) found.Add(directory);
                    }
                }
                catch (UnauthorizedAccessException) { }
                catch (IOException) { }
                catch (ArgumentException) { }
                catch (System.Security.SecurityException) { }
            }
            return found.OrderBy(x => x).ToList();
        }

        private Profile LoadProfile(string variant)
        {
            if (variant != "zh" && variant != "zh-TW") throw new ArgumentException("请选择简体或繁体中文。");
            TextManifest text = Disk.ReadJson<TextManifest>(Disk.Under(package, variant + "/payloads.json"));
            if (text.InstallationMode != "PackedFontAlias" || text.SteamBuildId != metadata.steamBuildId || text.FontPatchManifest != "font/" + variant + "/manifest.json")
                throw new IOException("文字数据与版本清单不匹配。");
            if (text.PreviousPackedHashes != null && text.PreviousPackedHashes.Any(hash => !Regex.IsMatch(hash ?? "", @"\A[a-fA-F0-9]{64}\z")))
                throw new IOException("旧版文字资源哈希清单无效。");
            FontManifest font = Disk.ReadJson<FontManifest>(Disk.Under(package, text.FontPatchManifest));
            if (font.SchemaVersion != 1 || font.SteamBuildId != metadata.steamBuildId || font.OriginalFile.Path != NativeFont)
                throw new IOException("字体清单不匹配。");
            var profile = new Profile { Variant = variant, Text = text, Font = font, Native = NativeRecords(text, "ja-JP") };
            profile.Native.Add(new BackupFile { Relative = NativeFont, Hash = font.OriginalFile.SHA256, Size = font.OriginalFile.Size, Backup = "pakchunk0-Windows.pak.bak" });
            return profile;
        }

        private static List<BackupFile> NativeRecords(TextManifest text, string language)
        {
            string chunk = language == "ja-JP" ? "503000" : language == "en-US" ? "502000" : "501000";
            List<NativeFile> files;
            if (text.OriginalFiles == null || !text.OriginalFiles.TryGetValue(language, out files) || files.Count != 4)
                throw new IOException("缺少原版资源清单。");
            var records = new List<BackupFile>();
            foreach (string extension in new[] { "pak", "sig", "ucas", "utoc" })
            {
                string name = "pakchunk" + chunk + "-Windows_0_P." + extension;
                NativeFile[] found = files.Where(f => f.Name == name).ToArray();
                if (found.Length != 1 || !Regex.IsMatch(found[0].Hash ?? "", "^[a-fA-F0-9]{64}$") || found[0].Size <= 0)
                    throw new IOException("原版资源记录无效：" + name);
                records.Add(new BackupFile { Relative = "Aion2/Content/Paks/L10N/Text/" + language + "/" + name, Hash = found[0].Hash, Size = found[0].Size, Backup = name + ".bak" });
            }
            return records;
        }

        private static string Expected(Profile profile, BackupFile file)
        {
            if (file.Relative == NativeFont) return profile.Font.PatchedSHA256;
            if (file.Backup.EndsWith(".pak.bak", StringComparison.Ordinal)) return profile.Text.PackedFile.SHA256;
            return file.Hash;
        }

        private static bool PreviousPacked(Profile profile, BackupFile file, string hash)
        {
            return file.Relative != NativeFont && file.Backup.EndsWith(".pak.bak", StringComparison.Ordinal) &&
                profile.Text.PreviousPackedHashes != null && profile.Text.PreviousPackedHashes.Any(previous => Disk.Same(previous, hash));
        }

        public InstallationInfo Inspect(string gameRoot)
        {
            GameLocation game = Locate(gameRoot);
            Profile simple = LoadProfile("zh"), traditional = LoadProfile("zh-TW");
            bool native = true, sc = true, tc = true, oldSc = true, oldTc = true;
            foreach (BackupFile file in simple.Native)
            {
                string path = Disk.Under(game.Root, file.Relative);
                string hash = File.Exists(path) ? Disk.Hash(path) : null;
                native &= Disk.Same(hash, file.Hash);
                sc &= Disk.Same(hash, Expected(simple, file));
                tc &= Disk.Same(hash, Expected(traditional, file));
                bool languagePak = file.Relative != NativeFont && file.Backup.EndsWith(".pak.bak", StringComparison.Ordinal);
                oldSc &= languagePak ? PreviousPacked(simple, file, hash) : Disk.Same(hash, Expected(simple, file));
                oldTc &= languagePak ? PreviousPacked(traditional, file, hash) : Disk.Same(hash, Expected(traditional, file));
            }
            bool hasState = File.Exists(Disk.Under(game.Root, BackupFolder + "/state.json"));
            if (hasState && (sc || tc || oldSc || oldTc))
                ValidateBackup(Disk.ReadJson<BackupState>(Disk.Under(game.Root, BackupFolder + "/state.json")), simple.Native, Disk.Under(game.Root, BackupFolder));
            bool earlier = (oldSc || oldTc) && hasState;
            string status = earlier && !sc && !tc ? "已安装较早版本，可更新" : native ? "原版资源匹配，可安装" : sc ? "已安装简体中文" : tc ? "已安装繁体中文" : "资源不匹配或不完整";
            if ((sc || tc) && !hasState) status += " · 缺少还原备份";
            if (game.Client != "Steam") status += " · 此启动器尚未游戏内实测";
            return new InstallationInfo { BuildId = game.Build ?? "按资源文件核验", ClientLabel = game.Client, ContentMatches = native || ((sc || tc || earlier) && hasState), Status = status };
        }

        public void Install(string gameRoot, string variant, Action<string> log) { Operate(gameRoot, variant, false, log); }
        public void Restore(string gameRoot, Action<string> log)
        {
            if (!File.Exists(Disk.Under(gameRoot, BackupFolder + "/state.json"))) { RestoreLegacy(gameRoot, "ja-JP", log); return; }
            Operate(gameRoot, "zh", true, log);
        }

        private void Operate(string gameRoot, string variant, bool restoring, Action<string> log)
        {
            WithLock(delegate
            {
                RequireGameClosed();
                GameLocation game = Locate(gameRoot);
                Profile selected = LoadProfile(variant), other = LoadProfile(variant == "zh" ? "zh-TW" : "zh");
                if (!Disk.Same(selected.Font.OriginalFile.SHA256, other.Font.OriginalFile.SHA256)) throw new IOException("简繁字体的原版基线不一致。");
                string backup = Disk.Under(game.Root, BackupFolder), statePath = Disk.Under(backup, "state.json");
                BackupState state = File.Exists(statePath) ? Disk.ReadJson<BackupState>(statePath) : null;
                if (state != null) ValidateBackup(state, selected.Native, backup);
                else if (restoring) throw new IOException("缺少可信还原备份，请通过启动器修复原版文件。");
                log("正在核验日文资源与字体文件…");
                var sources = new Dictionary<string, string>();
                foreach (BackupFile file in selected.Native)
                {
                    string active = Disk.Under(game.Root, file.Relative);
                    string current = File.Exists(active) ? Disk.Hash(active) : null;
                    bool original = Disk.Same(current, file.Hash);
                    bool installed = Disk.Same(current, Expected(selected, file)) || Disk.Same(current, Expected(other, file));
                    if (state != null)
                    {
                        if (!original && !installed && !PreviousPacked(selected, file, current) && !PreviousPacked(other, file, current)) throw new IOException("当前资源已改变，停止覆盖：" + active);
                        sources[file.Relative] = Disk.Under(backup, file.Backup);
                    }
                    else if (original) sources[file.Relative] = active;
                    else if (file.Relative != NativeFont && (!File.Exists(active) || new FileInfo(active).Length == 0))
                        sources[file.Relative] = FindLegacyOriginal(game.Root, "ja-JP", file);
                    else throw new IOException("资源不匹配或缺少可信备份：" + active + "。请先通过启动器修复文件。");
                }
                if (game.Client != "Steam") log("NC／其他启动器：所需资源已匹配；实际游戏兼容性仍需验证。");
                List<ArchiveMove> archives = CollectLegacyArchives(game.Root);
                string external = Disk.Under(game.Root, "Aion2/Content/L10N/Text/ja-JP/L10NString.dat");
                AddExternalArchive(archives, external, backup);
                if (state == null)
                {
                    Directory.CreateDirectory(backup);
                    foreach (BackupFile file in selected.Native)
                    {
                        string destination = Disk.Under(backup, file.Backup);
                        if (!File.Exists(destination)) File.Copy(sources[file.Relative], destination, false);
                        Disk.Verify(destination, file.Hash, file.Size);
                        sources[file.Relative] = destination;
                    }
                    Disk.SaveState(statePath, new BackupState { SchemaVersion = 1, BuildId = metadata.steamBuildId, Files = selected.Native });
                }
                var changes = new List<Replacement>();
                try
                {
                    foreach (BackupFile file in selected.Native)
                    {
                        string active = Disk.Under(game.Root, file.Relative);
                        var change = NewReplacement(active, sources[file.Relative], restoring ? file.Hash : Expected(selected, file), file.Size);
                        changes.Add(change);
                        File.Copy(change.Input, change.Stage, false);
                        if (!restoring && file.Relative == NativeFont) ApplyFont(change.Stage, selected);
                        else if (!restoring && file.Backup.EndsWith(".pak.bak", StringComparison.Ordinal)) ApplyText(change.Stage, selected);
                        Disk.Verify(change.Stage, change.Expected, change.Size);
                    }
                    Commit(changes, archives, log);
                }
                finally { CleanStages(changes); }
                log(restoring ? "还原完成：日文资源与字体已恢复原版。" : "安装完成。进入游戏后，文字语言请选择「日本語」。");
                log("原版备份：" + backup);
            });
        }

        private void ValidateBackup(BackupState state, List<BackupFile> expected, string folder)
        {
            if (state.SchemaVersion != 1 || state.BuildId != metadata.steamBuildId || state.Files == null || state.Files.Count != expected.Count)
                throw new IOException("备份不属于当前适配版本，请保留备份并修复客户端。");
            foreach (BackupFile file in expected)
            {
                if (state.Files.Count(f => f.Relative == file.Relative && f.Backup == file.Backup && f.Size == file.Size && Disk.Same(f.Hash, file.Hash)) != 1)
                    throw new IOException("备份记录不匹配：" + file.Backup);
                Disk.Verify(Disk.Under(folder, file.Backup), file.Hash, file.Size);
            }
        }

        private string FindLegacyOriginal(string root, string language, BackupFile file)
        {
            string directory = Disk.Under(root, "Aion2_Text_Backup/" + language);
            string recordPath = Disk.Under(directory, "state.json");
            if (File.Exists(recordPath))
            {
                LegacyState state = Disk.ReadJson<LegacyState>(recordPath);
                if (state.BuildId != metadata.steamBuildId || state.Files == null || state.Files.Count(f => f.Name == Path.GetFileName(file.Relative) && Disk.Same(f.Hash, file.Hash)) != 1)
                    throw new IOException("缺少当前版本原文件，旧备份不能替代；请通过启动器验证游戏文件。");
            }
            else if (language == "en-US") directory = Disk.Under(root, "Aion2_English_Backup_Safe");
            else throw new IOException("缺少当前版本原文件及备份，请通过启动器修复游戏。");
            string candidate = Disk.Under(directory, file.Backup);
            if (!File.Exists(candidate)) candidate = Disk.Under(directory, Path.GetFileName(file.Relative));
            Disk.Verify(candidate, file.Hash, file.Size);
            return candidate;
        }

        private void ApplyText(string path, Profile profile)
        {
            PackedFile layout = profile.Text.PackedFile;
            TextFile[] payload = profile.Text.Files.Where(x => x.Language == "ja-JP").ToArray();
            if (payload.Length != 1 || layout.PayloadLength != 3836404 || layout.PayloadOffset != 53 || layout.PayloadHashOffset != 28 || layout.Size != 3836918)
                throw new IOException("日文资源包布局不受支持。");
            string textPath = Disk.Under(package, profile.Variant + "/ja-JP/L10NString.dat");
            Disk.Verify(textPath, payload[0].SHA256, layout.PayloadLength);
            using (var output = new FileStream(path, FileMode.Open, FileAccess.Write, FileShare.None))
            using (var input = File.OpenRead(textPath))
            using (var sha = SHA1.Create())
            {
                byte[] digest = sha.ComputeHash(input);
                input.Position = 0;
                output.Position = layout.PayloadOffset;
                input.CopyTo(output);
                output.Position = layout.PayloadHashOffset;
                output.Write(digest, 0, digest.Length);
                output.Flush(true);
            }
        }

        private void ApplyFont(string path, Profile profile)
        {
            long end = 0;
            using (var stream = new FileStream(path, FileMode.Open, FileAccess.ReadWrite, FileShare.None))
                foreach (FontRegion region in profile.Font.Regions.OrderBy(x => x.Offset))
                {
                    if (region.Offset < end || region.Length <= 0 || region.Length > 1024 * 1024 || region.Offset > stream.Length - region.Length)
                        throw new IOException("字体区域越界或重叠。");
                    if (!Regex.IsMatch(region.DataFile ?? "", "^font/" + profile.Variant + "/blocks/[A-Za-z0-9_-]+\\.bin$"))
                        throw new IOException("字体补丁路径不合法。");
                    string patch = Disk.Under(package, region.DataFile);
                    Disk.Verify(patch, region.AfterSHA256, region.Length);
                    byte[] before = new byte[region.Length];
                    stream.Position = region.Offset;
                    int read = 0;
                    while (read < before.Length)
                    {
                        int n = stream.Read(before, read, before.Length - read);
                        if (n == 0) throw new EndOfStreamException("字体资源不完整。");
                        read += n;
                    }
                    using (var sha = SHA256.Create())
                        if (!Disk.Same(Disk.Hex(sha.ComputeHash(before)), region.BeforeSHA256)) throw new IOException("字体原区域校验失败。");
                    stream.Position = region.Offset;
                    using (var input = File.OpenRead(patch)) input.CopyTo(stream);
                    end = region.Offset + region.Length;
                }
        }

        private static Replacement NewReplacement(string target, string input, string hash, long size)
        {
            string token = Guid.NewGuid().ToString("N");
            return new Replacement { Target = target, Input = input, Expected = hash, Size = size, Before = File.Exists(target) ? Disk.Hash(target) : null, Stage = target + "." + token + ".stage.bak", Undo = target + "." + token + ".rollback.bak" };
        }

        private static void AddExternalArchive(List<ArchiveMove> list, string external, string backup)
        {
            if (Directory.Exists(external)) throw new IOException("文字文件路径被目录占用：" + external);
            if (!File.Exists(external)) return;
            list.Add(new ArchiveMove { Source = external, Destination = Disk.Under(backup, "ExternalText/L10NString." + Guid.NewGuid().ToString("N") + ".dat.bak"), Hash = Disk.Hash(external) });
        }

        private static List<ArchiveMove> CollectLegacyArchives(string root)
        {
            var moves = new List<ArchiveMove>();
            foreach (string language in new[] { "en-US", "ja-JP", "ko-KR" })
            {
                string chunk = language == "en-US" ? "502000" : language == "ja-JP" ? "503000" : "501000";
                var folders = new List<string> { "Aion2_Text_Backup/" + language };
                if (language == "en-US") folders.Add("Aion2_English_Backup_Safe");
                foreach (string folder in folders)
                    foreach (string extension in new[] { "pak", "sig", "ucas", "utoc" })
                    {
                        string source = Disk.Under(root, folder + "/pakchunk" + chunk + "-Windows_0_P." + extension);
                        if (!File.Exists(source)) continue;
                        string destination = Disk.Under(root, folder + "/" + Path.GetFileName(source) + ".bak");
                        string hash = Disk.Hash(source);
                        if (File.Exists(destination))
                        {
                            Disk.Verify(destination, hash, new FileInfo(source).Length);
                            destination = Disk.Under(root, folder + "/" + Path.GetFileName(source) + "." + Guid.NewGuid().ToString("N") + ".bak");
                        }
                        moves.Add(new ArchiveMove { Source = source, Destination = destination, Hash = hash });
                    }
            }
            return moves;
        }

        private void Commit(List<Replacement> changes, List<ArchiveMove> archives, Action<string> log)
        {
            RequireGameClosed();
            foreach (Replacement file in changes)
                if (!Disk.Same(File.Exists(file.Target) ? Disk.Hash(file.Target) : null, file.Before)) throw new IOException("操作期间资源发生变化，请重试。");
            bool rollbackFailed = false;
            try
            {
                foreach (ArchiveMove move in archives)
                {
                    Disk.Verify(move.Source, move.Hash, -1);
                    Directory.CreateDirectory(Path.GetDirectoryName(move.Destination));
                    File.Move(move.Source, move.Destination);
                    move.Applied = true;
                    Disk.Verify(move.Destination, move.Hash, -1);
                }
                log("校验通过，正在写入…");
                foreach (Replacement file in changes)
                {
                    if (file.Before == null) File.Move(file.Stage, file.Target);
                    else File.Replace(file.Stage, file.Target, file.Undo);
                    file.Applied = true;
                    Disk.Verify(file.Target, file.Expected, file.Size);
                }
            }
            catch (Exception error)
            {
                var failures = new List<string>();
                foreach (Replacement file in changes.AsEnumerable().Reverse().Where(x => x.Applied))
                    try
                    {
                        if (file.Before == null) File.Delete(file.Target);
                        else { File.Copy(file.Undo, file.Target, true); Disk.Verify(file.Target, file.Before, -1); }
                    }
                    catch (Exception rollback) { failures.Add(rollback.Message); }
                foreach (ArchiveMove move in archives.AsEnumerable().Reverse().Where(x => x.Applied))
                    try { File.Move(move.Destination, move.Source); Disk.Verify(move.Source, move.Hash, -1); }
                    catch (Exception rollback) { failures.Add(rollback.Message); }
                rollbackFailed = failures.Count != 0;
                if (rollbackFailed) throw new IOException("写入失败且部分回滚未完成，请保留 .rollback.bak 和归档文件：" + String.Join("；", failures), error);
                throw new IOException("安装或还原未完成，已恢复操作前的文件。" + Environment.NewLine + error.Message, error);
            }
            finally
            {
                if (!rollbackFailed) foreach (Replacement file in changes) if (File.Exists(file.Undo)) File.Delete(file.Undo);
            }
            foreach (ArchiveMove move in archives) log("已保留旧文件：" + move.Destination);
        }

        private static void CleanStages(List<Replacement> changes)
        {
            foreach (Replacement change in changes)
                try { if (File.Exists(change.Stage)) File.Delete(change.Stage); }
                catch (IOException) { }
        }

        public void RestoreLegacy(string gameRoot, string language, Action<string> log)
        {
            if (language != "en-US" && language != "ko-KR" && language != "ja-JP") throw new ArgumentException("语言不受支持。");
            WithLock(delegate
            {
                RequireGameClosed();
                GameLocation game = Locate(gameRoot);
                Profile profile = LoadProfile("zh");
                if (language == "ja-JP") Disk.Verify(Disk.Under(game.Root, NativeFont), profile.Font.OriginalFile.SHA256, profile.Font.OriginalFile.Size);
                List<BackupFile> records = NativeRecords(profile.Text, language);
                var changes = new List<Replacement>();
                string archive = Disk.Under(game.Root, "Aion2_Text_Backup/" + language);
                List<ArchiveMove> moves = CollectLegacyArchives(game.Root);
                AddExternalArchive(moves, Disk.Under(game.Root, "Aion2/Content/L10N/Text/" + language + "/L10NString.dat"), archive);
                try
                {
                    foreach (BackupFile file in records)
                    {
                        string active = Disk.Under(game.Root, file.Relative);
                        if (File.Exists(active) && Disk.Same(Disk.Hash(active), file.Hash)) continue;
                        if (File.Exists(active) && new FileInfo(active).Length > 0) throw new IOException("资源与当前原版不一致，请先通过启动器修复：" + active);
                        string source = FindLegacyOriginal(game.Root, language, file);
                        Replacement change = NewReplacement(active, source, file.Hash, file.Size);
                        changes.Add(change);
                        Directory.CreateDirectory(Path.GetDirectoryName(active));
                        File.Copy(source, change.Stage, false);
                        Disk.Verify(change.Stage, change.Expected, change.Size);
                    }
                    Commit(changes, moves, log);
                }
                finally { CleanStages(changes); }
                log("原版文字资源已恢复：" + language + "。备份继续保留。");
            });
        }

        private static void WithLock(Action work)
        {
            using (var gate = new Mutex(false, @"Local\FoohiAion2Patch"))
            {
                bool acquired;
                try { acquired = gate.WaitOne(0); } catch (AbandonedMutexException) { acquired = true; }
                if (!acquired) throw new IOException("另一项汉化操作正在执行，请完成后重试。");
                try { work(); } finally { gate.ReleaseMutex(); }
            }
        }
    }
}
