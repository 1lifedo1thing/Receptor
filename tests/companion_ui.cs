using System;
using System.IO;
using System.Net;
using System.Reflection;
using System.Text;
using System.Windows.Forms;
using ReceptorDesktop;

// Exercise the actual desktop controls and server through the reported pairing flow.
// No window is shown and no real user preferences are read or written.
static class CompanionUiTest {
    static object Field(CompanionForm form, string name) { return typeof(CompanionForm).GetField(name, BindingFlags.Instance | BindingFlags.NonPublic).GetValue(form); }
    static void Toggle(CompanionForm form) { typeof(CompanionForm).GetMethod("Toggle", BindingFlags.Instance | BindingFlags.NonPublic).Invoke(form, null); }
    static void Check(bool condition) { if (!condition) throw new Exception("Desktop pairing workflow regression."); }
    static string Bootstrap(CompanionServer server) {
        using (WebClient web = new WebClient()) { web.Proxy = null; return web.DownloadString("http://127.0.0.1:" + server.Port + "/v2/pairing?nonce=" + Guid.NewGuid().ToString("N")); }
    }
    [STAThread] static void Main(string[] args) {
        Application.EnableVisualStyles(); Application.SetCompatibleTextRenderingDefault(false);
        using (CompanionForm form = new CompanionForm(args[0])) {
            try {
                ComboBox addresses = (ComboBox)Field(form, "addresses");
                addresses.Items.Clear(); addresses.Items.Add(IPAddress.Loopback); addresses.SelectedIndex = 0;
                CheckBox accept = (CheckBox)Field(form, "accept");
                TextBox code = (TextBox)Field(form, "code"), endpoint = (TextBox)Field(form, "endpoint"), folder = (TextBox)Field(form, "receivePath");
                string shownCode = code.Text; Check(shownCode.Length == 9 && endpoint.Text.Length > 0 && !accept.Checked);
                Toggle(form);
                CompanionServer server = (CompanionServer)Field(form, "server"); string bootstrap = Bootstrap(server);
                Check(accept.Enabled && ((Button)Field(form, "chooseFolder")).Enabled);
                folder.Text = Path.Combine(Path.GetDirectoryName(args[0]), "received"); accept.Checked = true;
                Check(Object.ReferenceEquals(server, Field(form, "server")) && Bootstrap(server) == bootstrap && code.Text == shownCode);
                ConnectionSettings identity = (ConnectionSettings)Field(form, "settings");
                string nonce = Guid.NewGuid().ToString("N"), session = bootstrap.Split('\n')[2];
                byte[] payload = Encoding.UTF8.GetBytes("Device-to-PC workflow test");
                string name = Convert.ToBase64String(Encoding.UTF8.GetBytes("workflow.txt")), digest = CompanionServer.Hash(payload);
                HttpWebRequest upload = (HttpWebRequest)WebRequest.Create("http://127.0.0.1:" + server.Port + "/v2/uploads?nonce=" + nonce);
                upload.Proxy = null; upload.Method = "PUT"; upload.ContentLength = payload.Length; upload.Timeout = 5000; upload.ServicePoint.Expect100Continue = false;
                upload.Headers["X-Receptor-SHA256"] = digest; upload.Headers["X-Receptor-Name"] = name;
                upload.Headers["X-Receptor-Auth"] = CompanionServer.Mac(identity.Key, "PUT\n/v2/uploads\n" + nonce + "\n" + session + "\n" + payload.Length + "\n" + digest + "\n" + name);
                using (Stream output = upload.GetRequestStream()) output.Write(payload, 0, payload.Length);
                using (HttpWebResponse response = (HttpWebResponse)upload.GetResponse()) Check(response.StatusCode == HttpStatusCode.Created);
                Check(File.ReadAllText(Path.Combine(folder.Text, "workflow.txt")) == Encoding.UTF8.GetString(payload));
                Toggle(form); Check(Field(form, "server") == null && code.Text == shownCode && endpoint.Text.Length > 0);
                Toggle(form); Check(code.Text == shownCode && Bootstrap((CompanionServer)Field(form, "server")) != bootstrap);
                Toggle(form);
                Console.WriteLine("PASS: native desktop controls enable receiving without stopping, transfer a file using the same pairing/session, and retain visible credentials across pause/restart");
            } finally {
                CompanionServer active = (CompanionServer)Field(form, "server"); if (active != null) active.Dispose();
            }
        }
    }
}
