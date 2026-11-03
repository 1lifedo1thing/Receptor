using System;
using System.Collections.Generic;
using System.IO;
using System.Threading;
using System.Text.RegularExpressions;

namespace ReceptorDesktop {
    public sealed class RemoteDevice {
        public string Id, Label;
        public DateTime Seen;
        public bool Busy;
        public override string ToString() { return Label + " · " + Id.Substring(0,8) + (Busy?" · working / awaiting result":DateTime.UtcNow-Seen < TimeSpan.FromSeconds(40) ? " · online" : " · offline"); }
    }
    public sealed class RemoteJob {
        internal readonly string Id=Guid.NewGuid().ToString("N");
        internal readonly Dictionary<string,object> Request;
        internal readonly ManualResetEventSlim Completed=new ManualResetEventSlim(false);
        internal Dictionary<string,object> Result;
        internal bool Dispatched;
        internal bool Expired;
        internal RemoteJob(Dictionary<string,object> request) { Request=request; }
    }
    public sealed class RemoteBroker : IDisposable {
        sealed class DeviceState {
            public readonly RemoteDevice Info=new RemoteDevice();
            public readonly ManualResetEventSlim Wake=new ManualResetEventSlim(false);
            public long Counter;
            public byte[] Seed;
            public RemoteJob Job;
            public string LastAck;
            public bool Polling;
        }
        readonly object gate=new object();
        readonly Dictionary<string,DeviceState> devices=new Dictionary<string,DeviceState>();
        readonly RemoteIdentity identity;
        readonly string enrollmentKey;
        string session=Guid.NewGuid().ToString("N"); bool enabled, disposed;
        public RemoteBroker(RemoteIdentity identity,string enrollmentKey) { this.identity=identity; this.enrollmentKey=enrollmentKey; enabled=identity.Enabled; }
        public string PublicKey { get { return identity.PublicKey; } }
        public string Fingerprint { get { return identity.Fingerprint; } }
        public bool Enabled { get { lock(gate) return enabled && !disposed; } }
        public void SetEnabled(bool value) {
            lock(gate) {
                if(disposed) throw new IOException("Sharing stopped."); if(enabled==value) return;
                enabled=value; session=Guid.NewGuid().ToString("N");
                foreach(DeviceState device in devices.Values) { Fail(device,"Remote access changed. A dispatched operation may still finish on the device; inspect its operation log."); device.LastAck=null; device.Wake.Set(); }
            }
        }
        static void Fail(DeviceState device,string message) {
            if(device.Job!=null) { device.Job.Result=new Dictionary<string,object>{{"error",message}}; device.Job.Completed.Set(); device.Job=null; }
        }
        public RemoteDevice[] Devices() { lock(gate) { List<RemoteDevice> list=new List<RemoteDevice>(); foreach(DeviceState d in devices.Values) list.Add(new RemoteDevice {Id=d.Info.Id,Label=d.Info.Label,Seen=d.Info.Seen,Busy=d.Job!=null}); return list.ToArray(); } }
        public Dictionary<string,object> Execute(string id,Dictionary<string,object> request,int timeoutSeconds) {
            DeviceState device; RemoteJob job=new RemoteJob(request);
            lock(gate) {
                if(!enabled || disposed || !devices.TryGetValue(id,out device)) throw new IOException("Enable background access and wait for the device to connect.");
                if(DateTime.UtcNow-device.Info.Seen>TimeSpan.FromSeconds(40)) throw new IOException("The device is offline. Check power, Wi-Fi and its background-access setting.");
                if(device.Job!=null) {
                    if(device.Job.Expired && RecoveryQuery(request))device.Job=null;
                    else throw new IOException(device.Job.Expired?"A previous operation has an uncertain outcome. Request the device operation log or Installed list before making another change.":"This device already has an operation in progress.");
                }
                device.Job=job; device.Wake.Set();
            }
            if(!job.Completed.Wait(TimeSpan.FromSeconds(timeoutSeconds))) {
                lock(gate) {
                    if(device.Job==job && !job.Dispatched) device.Job=null;
                    job.Expired=true;
                    if(!job.Completed.IsSet) throw new IOException(job.Dispatched ? "No completion was received. The operation may still be running. Do not repeat an install blindly; inspect the device operation log when it reconnects." : "The device did not collect this request. It was cancelled before dispatch.");
                }
            }
            Dictionary<string,object> result=job.Result;
            if(result==null) throw new IOException("No remote result.");
            return result;
        }
        static bool RecoveryQuery(Dictionary<string,object> request) {
            object kind,args;
            if(request.TryGetValue("op",out kind) && (string)kind=="packages" && request.TryGetValue("args",out args)) {
                IEnumerable<object> sequence=args as IEnumerable<object>; if(sequence!=null)foreach(object value in sequence)return value as string=="last-result" || value as string=="installed" || value as string=="sources";
            }
            return false;
        }
        public byte[] Handle(string id,string nonce,string sealedSeed,string enrollment,string auth,byte[] frame,out string responseAuth) {
            responseAuth=null;
            if(!Regex.IsMatch(id??"", "^[a-f0-9]{32}$") || !Regex.IsMatch(nonce??"", "^[a-f0-9]{32}$") || frame.Length>RemoteCrypto.MaximumFrame) throw new IOException("Invalid remote request.");
            byte[] seed;
            lock(gate) {
                if(!enabled || disposed) throw new IOException("Remote access is disabled.");
                DeviceState known; seed=devices.TryGetValue(id,out known)?known.Seed:null;
            }
            if(seed==null) {
                byte[] sealedBytes=Convert.FromBase64String(sealedSeed??"");
                if(!RemoteCrypto.Equal(enrollment,CompanionServer.Mac(enrollmentKey,"enroll\n"+id+"\n"+CompanionServer.Hash(sealedBytes)))) throw new IOException("Enrollment requires the saved PC pairing.");
                seed=identity.Unseal(sealedBytes);
                if(!RemoteCrypto.Equal(CompanionServer.Hash(seed).Substring(0,32),id)) throw new IOException("Device identity mismatch.");
            }
            if(!RemoteCrypto.Equal(auth,RemoteCrypto.Mac(seed,"request",id,nonce,frame))) throw new IOException("Remote authentication failed.");
            Dictionary<string,object> input=RemotePlist.Read(RemoteCrypto.Decrypt(seed,frame));
            object peerSession; string supplied=input.TryGetValue("session",out peerSession)?peerSession as string:null;
            DeviceState state; string current; bool ready;
            lock(gate) {
                if(!enabled || disposed) throw new IOException("Remote access disabled.");
                if(!devices.TryGetValue(id,out state)) {
                    if(devices.Count>=8) throw new IOException("Device limit reached. Restart sharing.");
                    state=new DeviceState {Seed=seed}; state.Info.Id=id; state.Info.Label="Receptor device"; devices.Add(id,state);
                }
                object number;
                if(!input.TryGetValue("counter",out number) || !(number is long) || (long)number<0) throw new IOException("Invalid remote counter.");
                if((long)number==0 && supplied=="") {
                    byte[] challenge=RemoteCrypto.Encrypt(seed,RemotePlist.Write(new Dictionary<string,object>{{"session",session},{"counterFloor",state.Counter}}));
                    responseAuth=RemoteCrypto.Mac(seed,"response",id,nonce,challenge); return challenge;
                }
                if((long)number<=state.Counter) throw new IOException("Remote request replay rejected.");
                if(state.Polling) throw new IOException("A device poll is already active.");
                state.Counter=(long)number; state.Info.Seen=DateTime.UtcNow;
                object version; if(input.TryGetValue("os",out version) && version is string && ((string)version).Length<=24 && Regex.IsMatch((string)version,"^[0-9.]+$")) state.Info.Label="iOS "+(string)version;
                current=session; ready=supplied==current;
                if(ready) {
                    object raw; Dictionary<string,object> reply=input.TryGetValue("reply",out raw)?raw as Dictionary<string,object>:null;
                    if(reply!=null) {
                        object replyId,body;
                        if(reply.TryGetValue("id",out replyId) && reply.TryGetValue("body",out body) && body is byte[] && replyId is string) {
                            if(state.Job!=null && state.Job.Id==(string)replyId) {
                                state.Job.Result=RemotePlist.Read((byte[])body); state.LastAck=state.Job.Id; state.Job.Completed.Set(); state.Job=null;
                            } else if(Regex.IsMatch((string)replyId,"^[a-f0-9]{32}$")) state.LastAck=(string)replyId;
                        } else throw new IOException("Invalid remote result.");
                    }
                }
                state.Polling=true;
            }
            try {
                // Acknowledge completion and allow the desktop to enqueue the next file chunk
                // before this long poll returns, rather than waiting for a polling interval.
                DateTime deadline=DateTime.UtcNow.AddSeconds(10);
                while(ready) {
                    lock(gate) { if(!enabled || disposed || session!=current || (state.Job!=null && !state.Job.Expired)) break; state.Wake.Reset(); }
                    int delay=(int)(deadline-DateTime.UtcNow).TotalMilliseconds; if(delay<=0) break; state.Wake.Wait(Math.Min(1000,delay));
                }
                Dictionary<string,object> output=new Dictionary<string,object>();
                lock(gate) {
                    if(!enabled || disposed) throw new IOException("Remote access stopped.");
                    output["session"]=session;
                    if(ready && current==session) {
                        if(state.LastAck!=null) output["ack"]=state.LastAck;
                        if(state.Job!=null && !state.Job.Expired) { state.Job.Dispatched=true; output["command"]=new Dictionary<string,object>{{"id",state.Job.Id},{"request",state.Job.Request}}; }
                    }
                    state.Info.Seen=DateTime.UtcNow;
                }
                byte[] encrypted=RemoteCrypto.Encrypt(seed,RemotePlist.Write(output)); responseAuth=RemoteCrypto.Mac(seed,"response",id,nonce,encrypted); return encrypted;
            } finally { lock(gate) state.Polling=false; }
        }
        public void Dispose() { lock(gate) { if(disposed)return; disposed=true; enabled=false; foreach(DeviceState d in devices.Values) { Fail(d,"Sharing stopped. Any dispatched operation may still finish; inspect its operation log."); d.Wake.Set(); } } }
    }
}
