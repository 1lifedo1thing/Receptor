using System;
using System.Drawing;
using System.IO;
using System.Net;
using System.Net.NetworkInformation;
using System.Net.Sockets;
using System.Threading;
using System.Windows.Forms;

namespace ReceptorDesktop {
    static class Program {
        [STAThread] static void Main() {
            Application.EnableVisualStyles(); Application.SetCompatibleTextRenderingDefault(false);
            Application.Run(new CompanionForm());
        }
    }
    sealed class CompanionForm : Form {
        readonly ComboBox addresses = new ComboBox { DropDownStyle = ComboBoxStyle.DropDownList, Dock = DockStyle.Fill };
        readonly Button start = new Button { Text = "Start sharing", AutoSize = true };
        readonly Button add = new Button { Text = "Add DEBs…", AutoSize = true, Enabled = false };
        readonly TextBox endpoint = new TextBox { ReadOnly = true, Dock = DockStyle.Fill };
        readonly TextBox code = new TextBox { ReadOnly = true, Dock = DockStyle.Fill };
        readonly ListBox files = new ListBox { Dock = DockStyle.Fill, HorizontalScrollbar = true };
        readonly Label status = new Label { Text = "Choose your Wi-Fi address and start sharing.", AutoSize = true, Dock = DockStyle.Fill };
        CompanionServer server;
        bool adding;
        public CompanionForm() {
            Text = "Receptor Desktop"; ClientSize = new Size(650, 480); MinimumSize = new Size(550, 440);
            Font = new Font("Segoe UI", 10); StartPosition = FormStartPosition.CenterScreen;
            TableLayoutPanel layout = new TableLayoutPanel { Dock = DockStyle.Fill, Padding = new Padding(18), ColumnCount = 2, RowCount = 9 };
            layout.ColumnStyles.Add(new ColumnStyle(SizeType.Absolute, 130)); layout.ColumnStyles.Add(new ColumnStyle(SizeType.Percent, 100));
            for (int i = 0; i < 9; i++) layout.RowStyles.Add(new RowStyle(i == 7 ? SizeType.Percent : SizeType.AutoSize, i == 7 ? 100 : 0));
            Label intro = new Label { Text = "Send DEBs from this PC to Receptor 1.3.0 or later.\nKeep both devices on the same Wi-Fi network.", AutoSize = true, Margin = new Padding(0,0,0,14) };
            layout.Controls.Add(intro,0,0); layout.SetColumnSpan(intro,2);
            layout.Controls.Add(new Label { Text = "PC address", AutoSize = true },0,1); layout.Controls.Add(addresses,1,1);
            layout.Controls.Add(start,1,2);
            layout.Controls.Add(new Label { Text = "Address", AutoSize = true },0,3); layout.Controls.Add(endpoint,1,3);
            layout.Controls.Add(new Label { Text = "Pairing code", AutoSize = true },0,4); layout.Controls.Add(code,1,4);
            Label instruction = new Label { Text = "In Receptor, tap Desktop and enter the address and code above.\nTransfers use authenticated local HTTP; file contents are not encrypted.\nOnly files you add here are shared. Stop sharing to revoke this code.", AutoSize = true, Margin = new Padding(0,10,0,10) };
            layout.Controls.Add(instruction,0,5); layout.SetColumnSpan(instruction,2);
            layout.Controls.Add(add,0,6); layout.Controls.Add(files,0,7); layout.SetColumnSpan(files,2);
            status.Margin = new Padding(0,10,0,0); layout.Controls.Add(status,0,8); layout.SetColumnSpan(status,2);
            Controls.Add(layout);
            foreach (NetworkInterface nic in NetworkInterface.GetAllNetworkInterfaces()) {
                if (nic.OperationalStatus != OperationalStatus.Up || nic.NetworkInterfaceType == NetworkInterfaceType.Loopback) continue;
                foreach (UnicastIPAddressInformation ip in nic.GetIPProperties().UnicastAddresses) {
                    if (ip.Address.AddressFamily == AddressFamily.InterNetwork && IsPrivate(ip.Address)) addresses.Items.Add(ip.Address);
                }
            }
            if (addresses.Items.Count > 0) addresses.SelectedIndex = 0;
            else { start.Enabled = false; status.Text = "Connect to a private Wi-Fi network, then reopen Receptor Desktop."; }
            start.Click += delegate { Toggle(); }; add.Click += delegate { AddFiles(); };
            FormClosing += delegate { if (server != null) { server.Dispose(); server = null; } };
        }
        static bool IsPrivate(IPAddress ip) {
            byte[] b=ip.GetAddressBytes(); return b[0]==10 || (b[0]==172 && b[1]>=16 && b[1]<=31) || (b[0]==192 && b[1]==168) || (b[0]==169 && b[1]==254);
        }
        void SetStatus(string text) {
            if (IsDisposed || !IsHandleCreated) return;
            try { BeginInvoke((Action)delegate { status.Text = text; }); } catch (InvalidOperationException) { }
        }
        void Toggle() {
            if (server != null) {
                CompanionServer previous = server; server = null; previous.Dispose();
                endpoint.Clear(); code.Clear(); files.Items.Clear();
                start.Text = "Start sharing"; addresses.Enabled = true; add.Enabled = false;
                status.Text = "Sharing stopped. The old pairing code no longer works."; return;
            }
            try {
                IPAddress ip = (IPAddress)addresses.SelectedItem;
                server = new CompanionServer(ip, 0); server.Status += SetStatus;
                endpoint.Text = ip + ":" + server.Port;
                string k = server.Code; code.Text = k.Substring(0,5)+"-"+k.Substring(5,5)+"-"+k.Substring(10,5)+"-"+k.Substring(15,5);
                addresses.Enabled = false; start.Text = "Stop sharing"; add.Enabled = true;
                status.Text = "Add DEBs, then connect in Receptor. If Windows asks, allow access on private networks.";
            } catch (Exception ex) { MessageBox.Show(this, ex.Message, "Could not start sharing", MessageBoxButtons.OK, MessageBoxIcon.Error); }
        }
        void AddFiles() {
            if (server == null || adding) return;
            using (OpenFileDialog dialog = new OpenFileDialog { Filter = "Debian packages (*.deb)|*.deb", Multiselect = true, Title = "Choose DEBs to send" }) {
                if (dialog.ShowDialog(this) != DialogResult.OK) return;
                string[] paths = dialog.FileNames; CompanionServer target = server;
                adding = true; add.Enabled = false; start.Enabled = false; status.Text = "Preparing files…";
                ThreadPool.QueueUserWorkItem(delegate {
                    try {
                        foreach (string path in paths) {
                            SharedPackage item = target.Add(path);
                            if (!IsDisposed && IsHandleCreated) BeginInvoke((Action)delegate { if (server == target) files.Items.Add(item); });
                        }
                        SetStatus("Ready. Tap Connect / Refresh in Receptor to see these DEBs.");
                    } catch (Exception ex) { SetStatus("Could not add file: " + ex.Message); }
                    finally {
                        if (!IsDisposed && IsHandleCreated) {
                            try { BeginInvoke((Action)delegate { adding = false; start.Enabled = true; add.Enabled = server != null; }); }
                            catch (InvalidOperationException) { }
                        }
                    }
                });
            }
        }
    }
}
