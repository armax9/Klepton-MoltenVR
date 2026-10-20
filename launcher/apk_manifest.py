"""Decode APK binary XML into the text metadata expected by Klepton."""
import struct
import xml.etree.ElementTree as ET
ANDROID='http://schemas.android.com/apk/res/android'
ET.register_namespace('android', ANDROID)
def decode(data):
    if data.lstrip().startswith(b'<'):return ET.fromstring(data)
    u16=lambda p:struct.unpack_from('<H',data,p)[0]
    u32=lambda p:struct.unpack_from('<I',data,p)[0]
    if u16(0)!=3:raise ValueError('Invalid Android binary XML')
    strings=[];stack=[];root=None;pos=u16(2)
    def string(i):return '' if i==0xffffffff else strings[i]
    while pos+8<=len(data):
        kind=u16(pos);head=u16(pos+2);size=u32(pos+4)
        if size<8 or pos+size>len(data):raise ValueError('Invalid Android XML chunk')
        if kind==1:
            count=u32(pos+8);utf8=bool(u32(pos+16)&0x100);start=pos+u32(pos+20)
            for i in range(count):
                p=start+u32(pos+head+i*4)
                if utf8:
                    def length8(p):
                        n=data[p];return (((n&127)<<8)|data[p+1],p+2) if n&128 else (n,p+1)
                    _,p=length8(p);n,p=length8(p);strings.append(data[p:p+n].decode('utf-8'))
                else:
                    n=u16(p);p+=2
                    if n&0x8000:n=((n&0x7fff)<<16)|u16(p);p+=2
                    strings.append(data[p:p+n*2].decode('utf-16le'))
        elif kind==0x102:
            ext=pos+16;name=string(u32(ext+4));attrs={};first=ext+u16(ext+8);stride=u16(ext+10)
            for i in range(u16(ext+12)):
                a=first+i*stride;ns=string(u32(a));key=string(u32(a+4));raw=u32(a+8);typ=data[a+15];value=u32(a+16)
                if raw!=0xffffffff:v=string(raw)
                elif typ==3:v=string(value)
                elif typ==0x12:v='true' if value else 'false'
                elif typ in (0x10,0x11):v=str(value)
                elif typ==1:v='@0x%08x'%value
                else:v=str(value)
                attrs[('{'+ns+'}' if ns else '')+key]=v
            node=ET.Element(name,attrs)
            if stack:stack[-1].append(node)
            else:root=node
            stack.append(node)
        elif kind==0x103:
            if stack:stack.pop()
        pos+=size
    if root is None:raise ValueError('Manifest root missing')
    return root

def metadata(raw):
    root=decode(raw);sdk=root.find('uses-sdk');a='{'+ANDROID+'}'
    return root,dict(package=root.get('package'),versionCode=root.get(a+'versionCode','0'),versionName=root.get(a+'versionName','unknown'),minSdkVersion=sdk.get(a+'minSdkVersion','29') if sdk is not None else '29',targetSdkVersion=sdk.get(a+'targetSdkVersion','29') if sdk is not None else '29')
