import Cocoa
let base = URL(fileURLWithPath: CommandLine.arguments[0]).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
class TopStack: NSStackView { override var isFlipped: Bool { true } }
class Launcher: NSObject, NSApplicationDelegate {
 var window:NSWindow!; var stack:NSStackView!; var status:NSTextField!; var path:NSTextField!; var stateLabel:NSTextField!; var dot:NSView!; var spinner:NSProgressIndicator!; var stopButton:NSButton!; var game:Process?; var items:[[String:Any]]=[]; var launchButtons:[NSButton]=[]; var logPath:String?; var preparing=false; var stopping=false
 func state(_ title:String,_ detail:String,_ color:NSColor,_ busy:Bool=false){
  stateLabel.stringValue=title;stateLabel.textColor=color;dot.layer?.backgroundColor=color.cgColor;status.stringValue=detail
  if busy{spinner.startAnimation(nil)}else{spinner.stopAnimation(nil)}
  stopButton.isEnabled=game?.isRunning == true && !stopping
  for b in launchButtons{b.isEnabled = !preparing && game?.isRunning != true && (items[b.tag]["supported"] as? Bool ?? false)}
 }
 func applicationDidFinishLaunching(_ n:Notification){
  if let url=Bundle.main.url(forResource:"APKVRIcon",withExtension:"icns"),let image=NSImage(contentsOf:url){NSApp.applicationIconImage=image;NSApp.dockTile.display()}
  window=NSWindow(contentRect:NSRect(x:0,y:0,width:820,height:560),styleMask:[.titled,.closable,.miniaturizable,.resizable],backing:.buffered,defer:false);window.title="APK VR Library";window.minSize=NSSize(width:620,height:420);window.center()
  let outer=NSStackView();outer.orientation = .vertical;outer.spacing=14;outer.edgeInsets=NSEdgeInsets(top:24,left:24,bottom:24,right:24);outer.translatesAutoresizingMaskIntoConstraints=false
  window.contentView!.addSubview(outer);NSLayoutConstraint.activate([outer.leadingAnchor.constraint(equalTo:window.contentView!.leadingAnchor),outer.trailingAnchor.constraint(equalTo:window.contentView!.trailingAnchor),outer.topAnchor.constraint(equalTo:window.contentView!.topAnchor),outer.bottomAnchor.constraint(equalTo:window.contentView!.bottomAnchor)])
  let heading=NSStackView();heading.spacing=12
  let icon=NSImageView(image:NSApp.applicationIconImage);icon.widthAnchor.constraint(equalToConstant:44).isActive=true;icon.heightAnchor.constraint(equalToConstant:44).isActive=true;heading.addArrangedSubview(icon)
  let title=NSTextField(labelWithString:"Game Library");title.font = .systemFont(ofSize:25,weight:.semibold);heading.addArrangedSubview(title);outer.addArrangedSubview(heading)
  let row=NSStackView();row.spacing=8;row.addArrangedSubview(NSButton(title:"Choose Folder…",target:self,action:#selector(choose)));row.addArrangedSubview(NSButton(title:"Refresh",target:self,action:#selector(refresh)));outer.addArrangedSubview(row)
  path=NSTextField(labelWithString:UserDefaults.standard.string(forKey:"gamesRoot") ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Games").path);path.lineBreakMode = .byTruncatingMiddle;outer.addArrangedSubview(path)
  let scroll=NSScrollView();scroll.hasVerticalScroller=true;scroll.translatesAutoresizingMaskIntoConstraints=false;outer.addArrangedSubview(scroll);scroll.widthAnchor.constraint(equalTo:outer.widthAnchor,constant:-48).isActive=true
  stack=TopStack();stack.orientation = .vertical;stack.alignment = .leading;stack.spacing=10;stack.translatesAutoresizingMaskIntoConstraints=false;scroll.documentView=stack;stack.widthAnchor.constraint(equalTo:scroll.contentView.widthAnchor).isActive=true
  let stateRow=NSStackView();stateRow.spacing=8;dot=NSView();dot.wantsLayer=true;dot.layer?.cornerRadius=5;dot.widthAnchor.constraint(equalToConstant:10).isActive=true;dot.heightAnchor.constraint(equalToConstant:10).isActive=true;stateRow.addArrangedSubview(dot)
  stateLabel=NSTextField(labelWithString:"Ready");stateLabel.font = .systemFont(ofSize:13,weight:.semibold);stateRow.addArrangedSubview(stateLabel);spinner=NSProgressIndicator();spinner.style = .spinning;spinner.controlSize = .small;spinner.isDisplayedWhenStopped=false;stateRow.addArrangedSubview(spinner);outer.addArrangedSubview(stateRow)
  status=NSTextField(wrappingLabelWithString:"");status.font = .systemFont(ofSize:12);status.textColor = .secondaryLabelColor;outer.addArrangedSubview(status)
  let bottom=NSStackView();bottom.spacing=12;stopButton=NSButton(title:"Stop Game",target:self,action:#selector(stop));stopButton.contentTintColor = .systemRed;bottom.addArrangedSubview(stopButton);outer.addArrangedSubview(bottom)
  state("Ready","Connect your Quest in MoltenVR first.",.secondaryLabelColor);window.makeKeyAndOrderFront(nil);NSApp.activate(ignoringOtherApps:true);refresh()
 }
 func backend(_ op:String,_ arg:String,done:@escaping(Any)->Void){DispatchQueue.global().async{
  let p=Process();p.executableURL=URL(fileURLWithPath:"/opt/homebrew/bin/python3");p.arguments=[base.appendingPathComponent("library.py").path,op,arg];let out=Pipe();p.standardOutput=out
  do{try p.run();let data=out.fileHandleForReading.readDataToEndOfFile();p.waitUntilExit();let obj=try JSONSerialization.jsonObject(with:data);DispatchQueue.main.async{done(obj)}}catch{DispatchQueue.main.async{done(["error":error.localizedDescription])}}
 }}
 @objc func choose(){let p=NSOpenPanel();p.canChooseFiles=false;p.canChooseDirectories=true;if p.runModal() == .OK,let u=p.url{path.stringValue=u.path;UserDefaults.standard.set(u.path,forKey:"gamesRoot");refresh()}}
 @objc func refresh(){if !preparing && game?.isRunning != true{state("Scanning","Looking for APK games…",.systemOrange,true)};backend("scan",path.stringValue){obj in
  guard let list=obj as? [[String:Any]] else{if self.game?.isRunning != true{self.state("Error","Could not read the folder.",.systemRed)};return}
  self.stack.arrangedSubviews.forEach{self.stack.removeArrangedSubview($0);$0.removeFromSuperview()};self.launchButtons=[];self.items=list
  for (i,item) in list.enumerated(){
   let r=NSStackView();r.spacing=14;r.wantsLayer=true;r.layer?.backgroundColor=NSColor.controlBackgroundColor.cgColor;r.layer?.cornerRadius=10;r.edgeInsets=NSEdgeInsets(top:12,left:14,bottom:12,right:14);r.translatesAutoresizingMaskIntoConstraints=false
   let text=NSStackView();text.orientation = .vertical;text.alignment = .leading;text.spacing=5
   let title=NSTextField(labelWithString:item["title"] as? String ?? "Game");title.lineBreakMode = .byTruncatingTail;title.font = .systemFont(ofSize:13,weight:.medium);text.addArrangedSubview(title)
   let verified=item["verified"] as? Bool ?? false
   let tested=item["tested"] as? Bool ?? false
   let badge=NSTextField(labelWithString:verified ? "✓ Verified" : (tested ? "◉ Tested" : "○ Untested"));badge.font = .systemFont(ofSize:11,weight:.semibold);badge.textColor=verified ? .systemGreen : (tested ? .systemOrange : .secondaryLabelColor);badge.toolTip=item["verificationSource"] as? String ?? "Gameplay has not been verified.";text.addArrangedSubview(badge)
   let engine=NSTextField(labelWithString:(item["engine"] as? String ?? "Unknown engine")+" · "+((item["profileSource"] as? String == "engine") ? "Automatic profile" : "Game profile"));engine.font = .systemFont(ofSize:11);engine.textColor = .secondaryLabelColor;text.addArrangedSubview(engine)
   if item["supported"] as? Bool != true{let unsupported=NSTextField(labelWithString:"This APK is not supported yet");unsupported.font = .systemFont(ofSize:11);unsupported.textColor = .systemOrange;text.addArrangedSubview(unsupported)}
   r.addArrangedSubview(text);let b=NSButton(title:"▶ Launch in VR",target:self,action:#selector(self.launch(_:)));b.contentTintColor = .systemGreen;b.tag=i;b.setContentCompressionResistancePriority(.required,for:.horizontal);r.addArrangedSubview(b);self.launchButtons.append(b);self.stack.addArrangedSubview(r);r.widthAnchor.constraint(equalTo:self.stack.widthAnchor).isActive=true
  }
  if self.preparing || self.game?.isRunning == true{for b in self.launchButtons{b.isEnabled=false}}else{self.state("Ready",list.isEmpty ? "No APKs found. Choose your games folder.":"\(list.count) games found. Connect your Quest in MoltenVR before launching.",.secondaryLabelColor)}
 }}
 @objc func launch(_ b:NSButton){guard !preparing && game?.isRunning != true else{return};let item=items[b.tag];preparing=true;stopping=false;let title=item["title"] as? String ?? "Game";state("Preparing",title+" — first launch may take a while.",.systemOrange,true);backend("prepare",item["path"] as! String){obj in
  self.preparing=false;guard let d=obj as? [String:Any],let exe=d["executable"] as? String else{self.state("Error",(obj as? [String:String])?["error"] ?? "Preparation failed",.systemRed);return}
  let p=Process();p.executableURL=URL(fileURLWithPath:exe);p.arguments=d["args"] as? [String];p.currentDirectoryURL=URL(fileURLWithPath:d["cwd"] as! String)
  var env=ProcessInfo.processInfo.environment;for k in env.keys where k.hasPrefix("KL_"){env.removeValue(forKey:k)};for k in ["VERANTYX_SHARED_FRAME","VERANTYX_BENCH","XR_RUNTIME_JSON"]{env.removeValue(forKey:k)};env.merge(d["env"] as! [String:String]){_,v in v};p.environment=env
  guard let log=d["log"] as? String else{self.state("Error","Log path is missing.",.systemRed);return};self.logPath=log;FileManager.default.createFile(atPath:log,contents:nil)
  guard let file=FileHandle(forWritingAtPath:log) else{self.state("Error","Could not open the game log.",.systemRed);return};p.standardOutput=file;p.standardError=file
  p.terminationHandler={proc in try? file.close();DispatchQueue.main.async{let stopped=self.stopping;self.game=nil;self.stopping=false;self.state(stopped ? "Stopped" : (proc.terminationStatus == 0 ? "Finished" : "Game exited"),stopped ? "The game has stopped." : "\(title) exited (\(proc.terminationStatus)).",stopped || proc.terminationStatus == 0 ? .secondaryLabelColor : .systemRed)}}
  do{try p.run();self.game=p;self.state("Running",title+" — running in MoltenVR.",.systemGreen)}catch{try? file.close();self.state("Error",error.localizedDescription,.systemRed)}
 }}
 @objc func stop(){guard let p=game,p.isRunning else{return};stopping=true;state("Stopping","Waiting for the game to exit…",.systemRed,true);p.terminate()}
 @objc func log(){if let s=logPath{NSWorkspace.shared.open(URL(fileURLWithPath:s))}}
 func applicationShouldTerminateAfterLastWindowClosed(_ s:NSApplication)->Bool{return true}
 func applicationWillTerminate(_ n:Notification){game?.terminate()}
}
let app=NSApplication.shared;let delegate=Launcher();app.delegate=delegate;app.setActivationPolicy(.regular);app.run()
