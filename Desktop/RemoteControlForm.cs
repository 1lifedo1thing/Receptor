using System;
using System.Collections.Generic;
using System.Drawing;
using System.IO;
using System.Security.Cryptography;
using System.Threading;
using System.Windows.Forms;

namespace ReceptorDesktop {
    sealed class RemoteRow {
        public readonly Dictionary<string,object> Value;
        readonly string label;
        public RemoteRow(Dictionary<string,object> value,string label) { Value=value; this.label=label; }
        public override string ToString() { return label; }
    }
    sealed class RemoteReview : Form {
        public readonly CheckBox Unsigned=new CheckBox {Text="Allow unsigned repositories for this installation",AutoSize=true};
        public RemoteReview(string title,string text,bool install) {
            Text=title; Size=new Size(740,560); MinimumSize=new Size(580,420); StartPosition=FormStartPosition.CenterParent;
            TextBox output=new TextBox {Multiline=true,ReadOnly=true,Dock=DockStyle.Fill,ScrollBars=ScrollBars.Both,WordWrap=false,Font=new Font("Consolas",10),Text=text.Replace("\n",Environment.NewLine)};
            FlowLayoutPanel actions=new FlowLayoutPanel {Dock=DockStyle.Bottom,AutoSize=true,Padding=new Padding(8),FlowDirection=FlowDirection.RightToLeft};
            Button confirm=new Button {Text="Confirm changes",AutoSize=true},cancel=new Button {Text="Cancel",AutoSize=true,DialogResult=DialogResult.Cancel}; Unsigned.Visible=install;
            confirm.Click+=delegate {
                if(Unsigned.Checked && MessageBox.Show(this,"For this installation only, repository signatures will not be required. An untrusted or modified repository could install malicious code as root. Proceed only if you intend to trust the source.","Install unsigned packages?",MessageBoxButtons.YesNo,MessageBoxIcon.Warning)!=DialogResult.Yes)return;
                DialogResult=DialogResult.OK; Close();
            };
            actions.Controls.Add(confirm); actions.Controls.Add(cancel); actions.Controls.Add(Unsigned); Controls.Add(output); Controls.Add(actions); CancelButton=cancel;
        }
    }
    public sealed class RemoteControlForm : Form {
        readonly RemoteBroker broker;
        readonly ComboBox devices=new ComboBox {DropDownStyle=ComboBoxStyle.DropDownList,Dock=DockStyle.Fill};
        readonly Label status=new Label {AutoSize=true,Dock=DockStyle.Bottom,Padding=new Padding(8),MaximumSize=new Size(900,0)};
        readonly ListBox packages=new ListBox {Dock=DockStyle.Fill,HorizontalScrollbar=true};
        readonly ListBox sources=new ListBox {Dock=DockStyle.Fill,HorizontalScrollbar=true};
        readonly ListBox files=new ListBox {Dock=DockStyle.Fill,HorizontalScrollbar=true};
        readonly TextBox search=new TextBox {Width=220};
        readonly TextBox log=new TextBox {Multiline=true,ReadOnly=true,Dock=DockStyle.Fill,ScrollBars=ScrollBars.Both,WordWrap=false,Font=new Font("Consolas",10)};
        readonly TabControl tabs=new TabControl {Dock=DockStyle.Fill};
        readonly System.Windows.Forms.Timer timer=new System.Windows.Forms.Timer {Interval=2000};
        readonly List<Control> controls=new List<Control>();
        volatile bool cancelFile;
        bool busy;
        public RemoteControlForm(RemoteBroker broker) {
            this.broker=broker; Text="Receptor — device management"; Size=new Size(920,650); MinimumSize=new Size(700,500); Font=new Font("Segoe UI",10); StartPosition=FormStartPosition.CenterParent;
            TableLayoutPanel header=new TableLayoutPanel {Dock=DockStyle.Top,AutoSize=true,ColumnCount=1,Padding=new Padding(8)};
            header.Controls.Add(new Label {Text="PC key: "+broker.Fingerprint.Substring(0,16)+"   ·   Compare this with the iPad during setup.",AutoSize=true},0,0); header.Controls.Add(devices,0,1);
            header.Controls.Add(new Label {Text="On the iPad once: Receptor → Desktop → Connect / Refresh → Background desktop access → Enable.\nClose Cydia before package changes. Keep sharing and background access enabled on this PC.",AutoSize=true},0,2);
            TabPage pkg=Page("Packages"),src=Page("Sources"),folder=Page("Files"),logs=Page("Log"); logs.Controls.Add(log);
            FlowLayoutPanel p=Actions(pkg); p.Controls.Add(search); Add(p,"Search",delegate { PackageQuery("search",search.Text); }); Add(p,"Installed",delegate { PackageQuery("installed",null); }); Add(p,"Details",Details); Add(p,"Install / Upgrade…",delegate { Transaction(false); }); Add(p,"Remove…",delegate { Transaction(true); }); pkg.Controls.Add(packages);
            FlowLayoutPanel s=Actions(src); Add(s,"List sources",ListSources); Add(s,"Refresh indexes",delegate { Work(delegate(string device) { ShowLog(Package(device,"refresh")); }); }); Add(s,"Add source…",AddSource); Add(s,"Remove source…",RemoveSource); src.Controls.Add(sources);
            FlowLayoutPanel f=Actions(folder); Add(f,"Refresh files",ListFiles); Add(f,"Upload…",Upload); Add(f,"Download…",Download); Button cancel=new Button {Text="Cancel file transfer",AutoSize=true}; cancel.Click+=delegate {cancelFile=true;}; f.Controls.Add(cancel); folder.Controls.Add(files);
            FlowLayoutPanel l=Actions(logs); Add(l,"Device operation log",delegate {Work(delegate(string device) {ShowLog(Package(device,"last-result"));});}); Add(l,"Respring…",Respring);
            p.SendToBack();s.SendToBack();f.SendToBack();l.SendToBack(); status.MaximumSize=new Size(900,96);
            Controls.Add(tabs); Controls.Add(header); Controls.Add(status); devices.SelectedIndexChanged+=delegate { if(!busy) SetStatus("Connected devices are listed above. Choose an action; package changes require a reviewed desktop confirmation."); };
            timer.Tick+=delegate { RefreshDevices(); }; timer.Start(); FormClosed+=delegate { cancelFile=true; timer.Stop(); timer.Dispose(); }; RefreshDevices();
        }
        TabPage Page(string title) { TabPage page=new TabPage(title); tabs.TabPages.Add(page); return page; }
        FlowLayoutPanel Actions(TabPage page) { FlowLayoutPanel panel=new FlowLayoutPanel {Dock=DockStyle.Top,AutoSize=true,Padding=new Padding(4)}; page.Controls.Add(panel); return panel; }
        void Add(FlowLayoutPanel panel,string text,Action action) { Button button=new Button {Text=text,AutoSize=true}; button.Click+=delegate {if(!busy)action();}; panel.Controls.Add(button); controls.Add(button); }
        void RefreshDevices() {
            if(busy)return; string selected=(devices.SelectedItem as RemoteDevice)==null?null:((RemoteDevice)devices.SelectedItem).Id;
            RemoteDevice[] current=broker.Devices(); devices.BeginUpdate(); devices.Items.Clear(); foreach(RemoteDevice device in current) devices.Items.Add(device);
            for(int i=0;i<devices.Items.Count;i++)if(((RemoteDevice)devices.Items[i]).Id==selected)devices.SelectedIndex=i;
            if(devices.SelectedIndex<0 && devices.Items.Count>0)devices.SelectedIndex=0; devices.EndUpdate();
            if(current.Length==0)SetStatus("Waiting for a device with background access enabled. The iPad must be powered on and reachable on Wi-Fi; locked-device Wi-Fi behavior depends on iOS and power state.");
        }
        static string String(Dictionary<string,object> data,string key) { object value; return data.TryGetValue(key,out value) && value!=null?value.ToString():""; }
        string SelectedDevice() { RemoteDevice selected=devices.SelectedItem as RemoteDevice; if(selected==null)throw new IOException("No background device is connected yet. Complete the one-time iPad setup first."); return selected.Id; }
        void UI(Action action) { if(IsDisposed || !IsHandleCreated)return; try {Invoke(action);} catch(InvalidOperationException) {} }
        void SetStatus(string message) { status.Text=message.Length>400?message.Substring(0,400)+"… See Log for full output.":message; }
        void ShowLog(Dictionary<string,object> result) {
            string error=String(result,"error"),output=String(result,"output"); object raw;
            if(error.Length>0) throw new IOException(error);
            if(result.TryGetValue("status",out raw) && Convert.ToInt64(raw)!=0)throw new IOException(output.Length>0?output:"The device command failed.");
            UI(delegate {log.Text=output.Replace("\n",Environment.NewLine); SetStatus("Operation completed. Read the result; package refreshes may contain warnings. Respring only if required by the package.");});
        }
        Dictionary<string,object> Request(string device,Dictionary<string,object> request) {
            Dictionary<string,object> result=broker.Execute(device,request,900); string error=String(result,"error"); if(error.Length>0)throw new IOException(error);
            object raw; if(result.TryGetValue("status",out raw) && Convert.ToInt64(raw)!=0)throw new IOException(String(result,"output")); return result;
        }
        Dictionary<string,object> Package(string device,params string[] arguments) { return Request(device,new Dictionary<string,object>{{"op","packages"},{"args",arguments}}); }
        Dictionary<string,object> FileRequest(string device,string action,params object[] pairs) { Dictionary<string,object> request=new Dictionary<string,object>{{"op","files"},{"action",action}}; for(int i=0;i<pairs.Length;i+=2)request[(string)pairs[i]]=pairs[i+1]; return Request(device,request); }
        void Work(Action<string> action) {
            string target;
            try {target=SelectedDevice();} catch(Exception ex) {MessageBox.Show(this,ex.Message,"Device unavailable");return;}
            busy=true; cancelFile=false; devices.Enabled=false; foreach(Control control in controls)control.Enabled=false; SetStatus("Working on device "+target.Substring(0,8)+"… Package operations cannot be cancelled halfway through.");
            ThreadPool.QueueUserWorkItem(delegate {
                try {action(target);} catch(Exception ex) {UI(delegate {log.Text=ex.Message; SetStatus(ex.Message);});}
                finally {UI(delegate {busy=false; devices.Enabled=true; foreach(Control control in controls)control.Enabled=true;});}
            });
        }
        void Fill(ListBox list,Dictionary<string,object> result,string kind) {
            object raw; List<object> items=result.TryGetValue("items",out raw)?raw as List<object>:null; if(items==null)throw new IOException("The device returned no list.");
            List<RemoteRow> rows=new List<RemoteRow>();
            foreach(object item in items) { Dictionary<string,object> data=item as Dictionary<string,object>; if(data==null)continue;
                string label=kind=="sources"?String(data,"line"):kind=="files"?String(data,"name")+"  ("+String(data,"size")+" bytes)":(String(data,"Name").Length>0?String(data,"Name"):String(data,"Package"))+"  "+String(data,"Version")+" — "+String(data,"Description").Split('\n')[0]; rows.Add(new RemoteRow(data,label));
            }
            UI(delegate {list.BeginUpdate();list.Items.Clear();foreach(RemoteRow row in rows)list.Items.Add(row);list.EndUpdate();SetStatus(rows.Count+" item(s). Source/package changes and file transfers remain scoped to the selected device.");});
        }
        void PackageQuery(string operation,string value) { Work(delegate(string device) {Fill(packages,value==null?Package(device,operation):Package(device,operation,value),"packages");}); }
        void ListSources() {Work(delegate(string device) {Fill(sources,Package(device,"sources"),"sources");});}
        void ListFiles() {Work(delegate(string device) {Fill(files,FileRequest(device,"list"),"files");});}
        RemoteRow Row(ListBox list) {RemoteRow row=list.SelectedItem as RemoteRow; if(row==null)MessageBox.Show(this,"Select an item first.","Receptor");return row;}
        void Details() {RemoteRow row=Row(packages); if(row==null)return; Work(delegate(string device) {Dictionary<string,object> result=Package(device,"details",String(row.Value,"Package")); ShowLog(result); UI(delegate {tabs.SelectedIndex=3;});});}
        void Transaction(bool remove) {
            RemoteRow row=Row(packages); if(row==null)return; string identifier=String(row.Value,"Package");
            Work(delegate(string device) {
                Dictionary<string,object> plan=Package(device,remove?"plan-remove":"plan-install",identifier); string token=String(plan,"token"); if(token.Length!=64)throw new IOException("The device returned no valid transaction preview.");
                bool approved=false,unsigned=false;
                UI(delegate {using(RemoteReview review=new RemoteReview((remove?"Remove ":"Install / upgrade ")+identifier+" · device "+device.Substring(0,8),String(plan,"output"),!remove)) {approved=review.ShowDialog(this)==DialogResult.OK;unsigned=review.Unsigned.Checked;}});
                if(!approved) {UI(delegate {SetStatus("Cancelled; the reviewed transaction was not applied.");});return;}
                Dictionary<string,object> result=Package(device,remove?"apply-remove":unsigned?"apply-unsigned-install":"apply-install",identifier,token); ShowLog(result); Fill(packages,Package(device,"installed"),"packages");
            });
        }
        static string Input(IWin32Window parent,string title,string hint) {
            using(Form dialog=new Form {Text=title,Size=new Size(560,170),StartPosition=FormStartPosition.CenterParent,MinimizeBox=false,MaximizeBox=false,FormBorderStyle=FormBorderStyle.FixedDialog}) {
                TextBox input=new TextBox {Dock=DockStyle.Top,Text=hint}; Button okay=new Button {Text="Add",DialogResult=DialogResult.OK,Dock=DockStyle.Bottom}; dialog.Controls.Add(input);dialog.Controls.Add(okay);dialog.AcceptButton=okay;return dialog.ShowDialog(parent)==DialogResult.OK?input.Text:null;
            }
        }
        void AddSource() {string url=Input(this,"Add flat HTTP(S) repository","https://");if(url==null)return;Work(delegate(string device) {ShowLog(Package(device,"source-add",url));Fill(sources,Package(device,"sources"),"sources");});}
        void RemoveSource() {RemoteRow row=Row(sources);if(row==null)return;if(MessageBox.Show(this,"Remove "+String(row.Value,"name")+"? Installed packages stay. All distributions of a Cydia-managed URI are removed together.","Remove repository?",MessageBoxButtons.YesNo,MessageBoxIcon.Question)!=DialogResult.Yes)return;Work(delegate(string device) {ShowLog(Package(device,"source-remove",String(row.Value,"id")));Fill(sources,Package(device,"sources"),"sources");});}
        void Respring() {if(MessageBox.Show(this,"Restart the selected device's Home/lock-screen interface? Finish transfers and close package managers first. This is not a reboot.","Respring device?",MessageBoxButtons.YesNo,MessageBoxIcon.Question)!=DialogResult.Yes)return;Work(delegate(string device) {ShowLog(Request(device,new Dictionary<string,object>{{"op","respring"}}));});}
        void CheckCancelled() {if(cancelFile)throw new OperationCanceledException("File transfer cancelled. A file already fully delivered may remain.");}
        void Upload() {
            using(OpenFileDialog dialog=new OpenFileDialog {Title="Send a file to Receptor",Filter="All files (*.*)|*.*"}) {
                if(dialog.ShowDialog(this)!=DialogResult.OK)return; string source=dialog.FileName;
                Work(delegate(string device) {
                    bool started=false;
                    try {using(FileStream input=new FileStream(source,FileMode.Open,FileAccess.Read,FileShare.Read)) {
                        if(input.Length>2147483647L)throw new IOException("Choose a file no larger than 2 GB.");
                        string digest;using(SHA256 sha=SHA256.Create())digest=CompanionServer.Hex(sha.ComputeHash(input));input.Position=0;CheckCancelled();
                        string upload=String(FileRequest(device,"write-start","name",Path.GetFileName(source),"size",input.Length,"sha256",digest),"id");started=true;
                        byte[] buffer=new byte[65536];long offset=0;int count;
                        while((count=input.Read(buffer,0,buffer.Length))>0) {CheckCancelled();byte[] chunk=new byte[count];Buffer.BlockCopy(buffer,0,chunk,0,count);Dictionary<string,object> reply=FileRequest(device,"write-chunk","id",upload,"offset",offset,"data",chunk);offset+=count;if(Convert.ToInt64(reply["offset"])!=offset)throw new IOException("Upload offset mismatch.");long progress=offset;UI(delegate {SetStatus("Sent "+progress+" / "+input.Length+" bytes…");});}
                        CheckCancelled();Dictionary<string,object> finished=FileRequest(device,"write-finish","id",upload);started=false;UI(delegate {SetStatus("Saved and verified on the device as "+String(finished,"saved")+". Transfers do not automatically install packages.");});
                    }} finally {if(started)try {FileRequest(device,"abort");}catch(IOException){} }
                    Fill(files,FileRequest(device,"list"),"files");
                });
            }
        }
        void Download() {
            RemoteRow row=Row(files);if(row==null)return;string name=String(row.Value,"name");
            using(SaveFileDialog dialog=new SaveFileDialog {Title="Save file from Receptor",FileName=Path.GetFileName(name),OverwritePrompt=false}) {
                if(dialog.ShowDialog(this)!=DialogResult.OK)return;string destination=dialog.FileName;
                if(File.Exists(destination)) {MessageBox.Show(this,"Choose an unused filename; existing files are preserved.");return;}
                Work(delegate(string device) {
                    Dictionary<string,object> info=FileRequest(device,"info","name",name);long size=Convert.ToInt64(info["size"]);string token=String(info,"token"),digest=String(info,"sha256");
                    string partial=destination+".receptor-"+Guid.NewGuid().ToString("N")+".part";
                    try {using(FileStream output=new FileStream(partial,FileMode.CreateNew,FileAccess.ReadWrite,FileShare.None)) {
                        long offset=0;while(offset<size) {CheckCancelled();Dictionary<string,object> reply=FileRequest(device,"read","name",name,"token",token,"offset",offset,"length",65536);byte[] data=reply["data"] as byte[];if(data==null || data.Length==0 || data.Length>65536 || offset+data.Length>size || Convert.ToInt64(reply["offset"])!=offset)throw new IOException("Invalid download chunk.");output.Write(data,0,data.Length);offset+=data.Length;long progress=offset;UI(delegate {SetStatus("Received "+progress+" / "+size+" bytes…");});}
                        output.Flush(true);output.Position=0;using(SHA256 sha=SHA256.Create())if(!RemoteCrypto.Equal(CompanionServer.Hex(sha.ComputeHash(output)),digest))throw new IOException("Download SHA-256 verification failed.");
                    }CheckCancelled();File.Move(partial,destination);UI(delegate {SetStatus("Downloaded and verified "+name+".");});}
                    finally {if(File.Exists(partial))File.Delete(partial);}
                });
            }
        }
    }
}
