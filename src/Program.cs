using System;
using System.Windows.Forms;

namespace Foohi.Aion2
{
    internal static class Program
    {
        public const string Version = "2.0.3";

        [STAThread]
        private static void Main(string[] args)
        {
            Application.EnableVisualStyles();
            Application.SetCompatibleTextRenderingDefault(false);
            try
            {
                string path = "";
                for (int i = 0; i + 1 < args.Length; i++)
                    if (args[i] == "--game") path = args[++i];
                Application.Run(new MainForm(path));
            }
            catch (Exception error)
            {
                MessageBox.Show("程序无法启动，请确认已完整解压程序与汉化数据。\r\n\r\n" + error.Message,
                    "AION 2 汉化", MessageBoxButtons.OK, MessageBoxIcon.Error);
            }
        }
    }
}
