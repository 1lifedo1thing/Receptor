using System;
using System.Collections.Generic;
using System.IO;
using System.Net;
using ReceptorDesktop;

static class RemoteTestHost {
    static void Emit(Dictionary<string,object> value) { Console.WriteLine(Convert.ToBase64String(RemotePlist.Write(value))); Console.Out.Flush(); }
    static void Main() {
        ConnectionSettings pairing=ConnectionSettings.Create(); RemoteIdentity identity=RemoteIdentity.Create(); identity.Enabled=true;
        CompanionServer server=new CompanionServer(IPAddress.Loopback,0,pairing,null,identity); int port=server.Port;
        Emit(new Dictionary<string,object>{{"port",port},{"publicKey",identity.PublicKey},{"fingerprint",identity.Fingerprint},{"pairingKey",pairing.Key}});
        try {
            string line;
            while((line=Console.ReadLine())!=null) {
                try {
                    Dictionary<string,object> request=RemotePlist.Read(Convert.FromBase64String(line)); string action=(string)request["action"];
                    if(action=="exit") {Emit(new Dictionary<string,object>{{"ok",true}});break;}
                    if(action=="devices") {List<object> devices=new List<object>();foreach(RemoteDevice device in server.Remote.Devices())devices.Add(new Dictionary<string,object>{{"id",device.Id},{"busy",device.Busy}});Emit(new Dictionary<string,object>{{"items",devices}});}
                    else if(action=="request") Emit(server.Remote.Execute((string)request["device"],(Dictionary<string,object>)request["request"],request.ContainsKey("timeout")?(int)(long)request["timeout"]:15));
                    else if(action=="restart") {server.Dispose();server=new CompanionServer(IPAddress.Loopback,port,pairing,null,identity);Emit(new Dictionary<string,object>{{"ok",true}});}
                    else if(action=="off" || action=="on") {server.Remote.SetEnabled(action=="on");Emit(new Dictionary<string,object>{{"ok",true}});}
                    else if(action=="unseal") Emit(new Dictionary<string,object>{{"seed",identity.Unseal((byte[])request["data"])}});
                    else if(action=="decrypt") Emit(new Dictionary<string,object>{{"plain",RemoteCrypto.Decrypt((byte[])request["seed"],(byte[])request["frame"])}});
                    else if(action=="encrypt") {byte[] frame=RemoteCrypto.Encrypt((byte[])request["seed"],(byte[])request["plain"]);Emit(new Dictionary<string,object>{{"frame",frame},{"auth",RemoteCrypto.Mac((byte[])request["seed"],"response",(string)request["device"],(string)request["nonce"],frame)}});}
                    else if(action=="parse") Emit(RemotePlist.Read((byte[])request["data"]));
                    else throw new IOException("Unknown test action.");
                } catch(Exception ex) {Emit(new Dictionary<string,object>{{"error",ex.GetType().Name+": "+ex.Message}});}
            }
        } finally {server.Dispose();}
    }
}
