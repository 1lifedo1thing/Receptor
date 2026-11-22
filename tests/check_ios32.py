#!/usr/bin/env python3
"""Validate the separate 3.2 package and its startup dependencies; not a device test."""
from pathlib import Path
import io
import plistlib
import struct
import tarfile

ROOT=Path(__file__).resolve().parents[1]
def members(data):
    assert data.startswith(b'!<arch>\n');offset=8
    while offset+60<=len(data):
        header=data[offset:offset+60];size=int(header[48:58]);name=header[:16].decode().strip().rstrip('/');body=data[offset+60:offset+60+size]
        if name.startswith('#1/'):
            length=int(name[3:]);name=body[:length].rstrip(b'\0').decode();body=body[length:]
        yield name,body
        offset+=60+size+size%2
def inspect(data,label):
    magic,cpu,subtype,_,count=struct.unpack_from('<IIIII',data);assert (magic,cpu,subtype)==(0xfeedface,12,9),label
    offset=28;minimum=None;libraries=[];symbols=None
    for _ in range(count):
        command,size=struct.unpack_from('<II',data,offset);assert size>=8 and offset+size<=len(data)
        if command==0x25:minimum=struct.unpack_from('<II',data,offset+8)
        if command==2:symbols=struct.unpack_from('<IIII',data,offset+8)
        if command in (0xc,0x80000018,0x8000001f,0x80000023):
            start=offset+struct.unpack_from('<I',data,offset+8)[0];libraries.append(data[start:offset+size].split(b'\0')[0].decode())
        offset+=size
    assert minimum and minimum[0]==0x30200,(label,minimum)
    imports=set()
    if symbols:
        table,entries,strings,string_size=symbols
        for i in range(entries):
            index,kind,section,_,_=struct.unpack_from('<IBBHI',data,table+i*12)
            if kind&0x0e==0 and section==0 and index:imports.add(data[strings+index:strings+string_size].split(b'\0')[0].decode())
    forbidden={'_OBJC_CLASS_$_NSCache','_OBJC_CLASS_$_ALAssetsLibrary','_OBJC_CLASS_$_QLPreviewController','_OBJC_CLASS_$_UILocalNotification','_UIApplicationDidEnterBackgroundNotification','_UIBackgroundTaskInvalid','_UILocalNotificationDefaultSoundName','_UIGraphicsBeginImageContextWithOptions','_kSecAttrAccessible','_kSecAttrAccessibleWhenUnlockedThisDeviceOnly'}
    assert not imports&forbidden,(label,imports&forbidden)
    assert not any(s.startswith(('_Block_','__NSConcrete','_dispatch_','_CGImageSource','_objc_initWeak','_objc_loadWeak')) for s in imports),(label,imports)
    assert not any(any(f in lib for f in ['QuickLook.framework','ImageIO.framework','AssetsLibrary.framework','WebKit.framework','libdispatch']) for lib in libraries),(label,libraries)
    for selector in ['applicationState','rootViewController','setRootViewController:','dataWithPropertyList:format:options:error:','propertyListWithData:options:format:error:']:
        assert b'\0'+selector.encode()+b'\0' not in data,(label,selector)
    return minimum
def main():
    package=ROOT/'packages/com.receptor.downloadmanager.ios32_1.8.0b1_iphoneos-arm.deb';archive=dict(members(package.read_bytes()))
    control_tar=next(v for k,v in archive.items() if k.startswith('control.tar'));payload_tar=next(v for k,v in archive.items() if k.startswith('data.tar'))
    with tarfile.open(fileobj=io.BytesIO(control_tar)) as stream:
        control=next(stream.extractfile(m).read().decode() for m in stream if m.name.lstrip('./')=='control')
        scripts={m.name.lstrip('./'):stream.extractfile(m).read() for m in stream if m.isfile() and m.name.lstrip('./')=='postinst'}
    assert 'Package: com.receptor.downloadmanager.ios32\n' in control
    assert 'firmware (>= 3.2)' in control and 'firmware (<< 4.0)' in control and 'Conflicts: com.receptor.downloadmanager' in control
    assert b'launchctl' not in scripts['postinst']
    with tarfile.open(fileobj=io.BytesIO(payload_tar)) as stream:
        info={m.name.lstrip('./'):m for m in stream.getmembers()};payload={n:stream.extractfile(m).read() for n,m in info.items() if m.isfile()}
    assert not any(n.startswith('Library/LaunchDaemons/') or n.endswith(('receptor-remote-agent','receptor-file-helper')) for n in payload)
    app=plistlib.loads(payload['Applications/Receptor.app/Info.plist']);assert app['MinimumOSVersion']=='3.2' and app['UIDeviceFamily']==[2]
    for name in ['Applications/Receptor.app/ReceptorApp','Library/MobileSubstrate/DynamicLibraries/Receptor.dylib','usr/libexec/receptor-package-helper','usr/libexec/receptor-deb-helper']:
        inspect(payload[name],name)
        if name.startswith('usr/'):
            assert info[name].uid==0 and info[name].mode==0o4755
    print('PASS: all four armv7 binaries target 3.2; no startup dependency on Blocks, GCD, newer frameworks, Keychain accessibility constants or unadapted plist/app-state selectors')
    count=0
    for path in (ROOT/'vendor/tls32/lib').glob('*.a'):
        for name,data in members(path.read_bytes()):
            if data.startswith(b'\xce\xfa\xed\xfe'):inspect(data,path.name+':'+name);count+=1
    assert count>100,count
    print('PASS:',count,'bundled TLS archive objects target iOS 3.2; iPad-only firmware gating, helper modes and daemon-free package verified')
    print('Physical iPhone OS 3.2 loader, Safari hooks, UIKit, Keychain, installer ABI and root helper authorization still require device tests.')
if __name__=='__main__':main()
