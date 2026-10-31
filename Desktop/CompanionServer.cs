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
    public sealed class SharedPackage : IDisposable {
        public readonly string Id, Name, Digest;
        public readonly long Size;
        private readonly FileStream snapshot;
        private readonly string path;
        public SharedPackage(string source, string directory, Func<bool> cancelled) {
            Name = Path.GetFileName(source);
            if (!String.Equals(Path.GetExtension(Name), ".deb", StringComparison.OrdinalIgnoreCase))
                throw new IOException("Choose a .deb file.");
            XmlConvert.VerifyXmlChars(Name);
            Id = Guid.NewGuid().ToString("N");
            path = Path.Combine(directory, Id + ".deb");
            try {
                using (FileStream input = new FileStream(source, FileMode.Open, FileAccess.Read, FileShare.Read)) {
                    Size = input.Length;
                    if (Size < 8 || Size > 2147483647L) throw new IOException("DEBs must be between 8 bytes and 2 GB.");
                    byte[] magic = new byte[8];
                    if (input.Read(magic, 0, 8) != 8 || Encoding.ASCII.GetString(magic) != "!<arch>\n")
                        throw new IOException("This file is not a Debian archive.");
                    input.Position = 0;
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
        private readonly List<SharedPackage> packages = new List<SharedPackage>();
        private readonly HashSet<TcpClient> clients = new HashSet<TcpClient>();
        private readonly HashSet<string> nonces = new HashSet<string>();
        private readonly string staging = Path.Combine(Path.GetTempPath(), "Receptor-" + Guid.NewGuid().ToString("N"));
        private volatile bool stopped;
        private int pendingAdds;
        public event Action<string> Status;
        public string Code { get { return identity.Code; } }
        public int Port { get { return ((IPEndPoint)listener.LocalEndpoint).Port; } }
        public CompanionServer(IPAddress address, int port, ConnectionSettings settings) {
            identity = settings; key = settings.Key;
            byte[] random = new byte[16];
            using (RandomNumberGenerator rng = RandomNumberGenerator.Create()) rng.GetBytes(random);
            session = Hex(random);
            Directory.CreateDirectory(staging);
            listener = new TcpListener(address, port);
            try { listener.Start(8); } catch { Directory.Delete(staging); throw; }
            Thread thread = new Thread(AcceptLoop); thread.IsBackground = true; thread.Start();
        }
        public SharedPackage Add(string path) {
            lock (gate) {
                if (stopped) throw new IOException("Sharing has stopped.");
                if (packages.Count + pendingAdds >= 32) throw new IOException("Share up to 32 DEBs per session.");
                pendingAdds++;
            }
            SharedPackage item = null;
            try {
                item = new SharedPackage(path, staging, delegate { return stopped; });
                lock (gate) { if (stopped) throw new IOException("Sharing has stopped."); packages.Add(item); }
                return item;
            } catch { if (item != null) item.Dispose(); throw; }
            finally {
                lock (gate) { pendingAdds--; if (stopped && pendingAdds == 0) TryDeleteDirectory(); }
            }
        }
        private void AcceptLoop() {
            while (!stopped) {
                TcpClient client;
                try { client = listener.AcceptTcpClient(); } catch (SocketException) { break; } catch (ObjectDisposedException) { break; }
                lock (gate) {
                    if (stopped || clients.Count >= 4) { client.Close(); continue; }
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
                    lock (gate) foreach (SharedPackage item in packages) {
                        xml.WriteStartElement("dict");
                        Field(xml, "id", "string", item.Id); Field(xml, "name", "string", item.Name);
                        Field(xml, "size", "integer", item.Size.ToString(System.Globalization.CultureInfo.InvariantCulture));
                        Field(xml, "sha256", "string", item.Digest); xml.WriteEndElement();
                    }
                    xml.WriteEndElement(); xml.WriteEndElement(); xml.WriteEndElement(); xml.WriteEndDocument();
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
            string text = "HTTP/1.1 " + code + (code == 200 ? " OK" : " Rejected") + "\r\nConnection: close\r\nCache-Control: no-store\r\nContent-Type: " + contentType +
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
                        stream.Write(body, 0, body.Length); Notify("Connected. Choose a DEB in Receptor on your iPad.");
                    } else {
                        SharedPackage item;
                        lock (gate) item = packages.Find(delegate(SharedPackage p) { return p.Id == route.Substring(10); });
                        if (item == null) { Header(stream, 404, 0, null, "text/plain"); return; }
                        Notify("Sending " + item.Name + "…");
                        Header(stream, 200, item.Size, Mac(key, "response\n" + nonce + "\n" + item.Digest + "\n" + session), "application/vnd.debian.binary-package");
                        item.Send(stream);
                        Notify("Sent " + item.Name + ". Confirm installation on the iPad; this is not an installation result.");
                    }
                }
            } catch (IOException) { } catch (SocketException) { } catch (ObjectDisposedException) { }
            finally { client.Close(); lock (gate) clients.Remove(client); }
        }
        private void Notify(string text) { Action<string> handler = Status; if (handler != null) handler(text); }
        private void TryDeleteDirectory() { try { Directory.Delete(staging); } catch (IOException) { } catch (UnauthorizedAccessException) { } }
        public void Dispose() {
            lock (gate) {
                if (stopped) return;
                stopped = true; listener.Stop();
                foreach (TcpClient c in clients) c.Close();
            }
            // Closing sockets unblocks in-progress sends before their snapshot files are disposed.
            for (;;) { lock (gate) { if (clients.Count == 0 && pendingAdds == 0) break; } Thread.Sleep(20); }
            lock (gate) {
                foreach (SharedPackage item in packages) item.Dispose(); packages.Clear();
                if (pendingAdds == 0) TryDeleteDirectory();
            }
        }
    }
}
