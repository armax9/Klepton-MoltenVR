import Cocoa
let folder=URL(fileURLWithPath:CommandLine.arguments[1]);try FileManager.default.createDirectory(at:folder,withIntermediateDirectories:true)
for size in [16,32,64,128,256,512,1024]{
 let image=NSImage(size:NSSize(width:size,height:size));image.lockFocus();let ctx=NSGraphicsContext.current!.cgContext;ctx.scaleBy(x:CGFloat(size)/1024,y:CGFloat(size)/1024)
 let bg=NSBezierPath(roundedRect:NSRect(x:48,y:48,width:928,height:928),xRadius:205,yRadius:205);NSColor(calibratedRed:0.085,green:0.10,blue:0.15,alpha:1).setFill();bg.fill()
 let band=NSBezierPath(roundedRect:NSRect(x:167,y:327,width:690,height:380),xRadius:150,yRadius:150);NSColor(calibratedRed:1,green:0.38,blue:0.12,alpha:1).setFill();band.fill()
 let visor=NSBezierPath(roundedRect:NSRect(x:213,y:368,width:598,height:290),xRadius:110,yRadius:110);NSColor(calibratedRed:0.12,green:0.16,blue:0.23,alpha:1).setFill();visor.fill()
 for x in [300,575]{let eye=NSBezierPath(roundedRect:NSRect(x:x,y:446,width:150,height:98),xRadius:43,yRadius:43);NSColor(calibratedRed:0.31,green:0.83,blue:0.75,alpha:1).setFill();eye.fill()}
 let badge=NSBezierPath(roundedRect:NSRect(x:357,y:177,width:310,height:128),xRadius:38,yRadius:38);NSColor(calibratedRed:1,green:0.38,blue:0.12,alpha:1).setFill();badge.fill()
 let text="APK" as NSString;text.draw(in:NSRect(x:390,y:191,width:260,height:92),withAttributes:[.font:NSFont.systemFont(ofSize:72,weight:.heavy),.foregroundColor:NSColor.white])
 image.unlockFocus();let rep=NSBitmapImageRep(data:image.tiffRepresentation!)!;let data=rep.representation(using:.png,properties:[:])!
 if [16,32,128,256,512].contains(size){try data.write(to:folder.appendingPathComponent("icon_\(size)x\(size).png"))}
 if [32,64,256,512,1024].contains(size){let half=size/2;try data.write(to:folder.appendingPathComponent("icon_\(half)x\(half)@2x.png"))}
}
