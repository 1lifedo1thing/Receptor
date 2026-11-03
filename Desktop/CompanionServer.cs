using System;
using System.Collections.Generic;
using System.IO;
using System.Net;
using System.Net.Sockets;
using System.Security.Cryptography;
using System.Text;
using System.Text.RegularExpressions;
using System.Threading;
using System.Xml;

namespace ReceptorDesktop {
    public sealed class SharedFile : IDisposable {
        public readonly string Id, Name, Digest;
        public readonly long Size;
        private readonly FileStream snapshot;
        private readonly string path;
        public SharedFile(string source, string directory, Func<bool> cancelled) {
            Name = Path.GetFileName(source);
            XmlConvert.VerifyXmlChars(Name);
            Id = Guid.NewGuid().ToString("N");
            path = Path.Combine(directory, Id + ".snapshot");
            try {
                using (FileStream input = new FileStream(source, FileMode.Open, FileAccess.Read, FileShare.Read)) {
                    Size = input.Length;
                    if (Size > 2147483647L) throw new IOException("Files must be no larger than 2 GB.");
                    using (FileStream output = new FileStream(path, FileMode.CreateNew, FileAccess.Write, FileShare.None))
                    using (SHA256 sha = SHA256.Create()) {
                        byte[] buffer = new byte[65536]; int count;
                        while ((count = input.Read(buffer, 0, buffer.Length)) > 0) {
                            if (cancelled()) throw new IOException("Sharing has stopped.");
                            output.Write(buffer, 0, count);
                            sha.TransformBlock(buffer, 0, count, buffer, 0);
                        }
                        sha.TransformFinalBlock(new byte[0], 0, 0); Digest = CompanionServer.Hex(sha.Hash);
                    }
                }
                // Keep the immutable snapshot open, denying writes/deletion while it is shared.
                snapshot = new FileStream(path, FileMode.Open, FileAccess.Read, FileShare.Read);
            } catch { if (snapshot != null) snapshot.Dispose(); if (File.Exists(path)) File.Delete(path); throw; }
        }
        public void Send(Stream output) {
            lock (snapshot) { snapshot.Position = 0; snapshot.CopyTo(output); }
        }
        public void Dispose() { snapshot.Dispose(); File.Delete(path); }
        public override string ToString() { return Name + "  (" + (Size / 1024.0 / 1024.0).ToString("0.00") + " MB)"; }
    }

    public sealed class CompanionServer : IDisposable {
        private readonly TcpListener listener;
        private readonly string key;
        private readonly ConnectionSettings identity;
        private readonly string session;
        private readonly object gate = new object();
        private readonly List<SharedFile> packages = new List<SharedFile>();
        private readonly HashSet<TcpClient> clients = new HashSet<TcpClient>();
        private readonly HashSet<string> nonces = new HashSet<string>();
        private readonly string staging = Path.Combine(Path.GetTempPath(), "Receptor-" + Guid.NewGuid().ToString("N"));
        private volatile bool stopped;
        private int pendingAdds;
        private volatile string receiveFolder;
        private readonly SemaphoreSlim receiving = new SemaphoreSlim(1, 1);
        private int receivedCount;
        public event Action<string> Status;
        public event Action<string> FileReceived;
        public readonly RemoteBroker Remote;
        public string Code { get { return identity.Code; } }
        public int Port { get { return ((IPEndPoint)listener.LocalEndpoint).Port; } }
        public CompanionServer(IPAddress address, int port, ConnectionSettings settings) : this(address, port, settings, null) { }
        public CompanionServer(IPAddress address, int port, ConnectionSettings settings, ReceiveOptions incoming) : this(address,port,settings,incoming,null) { }
        public CompanionServer(IPAddress address, int port, ConnectionSettings settings, ReceiveOptions incoming, RemoteIdentity remoteIdentity) {
            identity = settings; key = settings.Key;
            if(remoteIdentity!=null) Remote=new RemoteBroker(remoteIdentity,key);
            receiveFolder = incoming != null && incoming.Enabled ? Path.GetFullPath(incoming.Folder) : null;
            byte[] random = new byte[16];
            using (RandomNumberGenerator rng = RandomNumberGenerator.Create()) rng.GetBytes(random);
            session = Hex(random);
            Directory.CreateDirectory(staging);
            listener = new TcpListener(address, port);
            try { listener.Start(8); } catch { Directory.Delete(staging); throw; }
            Thread thread = new Thread(AcceptLoop); thread.IsBackground = true; thread.Start();
        }
        public SharedFile Add(string path) {
            lock (gate) {
                if (stopped) throw new IOException("Sharing has stopped.");
                if (packages.Count + pendingAdds >= 32) throw new IOException("Share up to 32 files per session.");
                pendingAdds++;
            }
            SharedFile item = null;
            try {
                item = new SharedFile(path, staging, delegate { return stopped; });
                lock (gate) { if (stopped) throw new IOException("Sharing has stopped."); packages.Add(item); }
                return item;
            } catch { if (item != null) item.Dispose(); throw; }
            finally {
                lock (gate) { pendingAdds--; if (stopped && pendingAdds == 0) TryDeleteDirectory(); }
            }
        }
        public void ConfigureReceiving(ReceiveOptions incoming) {
            string folder = incoming != null && incoming.Enabled ? Path.GetFullPath(incoming.Folder) : null;
            lock (gate) {
                if (stopped) throw new IOException("Sharing has stopped.");
                receiveFolder = folder;
            }
        }
        private void AcceptLoop() {
            while (!stopped) {
                TcpClient client;
                try { client = listener.AcceptTcpClient(); } catch (SocketException) { break; } catch (ObjectDisposedException) { break; }
                lock (gate) {
                    if (stopped || clients.Count >= 12) { client.Close(); continue; }
                    clients.Add(client);
                }
                ThreadPool.QueueUserWorkItem(delegate { Handle(client); });
            }
        }
        public static string Hex(byte[] bytes) { return BitConverter.ToString(bytes).Replace("-", "").ToLowerInvariant(); }
        public static string Hash(byte[] bytes) { using (SHA256 sha = SHA256.Create()) return Hex(sha.ComputeHash(bytes)); }
        public static string Mac(string key, string text) {
            using (HMACSHA256 hmac = new HMACSHA256(Encoding.ASCII.GetBytes(key)))
                return Hex(hmac.ComputeHash(Encoding.UTF8.GetBytes(text)));
        }
        private static bool Equal(string a, string b) {
            if (a == null || b == null || a.Length != b.Length) return false;
            int different = 0; for (int i = 0; i < a.Length; i++) different |= a[i] ^ b[i];
            return different == 0;
        }
        private byte[] Manifest() {
            using (MemoryStream buffer = new MemoryStream()) {
                using (XmlWriter xml = XmlWriter.Create(buffer, new XmlWriterSettings { Encoding = new UTF8Encoding(false), CloseOutput = false })) {
                    xml.WriteStartDocument(); xml.WriteStartElement("plist"); xml.WriteAttributeString("version", "1.0");
                    xml.WriteStartElement("dict"); xml.WriteElementString("key", "protocol"); xml.WriteElementString("integer", "2");
                    xml.WriteElementString("key", "files"); xml.WriteStartElement("array");
                    lock (gate) foreach (SharedFile item in packages) {
                        xml.WriteStartElement("dict");
                        Field(xml, "id", "string", item.Id); Field(xml, "name", "string", item.Name);
                        Field(xml, "size", "integer", item.Size.ToString(System.Globalization.CultureInfo.InvariantCulture));
                        Field(xml, "sha256", "string", item.Digest); xml.WriteEndElement();
                    }
                    xml.WriteEndElement();
                    xml.WriteElementString("key", "accepts_uploads"); xml.WriteStartElement(receiveFolder != null ? "true" : "false"); xml.WriteEndElement();
                    if(Remote!=null && Remote.Enabled) Field(xml,"remote_public_key","string",Remote.PublicKey);
                    xml.WriteEndElement(); xml.WriteEndElement(); xml.WriteEndDocument();
                }
                return buffer.ToArray();
            }
        }
        private static void Field(XmlWriter xml, string key, string type, string value) {
            xml.WriteElementString("key", key); xml.WriteElementString(type, value);
        }
        private static string ReadLine(Stream input, ref int remaining) {
            StringBuilder line = new StringBuilder(); int previous = -1;
            while (--remaining >= 0) {
                int value = input.ReadByte(); if (value < 0) throw new IOException("Incomplete request.");
                if (value == 10 && previous == 13) return line.ToString(0, line.Length - 1);
                if (value > 126 || (value < 32 && value != 13)) throw new IOException("Invalid request.");
                line.Append((char)value); previous = value;
            }
            throw new IOException("Request too large.");
        }
        private static void Header(Stream stream, int code, long size, string auth, string contentType) {
            string text = "HTTP/1.1 " + code + (code == 200 ? " OK" : code == 201 ? " Created" : " Rejected") + "\r\nConnection: close\r\nCache-Control: no-store\r\nContent-Type: " + contentType +
                "\r\nContent-Length: " + size + "\r\n" + (auth == null ? "" : "X-Receptor-Auth: " + auth + "\r\n") + "\r\n";
            byte[] bytes = Encoding.ASCII.GetBytes(text); stream.Write(bytes, 0, bytes.Length);
        }
        private void Handle(TcpClient client) {
            try {
                client.ReceiveTimeout = 10000; client.SendTimeout = 30000;
                using (NetworkStream stream = client.GetStream()) {
                    int remaining = 8192;
                    string request = ReadLine(stream, ref remaining);
                    Dictionary<string,string> headers = new Dictionary<string,string>(StringComparer.OrdinalIgnoreCase);
                    for (;;) {
                        string line = ReadLine(stream, ref remaining); if (line.Length == 0) break;
                        int colon = line.IndexOf(':'); if (colon < 1) throw new IOException("Invalid header.");
                        string name = line.Substring(0, colon);
                        if (headers.ContainsKey(name)) throw new IOException("Duplicate header.");
                        headers.Add(name, line.Substring(colon + 1).Trim());
                    }
                    if(request=="POST /v3/control HTTP/1.1" || request=="POST /v3/control HTTP/1.0") { HandleRemote(stream,headers); return; }
                    Match upload = Regex.Match(request, @"^PUT /v2/uploads\?nonce=([a-f0-9]{32}) HTTP/1\.[01]$");
                    if (upload.Success) { ReceiveUpload(client, stream, headers, upload.Groups[1].Value); return; }
                    Match match = Regex.Match(request, @"^GET (/v2/pairing|/v2/manifest|/v2/files/[a-f0-9]{32})\?nonce=([a-f0-9]{32}) HTTP/1\.[01]$");
                    string auth;
                    if (!match.Success || headers.ContainsKey("Transfer-Encoding") ||
                        (headers.ContainsKey("Content-Length") && headers["Content-Length"] != "0")) {
                        Header(stream, 403, 0, null, "text/plain"); return;
                    }
                    string route = match.Groups[1].Value, nonce = match.Groups[2].Value;
                    if (route == "/v2/pairing") {
                        // Public salt and fresh server session; the subsequent manifest must authenticate.
                        byte[] info = Encoding.ASCII.GetBytes("2\n" + identity.Salt + "\n" + session);
                        Header(stream, 200, info.Length, null, "text/plain"); stream.Write(info, 0, info.Length); return;
                    }
                    if (
                        !headers.TryGetValue("X-Receptor-Auth", out auth) ||
                        !Equal(Mac(key, "GET\n" + route + "\n" + nonce + "\n" + session), auth)) {
                        Header(stream, 403, 0, null, "text/plain"); return;
                    }
                    lock (gate) {
                        // Bound memory without re-enabling old captured requests in a session.
                        if (nonces.Count >= 4096 || !nonces.Add(nonce)) { Header(stream, 409, 0, null, "text/plain"); return; }
                    }
                    if (route == "/v2/manifest") {
                        byte[] body = Manifest();
                        Header(stream, 200, body.Length, Mac(key, "response\n" + nonce + "\n" + Hash(body) + "\n" + session), "application/x-plist");
                        stream.Write(body, 0, body.Length); Notify("Connected. Choose a file in Receptor on your iPad.");
                    } else {
                        SharedFile item;
                        lock (gate) item = packages.Find(delegate(SharedFile p) { return p.Id == route.Substring(10); });
                        if (item == null) { Header(stream, 404, 0, null, "text/plain"); return; }
                        Notify("Sending " + item.Name + "…");
                        Header(stream, 200, item.Size, Mac(key, "response\n" + nonce + "\n" + item.Digest + "\n" + session), "application/octet-stream");
                        item.Send(stream);
                        Notify("Sent " + item.Name + ". Open the file in Receptor on your device. Installation is a separate on-device action.");
                    }
                }
            } catch (IOException) { } catch (SocketException) { } catch (ObjectDisposedException) { }
            finally { client.Close(); lock (gate) clients.Remove(client); }
        }
        private static string IncomingName(string encoded) {
            if (encoded == null || encoded.Length > 1400 || !Regex.IsMatch(encoded, @"^[A-Za-z0-9+/]+={0,2}$")) return null;
            string name;
            try { name = new UTF8Encoding(false, true).GetString(Convert.FromBase64String(encoded)); }
            catch (FormatException) { return null; } catch (DecoderFallbackException) { return null; }
            if (name.Length == 0 || name.Length > 255 || name == "." || name == ".." || name.IndexOfAny(new char[] { '/', '\\' }) >= 0) return null;
            foreach (char c in name) if (Char.IsControl(c)) return null;
            foreach (char c in Path.GetInvalidFileNameChars()) name = name.Replace(c, '_');
            name = name.TrimEnd(' ', '.').TrimStart(' ');
            if (name.Length == 0) name = "File";
            string device = name.Split('.')[0].TrimEnd(' ');
            if (Regex.IsMatch(device, @"^(CON|PRN|AUX|NUL|CONIN\$|CONOUT\$|COM[1-9¹²³]|LPT[1-9¹²³])$", RegexOptions.IgnoreCase)) name = "_" + name;
            if (name.Length > 180) {
                string extension = Path.GetExtension(name); if (extension.Length > 24) extension = "";
                int count = 180 - extension.Length;
                if (Char.IsHighSurrogate(name[count - 1])) count--;
                name = name.Substring(0, count) + extension;
            }
            return name;
        }
        void HandleRemote(Stream stream, Dictionary<string,string> headers) {
            try {
                string lengthText,id,nonce,sealedSeed,enrollment,auth; int length;
                if(Remote==null || !Remote.Enabled || headers.ContainsKey("Transfer-Encoding") || !headers.TryGetValue("Content-Length",out lengthText) ||
                    !Regex.IsMatch(lengthText,@"^[1-9][0-9]{1,7}$") || !Int32.TryParse(lengthText,out length) || length>RemoteCrypto.MaximumFrame ||
                    !headers.TryGetValue("X-RC-Device",out id) || !headers.TryGetValue("X-RC-Nonce",out nonce) ||
                    !headers.TryGetValue("X-RC-Sealed",out sealedSeed) || !headers.TryGetValue("X-RC-Enrollment",out enrollment) || !headers.TryGetValue("X-RC-Auth",out auth)) { Header(stream,403,0,null,"text/plain"); return; }
                byte[] frame=new byte[length]; int offset=0; while(offset<length) { int count=stream.Read(frame,offset,length-offset); if(count<=0) throw new IOException("Incomplete remote frame."); offset+=count; }
                string responseAuth; byte[] output=Remote.Handle(id,nonce,sealedSeed,enrollment,auth,frame,out responseAuth);
                Header(stream,200,output.Length,responseAuth,"application/octet-stream"); stream.Write(output,0,output.Length);
            } catch(System.Security.Cryptography.CryptographicException) { Header(stream,403,0,null,"text/plain"); }
            catch(FormatException) { Header(stream,403,0,null,"text/plain"); }
            catch(OverflowException) { Header(stream,403,0,null,"text/plain"); }
            catch(System.Xml.XmlException) { Header(stream,403,0,null,"text/plain"); }
            catch(IOException) { Header(stream,403,0,null,"text/plain"); }
        }
        private void ReceiveUpload(TcpClient client, Stream stream, Dictionary<string,string> headers, string nonce) {
            // An active upload keeps its chosen destination; changes apply to new requests.
            string destinationFolder = receiveFolder;
            string lengthText, digest, encoded, auth;
            long length;
            if (destinationFolder == null) { Header(stream, 403, 0, null, "text/plain"); return; }
            if (headers.ContainsKey("Transfer-Encoding") || !headers.TryGetValue("Content-Length", out lengthText) ||
                !Regex.IsMatch(lengthText, @"^(0|[1-9][0-9]{0,9})$") || !Int64.TryParse(lengthText, out length) || length > 2147483647L ||
                !headers.TryGetValue("X-Receptor-SHA256", out digest) || !Regex.IsMatch(digest, @"^[a-f0-9]{64}$") ||
                !headers.TryGetValue("X-Receptor-Name", out encoded) || !headers.TryGetValue("X-Receptor-Auth", out auth) ||
                !Equal(Mac(key, "PUT\n/v2/uploads\n" + nonce + "\n" + session + "\n" + lengthText + "\n" + digest + "\n" + encoded), auth)) {
                Header(stream, 403, 0, null, "text/plain"); return;
            }
            string name = IncomingName(encoded);
            if (name == null) { Header(stream, 400, 0, null, "text/plain"); return; }
            lock (gate) {
                if (nonces.Count >= 4096 || !nonces.Add(nonce)) { Header(stream, 409, 0, null, "text/plain"); return; }
                if (receivedCount >= 32) { Header(stream, 429, 0, null, "text/plain"); return; }
            }
            if (!receiving.Wait(0)) { Header(stream, 409, 0, null, "text/plain"); return; }
            string partial = null;
            try {
                client.ReceiveTimeout = 30000;
                Directory.CreateDirectory(destinationFolder);
                partial = Path.Combine(destinationFolder, ".receptor-receive-" + Guid.NewGuid().ToString("N") + ".part");
                using (FileStream output = new FileStream(partial, FileMode.CreateNew, FileAccess.Write, FileShare.None))
                using (SHA256 sha = SHA256.Create()) {
                    byte[] buffer = new byte[65536]; long remaining = length;
                    while (remaining > 0) {
                        int count = stream.Read(buffer, 0, (int)Math.Min(buffer.Length, remaining));
                        if (count <= 0) throw new IOException("Transfer ended before the declared file length.");
                        output.Write(buffer, 0, count); sha.TransformBlock(buffer, 0, count, buffer, 0); remaining -= count;
                    }
                    sha.TransformFinalBlock(new byte[0], 0, 0);
                    if (!Equal(Hex(sha.Hash), digest)) { Header(stream, 422, 0, null, "text/plain"); return; }
                    output.Flush(true);
                }
                string saved = null;
                lock (gate) {
                    if (stopped) return;
                    for (int i = 0; i < 10000; i++) {
                        string candidate = i == 0 ? name : Path.GetFileNameWithoutExtension(name) + " (" + i + ")" + Path.GetExtension(name);
                        string destination = Path.Combine(destinationFolder, candidate);
                        try { File.Move(partial, destination); saved = candidate; partial = null; break; }
                        catch (IOException) { if (!File.Exists(destination)) throw; }
                    }
                    if (saved == null) throw new IOException("Could not choose an unused received filename.");
                    receivedCount++;
                }
                byte[] receipt = Encoding.UTF8.GetBytes(saved);
                Header(stream, 201, receipt.Length, Mac(key, "response\n" + nonce + "\n" + Hash(receipt) + "\n" + session), "text/plain; charset=utf-8");
                stream.Write(receipt, 0, receipt.Length);
                Notify("Received " + saved + " from your device.");
                Action<string> callback = FileReceived; if (callback != null) callback(saved);
            } catch (IOException) { Notify("Incoming transfer interrupted. Incomplete data was discarded; a fully received copy may already be in the folder."); }
            catch (UnauthorizedAccessException) { Notify("Could not write to the receive folder. Stop sharing and choose a writable folder."); }
            finally {
                if (partial != null) try { File.Delete(partial); } catch (IOException) { } catch (UnauthorizedAccessException) { }
                receiving.Release();
            }
        }
        private void Notify(string text) { Action<string> handler = Status; if (handler != null) handler(text); }
        private void TryDeleteDirectory() { try { Directory.Delete(staging); } catch (IOException) { } catch (UnauthorizedAccessException) { } }
        public void Dispose() {
            if(Remote!=null) Remote.Dispose();
            lock (gate) {
                if (stopped) return;
                stopped = true; listener.Stop();
                foreach (TcpClient c in clients) c.Close();
            }
            // Closing sockets unblocks in-progress sends before their snapshot files are disposed.
            for (;;) { lock (gate) { if (clients.Count == 0 && pendingAdds == 0) break; } Thread.Sleep(20); }
            lock (gate) {
                foreach (SharedFile item in packages) item.Dispose(); packages.Clear();
                if (pendingAdds == 0) TryDeleteDirectory();
            }
        }
    }
}
