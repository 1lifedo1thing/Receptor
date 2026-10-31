using System;
using System.Net;
using System.IO;
using ReceptorDesktop;

// Test harness: exercises the same server implementation as the desktop app.
static class CompanionHost {
    static void Main(string[] args) {
        bool existed = File.Exists(args[0]);
        ConnectionSettings settings = ConnectionSettings.Load(args[0]);
        if (existed && (settings.Address != "192.168.1.20" || !settings.AutoStart)) throw new Exception("Saved connection was not restored.");
        settings.Address = "192.168.1.20"; settings.AutoStart = true; settings.Save(args[0]);
        using (CompanionServer server = new CompanionServer(IPAddress.Loopback, 0, settings)) {
            for (int i = 1; i < args.Length; i++) server.Add(args[i]);
            Console.WriteLine(server.Port + " " + server.Code);
            Console.Out.Flush();
            Console.ReadLine();
        }
    }
}
