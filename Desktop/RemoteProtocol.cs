using System;
using System.Collections.Generic;
using System.IO;
using System.Security.Cryptography;
using System.Text;
using System.Xml;

namespace ReceptorDesktop {
    public static class RemotePlist {
        public static byte[] Write(object value) {
            using (MemoryStream output = new MemoryStream()) {
                using (XmlWriter xml = XmlWriter.Create(output, new XmlWriterSettings { Encoding = new UTF8Encoding(false), CloseOutput = false })) {
                    xml.WriteStartElement("plist"); xml.WriteAttributeString("version", "1.0"); WriteValue(xml, value); xml.WriteEndElement();
                }
                return output.ToArray();
            }
        }
        static void WriteValue(XmlWriter xml, object value) {
            IDictionary<string,object> dict = value as IDictionary<string,object>;
            IEnumerable<object> array = value as IEnumerable<object>;
            if (dict != null) { xml.WriteStartElement("dict"); foreach (KeyValuePair<string,object> pair in dict) { xml.WriteElementString("key", pair.Key); WriteValue(xml, pair.Value); } xml.WriteEndElement(); }
            else if (value is byte[]) xml.WriteElementString("data", Convert.ToBase64String((byte[])value));
            else if (value is bool) { xml.WriteStartElement((bool)value ? "true" : "false"); xml.WriteEndElement(); }
            else if (value is long || value is int) xml.WriteElementString("integer", Convert.ToString(value, System.Globalization.CultureInfo.InvariantCulture));
            else if (array != null) { xml.WriteStartElement("array"); foreach (object item in array) WriteValue(xml, item); xml.WriteEndElement(); }
            else xml.WriteElementString("string", value == null ? "" : value.ToString());
        }
        public static Dictionary<string,object> Read(byte[] data) {
            if (data.Length > 4 * 1024 * 1024) throw new IOException("Remote result is too large.");
            XmlDocument document = new XmlDocument { XmlResolver = null };
            XmlReaderSettings settings=new XmlReaderSettings { DtdProcessing = DtdProcessing.Ignore, XmlResolver = null, MaxCharactersInDocument = 4 * 1024 * 1024 };
            using(XmlReader scan=XmlReader.Create(new MemoryStream(data),settings)) { int nodes=0; while(scan.Read()) if(scan.Depth>26 || ++nodes>200000) throw new IOException("Remote XML is too deeply nested or large."); }
            using (XmlReader reader = XmlReader.Create(new MemoryStream(data), settings)) document.Load(reader);
            XmlElement root = document.DocumentElement;
            if (root == null || root.Name != "plist" || root.ChildNodes.Count != 1) throw new IOException("Invalid remote plist.");
            int count = 0;
            Dictionary<string,object> result = ReadValue(root.FirstChild, 0, ref count) as Dictionary<string,object>;
            if (result == null) throw new IOException("Expected a remote dictionary."); return result;
        }
        static object ReadValue(XmlNode node, int depth, ref int count) {
            if (depth > 24 || ++count > 50000 || !(node is XmlElement)) throw new IOException("Invalid remote plist structure.");
            if (node.Name == "dict") {
                Dictionary<string,object> dict = new Dictionary<string,object>(StringComparer.Ordinal);
                if ((node.ChildNodes.Count & 1) != 0) throw new IOException("Invalid dictionary.");
                for (int i = 0; i < node.ChildNodes.Count; i += 2) {
                    XmlNode key = node.ChildNodes[i]; if (key.Name != "key" || dict.ContainsKey(key.InnerText)) throw new IOException("Invalid dictionary key.");
                    dict.Add(key.InnerText, ReadValue(node.ChildNodes[i + 1], depth + 1, ref count));
                }
                return dict;
            }
            if (node.Name == "array") { List<object> list = new List<object>(); foreach (XmlNode child in node.ChildNodes) list.Add(ReadValue(child, depth + 1, ref count)); return list; }
            if (node.Name == "string" || node.Name == "date") return node.InnerText;
            if (node.Name == "data") return Convert.FromBase64String(node.InnerText);
            if (node.Name == "integer") return Int64.Parse(node.InnerText, System.Globalization.CultureInfo.InvariantCulture);
            if (node.Name == "true") return true; if (node.Name == "false") return false;
            if (node.Name == "real") return Double.Parse(node.InnerText, System.Globalization.CultureInfo.InvariantCulture);
            throw new IOException("Unsupported remote plist value.");
        }
    }
    public sealed class RemoteIdentity {
        readonly byte[] privateKey;
        public readonly string PublicKey, Fingerprint;
        public bool Enabled;
        RemoteIdentity(byte[] key, bool enabled) {
            privateKey = key; Enabled = enabled;
            using (RSACryptoServiceProvider rsa = Open()) {
                RSAParameters parameters = rsa.ExportParameters(false);
                byte[] sequence = Der(0x30, Join(Der(2, Positive(parameters.Modulus)), Der(2, Positive(parameters.Exponent))));
                byte[] algorithm = new byte[] {0x30,0x0d,0x06,0x09,0x2a,0x86,0x48,0x86,0xf7,0x0d,0x01,0x01,0x01,0x05,0x00};
                byte[] spki = Der(0x30, Join(algorithm, Der(3, Join(new byte[] {0}, sequence))));
                PublicKey = "-----BEGIN PUBLIC KEY-----\n" + Convert.ToBase64String(spki, Base64FormattingOptions.InsertLineBreaks).Replace("\r", "") + "\n-----END PUBLIC KEY-----\n";
                Fingerprint = CompanionServer.Hash(spki);
            }
        }
        static byte[] Positive(byte[] value) { return value[0] >= 128 ? Join(new byte[] {0}, value) : value; }
        static byte[] Join(byte[] a, byte[] b) { byte[] data = new byte[a.Length + b.Length]; Buffer.BlockCopy(a,0,data,0,a.Length); Buffer.BlockCopy(b,0,data,a.Length,b.Length); return data; }
        static byte[] Der(byte tag, byte[] data) {
            byte[] prefix = data.Length < 128 ? new byte[] {tag,(byte)data.Length} : data.Length < 256 ? new byte[] {tag,0x81,(byte)data.Length} : new byte[] {tag,0x82,(byte)(data.Length >> 8),(byte)data.Length};
            return Join(prefix, data);
        }
        RSACryptoServiceProvider Open() { RSACryptoServiceProvider rsa = new RSACryptoServiceProvider(); rsa.PersistKeyInCsp = false; rsa.ImportCspBlob(privateKey); return rsa; }
        public byte[] Unseal(byte[] data) { if (data.Length != 256) throw new IOException("Invalid remote enrollment."); using (RSACryptoServiceProvider rsa = Open()) { byte[] seed = rsa.Decrypt(data, true); if (seed.Length != 32) throw new IOException("Invalid enrollment secret."); return seed; } }
        public static RemoteIdentity Create() { using (RSACryptoServiceProvider rsa = new RSACryptoServiceProvider(2048)) { rsa.PersistKeyInCsp = false; return new RemoteIdentity(rsa.ExportCspBlob(true), false); } }
        public static RemoteIdentity Load(string path) {
            if (!File.Exists(path)) return Create();
            string[] fields = Encoding.ASCII.GetString(ProtectedData.Unprotect(File.ReadAllBytes(path), null, DataProtectionScope.CurrentUser)).Split('\n');
            if (fields.Length != 3 || fields[0] != "1" || (fields[1] != "0" && fields[1] != "1")) throw new IOException("Invalid remote identity.");
            return new RemoteIdentity(Convert.FromBase64String(fields[2]), fields[1] == "1");
        }
        public void Save(string path) {
            byte[] data = ProtectedData.Protect(Encoding.ASCII.GetBytes("1\n" + (Enabled ? "1" : "0") + "\n" + Convert.ToBase64String(privateKey)), null, DataProtectionScope.CurrentUser);
            Directory.CreateDirectory(Path.GetDirectoryName(Path.GetFullPath(path))); string temp = path + "." + Guid.NewGuid().ToString("N") + ".tmp";
            try { File.WriteAllBytes(temp, data); if (File.Exists(path)) File.Replace(temp, path, null); else File.Move(temp,path); } finally { if (File.Exists(temp)) File.Delete(temp); }
        }
    }
    public static class RemoteCrypto {
        public const int MaximumFrame = 4 * 1024 * 1024;
        static byte[] Key(byte[] seed, string purpose) { using (HMACSHA256 hmac = new HMACSHA256(seed)) return hmac.ComputeHash(Encoding.ASCII.GetBytes("Receptor remote v3 " + purpose)); }
        public static byte[] Encrypt(byte[] seed, byte[] plain) {
            if (plain.Length > 3 * 1024 * 1024) throw new IOException("Remote request is too large.");
            using (Aes aes = Aes.Create()) { aes.Key = Key(seed,"encryption"); aes.GenerateIV(); aes.Mode = CipherMode.CBC; aes.Padding = PaddingMode.PKCS7;
                using (ICryptoTransform transform = aes.CreateEncryptor()) { byte[] cipher = transform.TransformFinalBlock(plain,0,plain.Length), frame = new byte[17 + cipher.Length]; frame[0]=3; Buffer.BlockCopy(aes.IV,0,frame,1,16); Buffer.BlockCopy(cipher,0,frame,17,cipher.Length); return frame; }
            }
        }
        public static byte[] Decrypt(byte[] seed, byte[] frame) {
            if (frame.Length < 33 || frame.Length > MaximumFrame || frame[0] != 3 || (frame.Length - 17) % 16 != 0) throw new IOException("Invalid encrypted remote frame.");
            using (Aes aes = Aes.Create()) { aes.Key=Key(seed,"encryption"); byte[] iv=new byte[16]; Buffer.BlockCopy(frame,1,iv,0,16); aes.IV=iv; aes.Mode=CipherMode.CBC; aes.Padding=PaddingMode.PKCS7;
                using (ICryptoTransform transform=aes.CreateDecryptor()) return transform.TransformFinalBlock(frame,17,frame.Length-17);
            }
        }
        public static string Mac(byte[] seed, string direction, string id, string nonce, byte[] frame) {
            using (HMACSHA256 hmac = new HMACSHA256(Key(seed,"authentication"))) return CompanionServer.Hex(hmac.ComputeHash(Encoding.ASCII.GetBytes(direction+"\n/v3/control\n"+id+"\n"+nonce+"\n"+CompanionServer.Hash(frame))));
        }
        public static bool Equal(string a, string b) { if (a==null || b==null || a.Length!=b.Length) return false; int diff=0; for(int i=0;i<a.Length;i++) diff|=a[i]^b[i]; return diff==0; }
    }
}
