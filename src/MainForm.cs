using System;
using System.Diagnostics;
using System.Drawing;
using System.IO;
using System.Threading.Tasks;
using System.Windows.Forms;

namespace Foohi.Aion2
{
    public sealed class MainForm : Form
    {
        private readonly PatchService service = new PatchService(AppDomain.CurrentDomain.BaseDirectory);
        private readonly ComboBox path = new ComboBox();
        private readonly TextBox log = new TextBox();
        private readonly Label state = new Label();
        private readonly RadioButton simplified = new RadioButton();
        private readonly TableLayoutPanel root = new TableLayoutPanel();
        private readonly FlowLayoutPanel actions = new FlowLayoutPanel();
        private readonly FlowLayoutPanel links = new FlowLayoutPanel();
        private readonly TableLayoutPanel directory = new TableLayoutPanel();
        private bool busy;
        private bool instructionsAccepted;
        private int inspection;

        public MainForm(string initialPath)
        {
            Text = "Foohi / AION 2 汉化";
            ClientSize = new Size(900, 640);
            MinimumSize = new Size(800, 600);
            StartPosition = FormStartPosition.CenterScreen;
            BackColor = Color.FromArgb(24, 32, 43);
            ForeColor = Color.FromArgb(222, 230, 238);
            Font = new Font("Microsoft YaHei UI", 10);
            AutoScaleMode = AutoScaleMode.Dpi;

            root.Dock = DockStyle.Fill;
            root.Padding = new Padding(32);
            root.ColumnCount = 1;
            root.RowCount = 8;
            foreach (int height in new[] { 70, 84, 80, 60, 78, 42, 140 })
                root.RowStyles.Add(new RowStyle(SizeType.Absolute, height));
            root.RowStyles.Add(new RowStyle(SizeType.Percent, 100));
            Controls.Add(root);

            var heading = new TableLayoutPanel { Dock = DockStyle.Fill, ColumnCount = 2 };
            heading.ColumnStyles.Add(new ColumnStyle(SizeType.Percent, 100));
            heading.ColumnStyles.Add(new ColumnStyle(SizeType.AutoSize));
            heading.Controls.Add(new Label { Text = "AION 2 汉化", Font = new Font(Font.FontFamily, 25, FontStyle.Bold), Dock = DockStyle.Fill });
            heading.Controls.Add(new Label { Text = "Foohi  /  v" + Program.Version, AutoSize = true, Anchor = AnchorStyles.Right, Margin = new Padding(10, 15, 0, 0) });
            root.Controls.Add(heading);

            directory.Dock = DockStyle.Fill;
            directory.ColumnCount = 3;
            directory.RowCount = 2;
            directory.ColumnStyles.Add(new ColumnStyle(SizeType.Percent, 100));
            directory.ColumnStyles.Add(new ColumnStyle(SizeType.AutoSize));
            directory.ColumnStyles.Add(new ColumnStyle(SizeType.AutoSize));
            directory.RowStyles.Add(new RowStyle(SizeType.Absolute, 28));
            directory.RowStyles.Add(new RowStyle(SizeType.Percent, 100));
            var caption = new Label { Text = "游戏目录", AutoSize = true };
            directory.Controls.Add(caption, 0, 0);
            directory.SetColumnSpan(caption, 3);
            path.Text = initialPath;
            path.Dock = DockStyle.Top;
            path.BackColor = Color.FromArgb(37, 48, 62);
            path.ForeColor = ForeColor;
            path.DropDownStyle = ComboBoxStyle.DropDown;
            directory.Controls.Add(path, 0, 1);
            directory.Controls.Add(MakeButton("浏览", Browse), 1, 1);
            directory.Controls.Add(MakeButton("自动查找", async (s, e) => await Discover()), 2, 1);
            root.Controls.Add(directory);

            state.Text = "选择目录后检查游戏状态";
            state.Dock = DockStyle.Fill;
            root.Controls.Add(state);
            actions.Dock = DockStyle.Fill;
            actions.WrapContents = false;
            simplified.Text = "简体中文";
            simplified.Checked = true;
            simplified.AutoSize = true;
            simplified.Margin = new Padding(0, 9, 18, 0);
            actions.Controls.Add(simplified);
            actions.Controls.Add(new RadioButton { Text = "繁體中文", AutoSize = true, Margin = new Padding(0, 9, 20, 0) });
            var install = MakeButton("安装汉化", async (s, e) => await Install());
            install.BackColor = Color.FromArgb(27, 132, 199);
            install.FlatAppearance.BorderColor = install.BackColor;
            actions.Controls.Add(install);
            actions.Controls.Add(MakeButton("还原原版", async (s, e) =>
            {
                string target = path.Text;
                await Run(() => service.Restore(target, Write));
            }));
            var more = MakeButton("更多", delegate { });
            var menu = new ContextMenuStrip();
            menu.Items.Add("还原旧版英文备份", null, async (s, e) => await RestoreLegacy("en-US"));
            menu.Items.Add("还原旧版韩文备份", null, async (s, e) => await RestoreLegacy("ko-KR"));
            more.Click += (s, e) => menu.Show(more, new Point(0, more.Height));
            more.Disposed += (s, e) => menu.Dispose();
            actions.Controls.Add(more);
            root.Controls.Add(actions);
            root.Controls.Add(new Label
            {
                Dock = DockStyle.Fill,
                Text = "使用前请退出游戏，安装后选择「日本語」文字语言。\r\n字体映射可能影响复制、中文搜索、玩家昵称与聊天。游戏更新后请重新检查适配状态。"
            });
            links.Dock = DockStyle.Fill;
            links.Controls.Add(MakeButton("检查更新", async (s, e) => await CheckUpdate()));
            links.Controls.Add(MakeButton("关于", (s, e) => ShowSources()));
            var details = MakeButton("收起日志", delegate { });
            details.Click += (s, e) =>
            {
                log.Visible = !log.Visible;
                root.RowStyles[6].Height = log.Visible ? 140 : 0;
                details.Text = log.Visible ? "收起日志" : "展开日志";
            };
            links.Controls.Add(details);
            root.Controls.Add(links);
            log.Dock = DockStyle.Fill;
            log.Multiline = true;
            log.ReadOnly = true;
            log.ScrollBars = ScrollBars.Vertical;
            log.BackColor = Color.FromArgb(18, 25, 34);
            log.ForeColor = Color.FromArgb(173, 191, 207);
            log.BorderStyle = BorderStyle.None;
            root.Controls.Add(log);
            path.TextChanged += (s, e) => { inspection++; state.Text = "目录已更改，请稍候或移出输入框检查。"; };
            path.Leave += async (s, e) => await Inspect();
            path.SelectionChangeCommitted += async (s, e) => await Inspect();
            Shown += async (s, e) =>
            {
                if (string.IsNullOrWhiteSpace(initialPath)) await Discover();
                else await Inspect();
            };
            FormClosing += (s, e) => { if (busy) e.Cancel = true; else inspection++; };
        }

        private Button MakeButton(string text, EventHandler click)
        {
            var button = new Button
            {
                Text = text, AutoSize = true, MinimumSize = new Size(80, 34),
                Margin = new Padding(4, 0, 6, 0), FlatStyle = FlatStyle.Flat,
                BackColor = Color.FromArgb(39, 51, 66), ForeColor = ForeColor, Cursor = Cursors.Hand
            };
            button.FlatAppearance.BorderColor = Color.FromArgb(60, 76, 94);
            button.Click += click;
            return button;
        }

        private void Browse(object sender, EventArgs args)
        {
            using (var dialog = new FolderBrowserDialog())
            {
                dialog.Description = "选择 AION 2 游戏目录（Steam 或 NC / PURPLE）";
                if (dialog.ShowDialog(this) == DialogResult.OK) path.Text = dialog.SelectedPath;
            }
            var ignored = Inspect();
        }

        private async Task Discover()
        {
            if (busy) return;
            busy = true;
            inspection++;
            directory.Enabled = actions.Enabled = links.Enabled = false;
            state.Text = "正在查找游戏目录…";
            try
            {
                var games = await Task.Run(() => service.DiscoverGames());
                path.Items.Clear();
                foreach (string game in games) path.Items.Add(game);
                if (games.Count > 0) path.SelectedIndex = 0;
                else state.Text = "未找到游戏，请手动选择目录";
            }
            catch (Exception error)
            {
                Write("查找目录：" + error.Message);
                state.Text = "未找到游戏，请手动选择目录";
            }
            finally
            {
                busy = false;
                directory.Enabled = actions.Enabled = links.Enabled = true;
            }
            if (path.Items.Count > 0) await Inspect();
        }
        private async Task Install()
        {
            if (!instructionsAccepted)
            {
                if (MessageBox.Show(this, "请先退出游戏。安装后选择「日本語」文字语言。字体映射可能影响复制、中文搜索、玩家昵称与聊天。是否继续？", "安装汉化", MessageBoxButtons.OKCancel, MessageBoxIcon.Information) != DialogResult.OK) return;
                instructionsAccepted = true;
            }
            string target = path.Text;
            string variant = simplified.Checked ? "zh" : "zh-TW";
            await Run(() => service.Install(target, variant, Write));
        }

        private async Task RestoreLegacy(string language)
        {
            string target = path.Text;
            await Run(() => service.RestoreLegacy(target, language, Write));
        }

        private void Write(string message)
        {
            if (IsDisposed) return;
            if (InvokeRequired) { BeginInvoke((Action<string>)Write, message); return; }
            log.AppendText(DateTime.Now.ToString("HH:mm:ss") + "  " + message + Environment.NewLine);
        }

        private async Task Inspect()
        {
            if (busy || string.IsNullOrWhiteSpace(path.Text)) return;
            string target = path.Text;
            int token = ++inspection;
            state.Text = "正在检查游戏文件…";
            try
            {
                var info = await Task.Run(() => service.Inspect(target));
                if (IsDisposed || token != inspection || busy) return;
                state.Text = info.ClientLabel + "  ·  游戏版本 " + info.BuildId + "\r\n" + info.Status;
            }
            catch (Exception error)
            {
                if (!IsDisposed && token == inspection && !busy) state.Text = error.Message;
            }
        }

        private async Task Run(Action action)
        {
            if (busy) return;
            busy = true;
            inspection++;
            directory.Enabled = actions.Enabled = links.Enabled = false;
            state.Text = "正在处理，请稍候…";
            Write("开始处理");
            try { await Task.Run(action); Write("处理完成"); }
            catch (Exception error)
            {
                Write("未完成：" + error.Message);
                MessageBox.Show(this, error.Message, "操作未完成", MessageBoxButtons.OK, MessageBoxIcon.Warning);
            }
            finally
            {
                busy = false;
                directory.Enabled = actions.Enabled = links.Enabled = true;
            }
            await Inspect();
        }

        private void ShowSources()
        {
            string file = Path.Combine(AppDomain.CurrentDomain.BaseDirectory, "SOURCES.md");
            using (var dialog = new Form { Text = "关于与数据来源", Size = new Size(680, 480), StartPosition = FormStartPosition.CenterParent })
            {
                dialog.Controls.Add(new TextBox
                {
                    Dock = DockStyle.Fill, Multiline = true, ReadOnly = true, ScrollBars = ScrollBars.Vertical,
                    Font = Font, Text = File.Exists(file) ? File.ReadAllText(file) : "Foohi / AION 2 汉化  v" + Program.Version
                });
                dialog.ShowDialog(this);
            }
        }

        private async Task CheckUpdate()
        {
            await Run(() =>
            {
                var release = new UpdateService().Check(Program.Version);
                Invoke((Action)(() =>
                {
                    if (!release.HasUpdate) { MessageBox.Show(this, "当前已是最新正式版本。", "检查更新"); return; }
                    string notes = release.Notes ?? "";
                    if (notes.Length > 2000) notes = notes.Substring(0, 2000) + "\r\n…完整内容请查看下载页面。";
                    if (MessageBox.Show(this, "发现新版本 " + release.Version + "\r\n\r\n" + notes + "\r\n\r\n打开下载页面？", "版本更新", MessageBoxButtons.OKCancel, MessageBoxIcon.Information) == DialogResult.OK)
                        Process.Start(new ProcessStartInfo(release.Url) { UseShellExecute = true });
                }));
            });
        }
    }
}


