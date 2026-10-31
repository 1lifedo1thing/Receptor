using System;
using System.Net;
using ReceptorDesktop;

// Test harness: exercises the same server implementation as the desktop app.
static class CompanionHost {
    static void Main(string[] args) {
        using (CompanionServer server = new CompanionServer(IPAddress.Loopback, 0)) {
            foreach (string file in args) server.Add(file);
            Console.WriteLine(server.Port + " " + server.Code);
            Console.Out.Flush();
            Console.ReadLine();
        }
    }
}
