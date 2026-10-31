using System;
using System.IO;
using System.Security.Cryptography;
using System.Text;
using System.Text.RegularExpressions;

namespace ReceptorDesktop {
    public sealed class ConnectionSettings {
        public const int ListenPort = 49176;
        public const int Iterations = 100000;
        public string Code { get; private set; }
        public string Salt { get; private set; }
        public string Key { get; private set; }
        public string Address = "";
        public bool AutoStart;
        private ConnectionSettings() { }
        public static ConnectionSettings Create() {
            const string alphabet = "ABCDEFGHJKLMNPQRSTUVWXYZ23456789";
            byte[] random = new byte[24];
            using (RandomNumberGenerator rng = RandomNumberGenerator.Create()) rng.GetBytes(random);
            StringBuilder code = new StringBuilder();
            for (int i = 0; i < 8; i++) code.Append(alphabet[random[i] & 31]);
            byte[] salt = new byte[16]; Array.Copy(random, 8, salt, 0, 16);
            return new ConnectionSettings { Code = code.ToString(), Salt = CompanionServer.Hex(salt), Key = Derive(code.ToString(), salt) };
        }
        public static string Derive(string code, byte[] salt) {
            // PBKDF2-HMAC-SHA256, one 32-byte block. Also supported by the iOS 4 client.
            byte[] block = new byte[salt.Length + 4]; Array.Copy(salt, block, salt.Length); block[block.Length - 1] = 1;
            using (HMACSHA256 hmac = new HMACSHA256(Encoding.ASCII.GetBytes(code))) {
                byte[] u = hmac.ComputeHash(block), output = (byte[])u.Clone();
                for (int iteration = 1; iteration < Iterations; iteration++) {
                    u = hmac.ComputeHash(u); for (int j = 0; j < output.Length; j++) output[j] ^= u[j];
                }
                return CompanionServer.Hex(output);
            }
        }
        public static ConnectionSettings Load(string path) {
            if (!File.Exists(path)) return Create();
            byte[] plain = ProtectedData.Unprotect(File.ReadAllBytes(path), null, DataProtectionScope.CurrentUser);
            string[] fields = Encoding.UTF8.GetString(plain).Split('\n');
            if (fields.Length != 6 || fields[0] != "2" || !Regex.IsMatch(fields[1], "^[A-HJ-NP-Z2-9]{8}$") ||
                !Regex.IsMatch(fields[2], "^[a-f0-9]{32}$") || !Regex.IsMatch(fields[3], "^[a-f0-9]{64}$") ||
                !Regex.IsMatch(fields[4], "^[0-9.]{0,15}$") || (fields[5] != "0" && fields[5] != "1"))
                throw new IOException("Saved pairing settings are invalid. Stop sharing and use Reset pairing.");
            return new ConnectionSettings { Code = fields[1], Salt = fields[2], Key = fields[3], Address = fields[4], AutoStart = fields[5] == "1" };
        }
        public void Save(string path) {
            byte[] plain = Encoding.UTF8.GetBytes("2\n" + Code + "\n" + Salt + "\n" + Key + "\n" + Address + "\n" + (AutoStart ? "1" : "0"));
            byte[] encrypted = ProtectedData.Protect(plain, null, DataProtectionScope.CurrentUser);
            Directory.CreateDirectory(Path.GetDirectoryName(Path.GetFullPath(path)));
            string temporary = path + "." + Guid.NewGuid().ToString("N") + ".tmp";
            try {
                File.WriteAllBytes(temporary, encrypted);
                if (File.Exists(path)) File.Replace(temporary, path, null); else File.Move(temporary, path);
            } finally { if (File.Exists(temporary)) File.Delete(temporary); }
        }
    }
}
