using System;
using System.Collections.Generic;
using System.IO;
using System.Net;
using System.Text;
using System.Text.RegularExpressions;
using System.Web.Script.Serialization;

namespace Foohi.Aion2
{
    public sealed class ReleaseInfo
    {
        public bool HasUpdate;
        public string Version, Notes, Url;
    }

    public sealed class UpdateService
    {
        private const int Limit = 1024 * 1024;
        public ReleaseInfo Check(string currentVersion)
        {
            try
            {
                ServicePointManager.SecurityProtocol |= SecurityProtocolType.Tls12;
                HttpWebRequest request = (HttpWebRequest)WebRequest.Create("https://api.github.com/repos/Foohi666/Aion2-CN-Foohi/releases/latest");
                request.UserAgent = "Aion2-CN-Foohi-UpdateCheck";
                request.Accept = "application/vnd.github+json";
                request.Timeout = 8000;
                request.ReadWriteTimeout = 8000;
                request.AllowAutoRedirect = false;
                using (HttpWebResponse response = (HttpWebResponse)request.GetResponse())
                {
                    if (response.StatusCode != HttpStatusCode.OK) throw new InvalidOperationException("更新服务器返回了异常状态，请稍后重试。");
                    if (response.ContentLength > Limit) throw new InvalidOperationException("更新信息过大，已停止读取。");
                    using (Stream stream = response.GetResponseStream())
                    using (MemoryStream data = new MemoryStream())
                    {
                        byte[] buffer = new byte[8192];
                        int count;
                        while ((count = stream.Read(buffer, 0, buffer.Length)) != 0)
                        {
                            if (data.Length + count > Limit) throw new InvalidOperationException("更新信息过大，已停止读取。");
                            data.Write(buffer, 0, count);
                        }
                        return Parse(new UTF8Encoding(false, true).GetString(data.ToArray()), currentVersion);
                    }
                }
            }
            catch (WebException ex)
            {
                HttpWebResponse response = ex.Response as HttpWebResponse;
                bool missing = response != null && response.StatusCode == HttpStatusCode.NotFound;
                if (response != null) response.Dispose();
                throw new InvalidOperationException(missing ? "本仓库尚无可用的正式发布版本。" : "无法连接更新服务器，请检查网络或代理后重试。");
            }
            catch (DecoderFallbackException) { throw new InvalidOperationException("更新服务器返回的文本编码无效。"); }
        }

        internal static ReleaseInfo Parse(string json, string currentVersion)
        {
            try
            {
                if (json == null || Encoding.UTF8.GetByteCount(json) > Limit) throw new FormatException();
                JavaScriptSerializer serializer = new JavaScriptSerializer();
                serializer.MaxJsonLength = Limit;
                Dictionary<string, object> release = serializer.DeserializeObject(json) as Dictionary<string, object>;
                object draft, prerelease, tag, body;
                if (release == null || !release.TryGetValue("draft", out draft) || !(draft is bool) || (bool)draft ||
                    !release.TryGetValue("prerelease", out prerelease) || !(prerelease is bool) || (bool)prerelease ||
                    !release.TryGetValue("tag_name", out tag) || !(tag is string) ||
                    !release.TryGetValue("body", out body) || !(body is string) || String.IsNullOrWhiteSpace((string)body)) throw new FormatException();
                string tagName = (string)tag;
                if (!Regex.IsMatch(tagName, @"\Av[0-9]+\.[0-9]+\.[0-9]+(?:\.[0-9]+)?\z")) throw new FormatException();
                Version latest = Normalize(tagName.Substring(1));
                string current = currentVersion != null && currentVersion.StartsWith("v", StringComparison.Ordinal) ? currentVersion.Substring(1) : currentVersion;
                Version installed = Normalize(current);
                return new ReleaseInfo { HasUpdate = latest > installed, Version = tagName.Substring(1), Notes = (string)body,
                    Url = "https://github.com/Foohi666/Aion2-CN-Foohi/releases/tag/" + Uri.EscapeDataString(tagName) };
            }
            catch (Exception ex)
            {
                if (!(ex is ArgumentException) && !(ex is InvalidOperationException) && !(ex is FormatException) && !(ex is OverflowException)) throw;
                throw new InvalidOperationException("版本或更新信息格式无效，无法检查更新。");
            }
        }

        private static Version Normalize(string text)
        {
            Version value;
            if (text == null || !Regex.IsMatch(text, @"\A[0-9]+\.[0-9]+\.[0-9]+(?:\.[0-9]+)?\z") || !System.Version.TryParse(text, out value)) throw new FormatException();
            return new Version(value.Major, value.Minor, value.Build, Math.Max(0, value.Revision));
        }
    }
}
