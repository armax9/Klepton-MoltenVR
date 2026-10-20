// Native macOS OpenXR frontend for Klepton. No Android VM or CPU image readback.
#define XR_NO_PROTOTYPES
#define XR_USE_GRAPHICS_API_METAL
#define XR_USE_TIMESPEC
#import <Metal/Metal.h>
#import <AVFoundation/AVFoundation.h>
#import <CoreVideo/CoreVideo.h>
#include <simd/simd.h>
#include <openxr/openxr.h>
#include <openxr/openxr_platform.h>
#include "openxr_loader_negotiation.h"
#include <dlfcn.h>
#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <cmath>
#include <vector>
#include <mutex>
#include <condition_variable>
#include <chrono>
#include <atomic>
#include <csignal>
#include <unistd.h>
#include "kl_stereo_head.hpp"
extern "C" {
#include "kl_view.h"
#include "kl_ovrp.h"
#include "kl_openxr.h"
#include "kl_glfb.h"
#include "kl_vulkan.h"
#include "kl_reproject.h"
}

extern "C" void *objc_autoreleasePoolPush(void);
extern "C" void objc_autoreleasePoolPop(void *);
static thread_local void *guestFramePool=nullptr;
static std::atomic<uint64_t> guestPoolsOpened{0},guestPoolsDrained{0};
extern "C" void kl_moltenvr_guest_pool_begin(void) {
 if(!getenv("KL_MOLTENVR_GUEST_POOL")||guestFramePool)return;
 guestFramePool=objc_autoreleasePoolPush();guestPoolsOpened++;
}
extern "C" void kl_moltenvr_guest_pool_end(void) {
 if(!guestFramePool)return;
 void *pool=guestFramePool;guestFramePool=nullptr;
 objc_autoreleasePoolPop(pool);guestPoolsDrained++;
}
struct RetiredTexture { __weak id<MTLTexture> texture; uint64_t image; double retired; };
static RetiredTexture retiredTextures[2048];
static std::mutex retiredTextureMutex;
static uint64_t retiredTextureCount,retiredTextureOverflow;
static std::atomic<uint64_t> retiredDepthPurged{0},retiredDepthBytes{0};
extern "C" int kl_moltenvr_discard_dead_depth(void *texture) { @autoreleasepool {
 id<MTLTexture> t=(__bridge id<MTLTexture>)texture;
 if(!t||t.sampleCount<=1||t.storageMode==MTLStorageModeMemoryless||t.heap||t.parentTexture||t.iosurface)return 0;
 auto f=t.pixelFormat;
 if(f!=MTLPixelFormatDepth32Float&&f!=MTLPixelFormatDepth32Float_Stencil8&&f!=MTLPixelFormatDepth16Unorm&&f!=MTLPixelFormatDepth24Unorm_Stencil8)return 0;
 uint64_t bytes=t.allocatedSize;
 // vkDestroyImage requires all submitted uses to have completed. The contents
 // of this non-aliased, standalone depth image can never be used legally again.
 [t setPurgeableState:MTLPurgeableStateEmpty];
 retiredDepthPurged++;retiredDepthBytes+=bytes;return 1;
}}
extern "C" void kl_moltenvr_retire_texture(void *texture,uint64_t image) {
 if(!texture)return;
 std::lock_guard<std::mutex> lock(retiredTextureMutex);
 for(auto &r:retiredTextures)if(!r.texture){r.texture=(__bridge id<MTLTexture>)texture;r.image=image;r.retired=CACurrentMediaTime();retiredTextureCount++;return;}
 retiredTextureOverflow++;
}
static void reportRetiredTextures(void) { @autoreleasepool {
 std::lock_guard<std::mutex> lock(retiredTextureMutex);
 unsigned alive=0;uint64_t bytes=0;double now=CACurrentMediaTime();unsigned printed=0;
 for(auto &r:retiredTextures){id<MTLTexture> t=r.texture;if(!t||now-r.retired<1.0)continue;alive++;bytes+=t.allocatedSize;
  if(printed++<4)fprintf(stderr,"  [metal-retired] VkImage=%#llx still alive %.1fs %lux%lu samples=%lu allocated=%llu MiB storage=%lu heap=%p\n",(unsigned long long)r.image,now-r.retired,(unsigned long)t.width,(unsigned long)t.height,(unsigned long)t.sampleCount,(unsigned long long)(t.allocatedSize>>20),(unsigned long)t.storageMode,(__bridge void*)t.heap);
 }
 fprintf(stderr,"  [metal-retired] observed=%llu alive-after-1s=%u size=%llu MiB overflow=%llu (weak references only)\n",(unsigned long long)retiredTextureCount,alive,(unsigned long long)(bytes>>20),(unsigned long long)retiredTextureOverflow);
}}
extern "C" void kl_moltenvr_memory_report(void) {
 fprintf(stderr,"  [metal-retired] dead depth storage discarded: count=%llu total=%llu MiB\n",(unsigned long long)retiredDepthPurged.load(),(unsigned long long)(retiredDepthBytes.load()>>20));
 reportRetiredTextures();
 static id<MTLDevice> gpu=MTLCreateSystemDefaultDevice();
 fprintf(stderr,"  [metal-mem] actual device allocations=%llu MiB\n",(unsigned long long)(gpu.currentAllocatedSize>>20));
 fprintf(stderr,"  [metal-mem] frame pools: opened=%llu drained=%llu\n",(unsigned long long)guestPoolsOpened.load(),(unsigned long long)guestPoolsDrained.load());
}

#define XR_FUNCTIONS(F) \
 F(xrCreateInstance) F(xrDestroyInstance) F(xrEnumerateInstanceExtensionProperties) \
 F(xrGetSystem) F(xrGetMetalGraphicsRequirementsKHR) F(xrCreateSession) F(xrDestroySession) \
 F(xrPollEvent) F(xrBeginSession) F(xrEndSession) F(xrCreateReferenceSpace) F(xrDestroySpace) \
 F(xrEnumerateViewConfigurationViews) F(xrEnumerateSwapchainFormats) F(xrCreateSwapchain) \
 F(xrDestroySwapchain) F(xrEnumerateSwapchainImages) F(xrWaitFrame) F(xrBeginFrame) F(xrEndFrame) \
 F(xrLocateViews) F(xrLocateSpace) F(xrAcquireSwapchainImage) F(xrWaitSwapchainImage) F(xrReleaseSwapchainImage) \
 F(xrStringToPath) F(xrCreateActionSet) F(xrDestroyActionSet) F(xrCreateAction) \
 F(xrSuggestInteractionProfileBindings) F(xrCreateActionSpace) F(xrAttachSessionActionSets) \
 F(xrSyncActions) F(xrGetActionStatePose) F(xrGetActionStateFloat) F(xrGetActionStateBoolean) \
 F(xrGetActionStateVector2f) F(xrApplyHapticFeedback)
static struct Api {
#define FIELD(n) PFN_##n n = nullptr;
 XR_FUNCTIONS(FIELD)
#undef FIELD
 PFN_xrGetInstanceProcAddr get = nullptr;
 PFN_xrConvertTimeToTimespecTimeKHR toTime = nullptr;
} api;
static void xrcheck(XrResult r, const char *where) {
 if (XR_FAILED(r)) { fprintf(stderr,"[moltenvr] %s failed: %d\n",where,int(r)); std::exit(2); }
}
static void load(const char *name, PFN_xrVoidFunction *out, XrInstance instance) {
 xrcheck(api.get(instance,name,out),name);
 if (!*out) { fprintf(stderr,"[moltenvr] missing %s\n",name); std::exit(2); }
}
static std::mutex clockMutex;
static std::condition_variable clockCv;
static uint64_t tick=0, consumed=0;
static std::atomic<bool> stopped{false};
static volatile sig_atomic_t interrupted=0;
static void signal_stop(int) { interrupted=1; }
extern "C" void kl_view_pace_wait(void) {
 std::unique_lock<std::mutex> lock(clockMutex);
 clockCv.wait_for(lock,std::chrono::milliseconds(100),[]{return stopped||tick!=consumed;});
 consumed=tick;
}
extern "C" void kl_view_pace_publish(void) {
 { std::lock_guard<std::mutex> lock(clockMutex); ++tick; } clockCv.notify_all();
}
extern "C" void kl_view_pace_stop(void) { stopped=true; clockCv.notify_all(); }
extern "C" void kl_view_frame_sink(const uint8_t *,int,int,void *) {}

static XrInstance instance{};
static XrSystemId systemId{};
static XrSession session{};
static XrSpace localSpace{}, stageSpace{}, headSpace{};
static bool haveStage=false, initialized=false, running=false;
static id<MTLDevice> device;
static id<MTLCommandQueue> queue;
static id<MTLRenderPipelineState> pipeline2d, pipelineArray;
static id<MTLSamplerState> sampler;
static id<MTLRenderPipelineState> loadingPipeline, panelPipeline;
static AVPlayer *loadingPlayer;
static id loadingEndObserver;
static AVPlayerItemVideoOutput *loadingOutput;
static CVMetalTextureCacheRef loadingCache;
static CVMetalTextureRef loadingFrame;
static id<MTLTexture> loadingTexture;
static unsigned loadingGeneration=~0u;
static bool loadingWasActive=false;
static id<MTLSharedEvent> sharedEvent;
static MTLPixelFormat pixelFormat;
static XrViewConfigurationView sizes[2]={{XR_TYPE_VIEW_CONFIGURATION_VIEW},{XR_TYPE_VIEW_CONFIGURATION_VIEW}};
struct Chain { XrSwapchain handle{}; std::vector<XrSwapchainImageMetalKHR> images; uint32_t width=0,height=0; };
static Chain eyes[2];
static Chain panels[16][2];
static double frequency=72;
static std::vector<XrTime> pendingRecenters;
static XrTime lastRecenter=0,lastRecenterDelivery=0;
static bool haveLocalStage=false;
static XrPosef previousLocalStage{};
static void deliverRecenter(XrTime time,const char *why) {
 if(lastRecenterDelivery && time-lastRecenterDelivery<500000000LL)return;
 lastRecenterDelivery=time;kl_ovrp_notify_recenter();
 fprintf(stderr,"[moltenvr] recenter delivered to guest (%s)\n",why);
}

static XrQuaternionf inverse(XrQuaternionf q) { return {-q.x,-q.y,-q.z,q.w}; }
static XrQuaternionf multiply(XrQuaternionf a,XrQuaternionf b) {
 return {a.w*b.x+a.x*b.w+a.y*b.z-a.z*b.y,
         a.w*b.y-a.x*b.z+a.y*b.w+a.z*b.x,
         a.w*b.z+a.x*b.y-a.y*b.x+a.z*b.w,
         a.w*b.w-a.x*b.x-a.y*b.y-a.z*b.z};
}
static XrVector3f rotate(XrQuaternionf q,XrVector3f p) {
 XrQuaternionf r=multiply(multiply(q,{p.x,p.y,p.z,0}),inverse(q));return {r.x,r.y,r.z};
}
static double seconds(XrTime time) {
 timespec ts{};
 if(api.toTime&&XR_SUCCEEDED(api.toTime(instance,time,&ts)))return double(ts.tv_sec)+ts.tv_nsec*1e-9;
 clock_gettime(CLOCK_MONOTONIC,&ts);return double(ts.tv_sec)+ts.tv_nsec*1e-9;
}
static XrPath path(const char *text) { XrPath p{};xrcheck(api.xrStringToPath(instance,text,&p),text);return p; }
struct Inputs {
 XrActionSet set{};XrPath hands[2]{};XrSpace spaces[2]{},aimSpaces[2]{};
 XrAction pose{},aim{}, trigger{},grip{},stick{},click{},touch{},primary{},secondary{},menu{},haptic{};
 XrAction create(const char *name,XrActionType type) {
  XrActionCreateInfo ci{XR_TYPE_ACTION_CREATE_INFO};strcpy(ci.actionName,name);strcpy(ci.localizedActionName,name);
  ci.actionType=type;ci.countSubactionPaths=2;ci.subactionPaths=hands;
  XrAction a{};xrcheck(api.xrCreateAction(set,&ci,&a),name);return a;
 }
 void init() {
  hands[0]=path("/user/hand/left");hands[1]=path("/user/hand/right");
  XrActionSetCreateInfo ci{XR_TYPE_ACTION_SET_CREATE_INFO};strcpy(ci.actionSetName,"klepton");strcpy(ci.localizedActionSetName,"Klepton controllers");
  xrcheck(api.xrCreateActionSet(instance,&ci,&set),"create action set");
  pose=create("grip_pose",XR_ACTION_TYPE_POSE_INPUT);aim=create("aim_pose",XR_ACTION_TYPE_POSE_INPUT);trigger=create("trigger",XR_ACTION_TYPE_FLOAT_INPUT);
  grip=create("grip",XR_ACTION_TYPE_FLOAT_INPUT);stick=create("stick",XR_ACTION_TYPE_VECTOR2F_INPUT);
  click=create("stick_click",XR_ACTION_TYPE_BOOLEAN_INPUT);touch=create("stick_touch",XR_ACTION_TYPE_BOOLEAN_INPUT);
  primary=create("primary",XR_ACTION_TYPE_BOOLEAN_INPUT);secondary=create("secondary",XR_ACTION_TYPE_BOOLEAN_INPUT);
  menu=create("menu",XR_ACTION_TYPE_BOOLEAN_INPUT);haptic=create("vibration",XR_ACTION_TYPE_VIBRATION_OUTPUT);
  std::vector<XrActionSuggestedBinding> bindings;
  auto bind=[&](XrAction a,int hand,const char *component){char full[180];snprintf(full,sizeof(full),"/user/hand/%s/%s",hand?"right":"left",component);bindings.push_back({a,path(full)});};
  for(int h=0;h<2;h++) {
   bind(pose,h,"input/grip/pose");bind(aim,h,"input/aim/pose");bind(trigger,h,"input/trigger/value");bind(grip,h,"input/squeeze/value");
   bind(stick,h,"input/thumbstick");bind(click,h,"input/thumbstick/click");bind(touch,h,"input/thumbstick/touch");bind(haptic,h,"output/haptic");
  }
  bind(primary,0,"input/x/click");bind(secondary,0,"input/y/click");bind(primary,1,"input/a/click");bind(secondary,1,"input/b/click");bind(menu,0,"input/menu/click");
  XrInteractionProfileSuggestedBinding sb{XR_TYPE_INTERACTION_PROFILE_SUGGESTED_BINDING};sb.interactionProfile=path("/interaction_profiles/oculus/touch_controller");sb.countSuggestedBindings=uint32_t(bindings.size());sb.suggestedBindings=bindings.data();xrcheck(api.xrSuggestInteractionProfileBindings(instance,&sb),"Touch bindings");
  for(int h=0;h<2;h++){XrActionSpaceCreateInfo ai{XR_TYPE_ACTION_SPACE_CREATE_INFO};ai.action=pose;ai.subactionPath=hands[h];ai.poseInActionSpace.orientation.w=1;xrcheck(api.xrCreateActionSpace(session,&ai,&spaces[h]),"controller space");ai.action=aim;xrcheck(api.xrCreateActionSpace(session,&ai,&aimSpaces[h]),"controller aim space");}
  XrSessionActionSetsAttachInfo ai{XR_TYPE_SESSION_ACTION_SETS_ATTACH_INFO};ai.countActionSets=1;ai.actionSets=&set;xrcheck(api.xrAttachSessionActionSets(session,&ai),"attach actions");
 }
 XrActionStateGetInfo info(XrAction a,int h) {XrActionStateGetInfo i{XR_TYPE_ACTION_STATE_GET_INFO};i.action=a;i.subactionPath=hands[h];return i;}
 float scalar(XrAction a,int h){auto i=info(a,h);XrActionStateFloat s{XR_TYPE_ACTION_STATE_FLOAT};xrcheck(api.xrGetActionStateFloat(session,&i,&s),"analog input");return s.isActive?s.currentState:0;}
 bool button(XrAction a,int h){auto i=info(a,h);XrActionStateBoolean s{XR_TYPE_ACTION_STATE_BOOLEAN};xrcheck(api.xrGetActionStateBoolean(session,&i,&s),"button input");return s.isActive&&s.currentState;}
 void update(XrSpace base,XrTime time) {
  XrActiveActionSet active{set,XR_NULL_PATH};XrActionsSyncInfo si{XR_TYPE_ACTIONS_SYNC_INFO};si.countActiveActionSets=1;si.activeActionSets=&active;
  XrResult result=api.xrSyncActions(session,&si);bool focused=result!=XR_SESSION_NOT_FOCUSED;if(focused)xrcheck(result,"sync actions");
  for(int h=0;h<2;h++) {
   uint32_t buttons=0,touches=0;float t=0,g=0,x=0,y=0;
   if(!focused)kl_openxr_set_native_aim(h,nullptr,0);
   if(focused) {
    auto pi=info(pose,h);XrActionStatePose ps{XR_TYPE_ACTION_STATE_POSE};xrcheck(api.xrGetActionStatePose(session,&pi,&ps),"pose state");
    XrSpaceVelocity v{XR_TYPE_SPACE_VELOCITY};XrSpaceLocation l{XR_TYPE_SPACE_LOCATION};l.next=&v;
    if(ps.isActive&&XR_SUCCEEDED(api.xrLocateSpace(spaces[h],base,time,&l))&&(l.locationFlags&XR_SPACE_LOCATION_POSITION_VALID_BIT)&&(l.locationFlags&XR_SPACE_LOCATION_ORIENTATION_VALID_BIT)) {
     auto p=l.pose.position;auto q=l.pose.orientation;
     auto aimInfo=info(aim,h);XrActionStatePose aps{XR_TYPE_ACTION_STATE_POSE};xrcheck(api.xrGetActionStatePose(session,&aimInfo,&aps),"aim state");
     XrSpaceLocation al{XR_TYPE_SPACE_LOCATION};
     if(aps.isActive&&XR_SUCCEEDED(api.xrLocateSpace(aimSpaces[h],base,time,&al))&&
        (al.locationFlags&XR_SPACE_LOCATION_POSITION_VALID_BIT)&&(al.locationFlags&XR_SPACE_LOCATION_ORIENTATION_VALID_BIT)) {
        auto aq=multiply(inverse(q),al.pose.orientation);auto ap=al.pose.position;
        auto dp=rotate(inverse(q),{ap.x-p.x,ap.y-p.y,ap.z-p.z});float delta[7]={aq.x,aq.y,aq.z,aq.w,dp.x,dp.y,dp.z};kl_openxr_set_native_aim(h,delta,1);
     } else kl_openxr_set_native_aim(h,nullptr,0);
     if((v.velocityFlags&XR_SPACE_VELOCITY_LINEAR_VALID_BIT)&&(v.velocityFlags&XR_SPACE_VELOCITY_ANGULAR_VALID_BIT))
      kl_ovrp_set_hand_motion(h,p.x,p.y,p.z,q.x,q.y,q.z,q.w,v.linearVelocity.x,v.linearVelocity.y,v.linearVelocity.z,v.angularVelocity.x,v.angularVelocity.y,v.angularVelocity.z);
     else kl_ovrp_set_hand_pose(h,p.x,p.y,p.z,q.x,q.y,q.z,q.w);
    }
    t=scalar(trigger,h);g=scalar(grip,h);auto ii=info(stick,h);XrActionStateVector2f sv{XR_TYPE_ACTION_STATE_VECTOR2F};xrcheck(api.xrGetActionStateVector2f(session,&ii,&sv),"stick");if(sv.isActive){x=sv.currentState.x;y=sv.currentState.y;}
    if(button(primary,h))buttons|=h?KL_OVRP_RAW_A:KL_OVRP_RAW_X;
    if(button(secondary,h))buttons|=h?KL_OVRP_RAW_B:KL_OVRP_RAW_Y;
    if(button(click,h))buttons|=h?KL_OVRP_RAW_RTHUMBSTICK:KL_OVRP_RAW_LTHUMBSTICK;
    if(button(menu,h))buttons|=KL_OVRP_RAW_START;
    if(t>.75f)buttons|=h?KL_OVRP_RAW_RINDEX_TRIGGER:KL_OVRP_RAW_LINDEX_TRIGGER;
    if(g>.75f)buttons|=h?KL_OVRP_RAW_RHAND_TRIGGER:KL_OVRP_RAW_LHAND_TRIGGER;
    if(button(touch,h))touches|=h?0x4:0x400;
    if(t>.05f)touches|=h?0x10:0x1000;
   }
   kl_ovrp_set_controller_input(h,buttons,touches,t,g,x,y);
   float amp=0,duration=0;
   if(kl_ovrp_haptics_pull(h,&amp,&duration)&&focused&&amp>0) {
    XrHapticVibration vib{XR_TYPE_HAPTIC_VIBRATION};vib.amplitude=fminf(amp,1);vib.duration=XrDuration(fminf(duration,.5f)*1e9);vib.frequency=XR_FREQUENCY_UNSPECIFIED;
    XrHapticActionInfo hi{XR_TYPE_HAPTIC_ACTION_INFO};hi.action=haptic;hi.subactionPath=hands[h];api.xrApplyHapticFeedback(session,&hi,(XrHapticBaseHeader*)&vib);
   }
  }
 }
} inputs;

static Chain createChain(uint32_t width,uint32_t height) {
 Chain c;c.width=width;c.height=height;XrSwapchainCreateInfo ci{XR_TYPE_SWAPCHAIN_CREATE_INFO};ci.usageFlags=XR_SWAPCHAIN_USAGE_COLOR_ATTACHMENT_BIT|XR_SWAPCHAIN_USAGE_SAMPLED_BIT;ci.format=pixelFormat;ci.sampleCount=ci.arraySize=ci.faceCount=ci.mipCount=1;ci.width=width;ci.height=height;
 xrcheck(api.xrCreateSwapchain(session,&ci,&c.handle),"Metal swapchain");uint32_t n=0;xrcheck(api.xrEnumerateSwapchainImages(c.handle,0,&n,nullptr),"image count");c.images.resize(n,{XR_TYPE_SWAPCHAIN_IMAGE_METAL_KHR});xrcheck(api.xrEnumerateSwapchainImages(c.handle,n,&n,(XrSwapchainImageBaseHeader*)c.images.data()),"Metal images");return c;
}
static void init() {
 if(initialized)return;
 setvbuf(stdout,nullptr,_IOLBF,0);
 char library[4096];snprintf(library,sizeof(library),"%s/Library/Application Support/MoltenVR/bin/libmoltenvr_openxr.dylib",getenv("HOME"));
 void *handle=dlopen(library,RTLD_NOW|RTLD_LOCAL);if(!handle){fprintf(stderr,"[moltenvr] %s\n",dlerror());std::exit(2);}
 auto negotiate=(PFN_xrNegotiateLoaderRuntimeInterface)dlsym(handle,"xrNegotiateLoaderRuntimeInterface");if(!negotiate)std::exit(2);
 XrNegotiateLoaderInfo li{};li.structType=XR_LOADER_INTERFACE_STRUCT_LOADER_INFO;li.structVersion=1;li.structSize=sizeof(li);li.minInterfaceVersion=li.maxInterfaceVersion=1;li.minApiVersion=XR_MAKE_VERSION(1,0,0);li.maxApiVersion=XR_MAKE_VERSION(1,1,0);
 XrNegotiateRuntimeRequest rr{};rr.structType=XR_LOADER_INTERFACE_STRUCT_RUNTIME_REQUEST;rr.structVersion=1;rr.structSize=sizeof(rr);xrcheck(negotiate(&li,&rr),"negotiate runtime");api.get=rr.getInstanceProcAddr;
 load("xrEnumerateInstanceExtensionProperties",(PFN_xrVoidFunction*)&api.xrEnumerateInstanceExtensionProperties,{});load("xrCreateInstance",(PFN_xrVoidFunction*)&api.xrCreateInstance,{});
 uint32_t n=0;xrcheck(api.xrEnumerateInstanceExtensionProperties(nullptr,0,&n,nullptr),"extensions");std::vector<XrExtensionProperties> ep(n,{XR_TYPE_EXTENSION_PROPERTIES});xrcheck(api.xrEnumerateInstanceExtensionProperties(nullptr,n,&n,ep.data()),"extensions");
 bool metal=false,clock=false;for(auto &e:ep){metal|=!strcmp(e.extensionName,"XR_KHR_metal_enable");clock|=!strcmp(e.extensionName,"XR_KHR_convert_timespec_time");}
 if(!metal){fprintf(stderr,"[moltenvr] runtime has no native Metal support\n");std::exit(2);}
 const char *extensions[]={"XR_KHR_metal_enable","XR_KHR_convert_timespec_time"};XrInstanceCreateInfo ci{XR_TYPE_INSTANCE_CREATE_INFO};strcpy(ci.applicationInfo.applicationName,"Klepton APK native Metal");ci.applicationInfo.apiVersion=XR_MAKE_VERSION(1,0,0);ci.enabledExtensionCount=clock?2:1;ci.enabledExtensionNames=extensions;xrcheck(api.xrCreateInstance(&ci,&instance),"create instance");
#define RESOLVE(n) load(#n,(PFN_xrVoidFunction*)&api.n,instance);
 XR_FUNCTIONS(RESOLVE)
#undef RESOLVE
 if(clock)load("xrConvertTimeToTimespecTimeKHR",(PFN_xrVoidFunction*)&api.toTime,instance);
 XrSystemGetInfo si{XR_TYPE_SYSTEM_GET_INFO};si.formFactor=XR_FORM_FACTOR_HEAD_MOUNTED_DISPLAY;xrcheck(api.xrGetSystem(instance,&si,&systemId),"get headset");
 XrGraphicsRequirementsMetalKHR req{XR_TYPE_GRAPHICS_REQUIREMENTS_METAL_KHR};xrcheck(api.xrGetMetalGraphicsRequirementsKHR(instance,systemId,&req),"Metal requirements");device=(__bridge id<MTLDevice>)req.metalDevice;if(!device)device=MTLCreateSystemDefaultDevice();queue=[device newCommandQueue];
 XrGraphicsBindingMetalKHR binding{XR_TYPE_GRAPHICS_BINDING_METAL_KHR};binding.commandQueue=(__bridge void*)queue;XrSessionCreateInfo sci{XR_TYPE_SESSION_CREATE_INFO};sci.next=&binding;sci.systemId=systemId;xrcheck(api.xrCreateSession(instance,&sci,&session),"create Metal session");
 XrReferenceSpaceCreateInfo ri{XR_TYPE_REFERENCE_SPACE_CREATE_INFO};ri.poseInReferenceSpace.orientation.w=1;ri.referenceSpaceType=XR_REFERENCE_SPACE_TYPE_LOCAL;xrcheck(api.xrCreateReferenceSpace(session,&ri,&localSpace),"local space");ri.referenceSpaceType=XR_REFERENCE_SPACE_TYPE_STAGE;haveStage=XR_SUCCEEDED(api.xrCreateReferenceSpace(session,&ri,&stageSpace));ri.referenceSpaceType=XR_REFERENCE_SPACE_TYPE_VIEW;xrcheck(api.xrCreateReferenceSpace(session,&ri,&headSpace),"head space");
 uint32_t count=0;xrcheck(api.xrEnumerateViewConfigurationViews(instance,systemId,XR_VIEW_CONFIGURATION_TYPE_PRIMARY_STEREO,2,&count,sizes),"stereo sizes");if(count!=2)std::exit(2);
 xrcheck(api.xrEnumerateSwapchainFormats(session,0,&n,nullptr),"formats");std::vector<int64_t> formats(n);xrcheck(api.xrEnumerateSwapchainFormats(session,n,&n,formats.data()),"formats");pixelFormat=MTLPixelFormatInvalid;
 for(auto wanted:{MTLPixelFormatBGRA8Unorm_sRGB,MTLPixelFormatRGBA8Unorm_sRGB,MTLPixelFormatBGRA8Unorm,MTLPixelFormatRGBA8Unorm})for(auto f:formats)if(pixelFormat==MTLPixelFormatInvalid&&f==wanted)pixelFormat=wanted;
 if(pixelFormat==MTLPixelFormatInvalid){fprintf(stderr,"[moltenvr] no compatible Metal color format\n");std::exit(2);}
 for(int e=0;e<2;e++)eyes[e]=createChain(sizes[e].recommendedImageRectWidth,sizes[e].recommendedImageRectHeight);
 kl_ovrp_set_eye_texture_size(sizes[0].recommendedImageRectWidth,sizes[0].recommendedImageRectHeight);
 inputs.init();initialized=true;fprintf(stderr,"[moltenvr] native Metal session, %ux%u per eye, format %lu\n",sizes[0].recommendedImageRectWidth,sizes[0].recommendedImageRectHeight,(unsigned long)pixelFormat);
}

extern "C" unsigned kl_visual_probe_shot(void);
extern "C" int kl_visual_write_png(const char*,const uint8_t*,int,int);
static unsigned lastVisualShot;
static const char *shader=R"MSL(
#include <metal_stdlib>
using namespace metal;
struct V {float4 p[[position]];float2 uv;};
struct Params {float4 rect;float4 uvmap;uint slice;uint flip;uint encode;uint pad;float4 rotation;float4 rendered;float4 display;uint warp;};
vertex V vertex_main(uint i[[vertex_id]]){float2 p=float2((i<<1)&2,i&2);return {float4(p*2-1,0,1),float2(p.x,1-p.y)};}
float4 color(float4 c,constant Params&p){if(p.encode)c.rgb=select(1.055*pow(max(c.rgb,0.0),float3(1.0/2.4))-0.055,12.92*c.rgb,c.rgb<=0.0031308);return float4(c.rgb,p.pad ? c.a : 1.0);}
float2 sourceUV(float2 uv,constant Params&p){
 if(!p.warp)return p.uvmap.xy+uv*p.uvmap.zw;
 float3 ray=float3(mix(-p.display.x,p.display.y,uv.x),mix(p.display.z,-p.display.w,uv.y),-1);
 float3 rotated=ray+2*cross(p.rotation.xyz,cross(p.rotation.xyz,ray)+p.rotation.w*ray);
 if(rotated.z>=-0.00001)return float2(-1);
 float2 slope=rotated.xy/-rotated.z;
 return float2((slope.x+p.rendered.x)/(p.rendered.x+p.rendered.y),(p.rendered.z-slope.y)/(p.rendered.z+p.rendered.w));
}
fragment float4 frag2d(V v[[stage_in]],texture2d<float> t[[texture(0)]],sampler s[[sampler(0)]],constant Params&p[[buffer(0)]]){float2 uv=sourceUV(v.uv,p);if(any(uv<0.0)||any(uv>1.0))return float4(0,0,0,1);if(p.flip)uv.y=1-uv.y;return color(t.sample(s,p.rect.xy+uv*p.rect.zw),p);}
fragment float4 fragarray(V v[[stage_in]],texture2d_array<float> t[[texture(0)]],sampler s[[sampler(0)]],constant Params&p[[buffer(0)]]){float2 uv=sourceUV(v.uv,p);if(any(uv<0.0)||any(uv>1.0))return float4(0,0,0,1);if(p.flip)uv.y=1-uv.y;return color(t.sample(s,p.rect.xy+uv*p.rect.zw,p.slice),p);}
)MSL";
static void initPipelines() {
 NSError *error=nil;id<MTLLibrary> lib=[device newLibraryWithSource:[NSString stringWithUTF8String:shader] options:nil error:&error];
 if(!lib){fprintf(stderr,"[moltenvr] shader: %s\n",error.localizedDescription.UTF8String);std::exit(2);}
 for(int array=0;array<2;array++) {
  MTLRenderPipelineDescriptor *p=[MTLRenderPipelineDescriptor new];p.vertexFunction=[lib newFunctionWithName:@"vertex_main"];p.fragmentFunction=[lib newFunctionWithName:array?@"fragarray":@"frag2d"];p.colorAttachments[0].pixelFormat=pixelFormat;
  id<MTLRenderPipelineState> result=[device newRenderPipelineStateWithDescriptor:p error:&error];if(!result){fprintf(stderr,"[moltenvr] pipeline: %s\n",error.localizedDescription.UTF8String);std::exit(2);}if(array)pipelineArray=result;else pipeline2d=result;
 }
 MTLSamplerDescriptor *s=[MTLSamplerDescriptor new];s.minFilter=s.magFilter=MTLSamplerMinMagFilterLinear;s.sAddressMode=s.tAddressMode=MTLSamplerAddressModeClampToEdge;sampler=[device newSamplerStateWithDescriptor:s];
}
// The original Quest loading scene may be a video skybox, not an eye image.
// Decode through AVFoundation and share its pixel buffer with Metal directly.
static id<MTLTexture> loadingVideo() {
 bool active=kl_loadingvideo_active()!=0 || getenv("KL_MOLTENVR_VIDEO_TEST_PATH");
 if(!active) {
  if(loadingWasActive){[loadingPlayer pause];loadingPlayer=nil;if(loadingEndObserver){[[NSNotificationCenter defaultCenter] removeObserver:loadingEndObserver];loadingEndObserver=nil;}loadingOutput=nil;loadingTexture=nil;if(loadingFrame){CFRelease(loadingFrame);loadingFrame=nullptr;}loadingGeneration=~0u;}
  loadingWasActive=false;return nil;
 }
 loadingWasActive=true;
 // AVPlayer readiness and playback notifications need the host run loop,
 // which the OpenXR frame loop otherwise never services. Never block here.
 CFRunLoopRunInMode(kCFRunLoopDefaultMode,0,false);
 char source[4096]{}; unsigned gen=kl_loadingvideo_source(source,sizeof(source));
 if(gen!=loadingGeneration) {
  loadingGeneration=gen;[loadingPlayer pause];loadingPlayer=nil;if(loadingEndObserver){[[NSNotificationCenter defaultCenter] removeObserver:loadingEndObserver];loadingEndObserver=nil;}loadingOutput=nil;loadingTexture=nil;
  NSString *path=source[0]?[NSString stringWithUTF8String:source]:nil;
  if(getenv("KL_MOLTENVR_VIDEO_TEST_PATH"))path=[NSString stringWithUTF8String:getenv("KL_MOLTENVR_VIDEO_TEST_PATH")];
  if(!path&&getenv("KL_MOLTENVR_VIDEO_DIR")) {
   NSString *dir=[NSString stringWithUTF8String:getenv("KL_MOLTENVR_VIDEO_DIR")];
   for(NSString *name in @[@"Background-with-Initialisation-Loop.mp4",@"Background-Looping.mp4"]){NSString *candidate=[dir stringByAppendingPathComponent:name];if([[NSFileManager defaultManager] fileExistsAtPath:candidate]){path=candidate;break;}}
  }
  if(path) {
   loadingOutput=[[AVPlayerItemVideoOutput alloc] initWithPixelBufferAttributes:@{(id)kCVPixelBufferPixelFormatTypeKey:@(kCVPixelFormatType_32BGRA),(id)kCVPixelBufferMetalCompatibilityKey:@YES}];
   AVPlayerItem *item=[AVPlayerItem playerItemWithURL:[NSURL fileURLWithPath:path]];[item addOutput:loadingOutput];
   loadingPlayer=[AVPlayer playerWithPlayerItem:item];loadingPlayer.muted=YES;
   loadingEndObserver=[[NSNotificationCenter defaultCenter] addObserverForName:AVPlayerItemDidPlayToEndTimeNotification object:item queue:nil usingBlock:^(NSNotification *){[loadingPlayer seekToTime:kCMTimeZero toleranceBefore:kCMTimeZero toleranceAfter:kCMTimeZero completionHandler:^(BOOL done){if(done)[loadingPlayer play];}];}];[loadingPlayer play];
   fprintf(stderr,"[moltenvr] loading panorama video: %s\n",path.fileSystemRepresentation);
  }
 }
 if(loadingOutput) {
  CMTime time=[loadingOutput itemTimeForHostTime:CACurrentMediaTime()];
  if([loadingOutput hasNewPixelBufferForItemTime:time]) {
   CVPixelBufferRef pixel=[loadingOutput copyPixelBufferForItemTime:time itemTimeForDisplay:nullptr];
   if(pixel) {
    if(!loadingCache)CVMetalTextureCacheCreate(kCFAllocatorDefault,nullptr,device,nullptr,&loadingCache);
    CVMetalTextureRef next=nullptr;
    if(loadingCache&&CVMetalTextureCacheCreateTextureFromImage(kCFAllocatorDefault,loadingCache,pixel,nullptr,MTLPixelFormatBGRA8Unorm,CVPixelBufferGetWidth(pixel),CVPixelBufferGetHeight(pixel),0,&next)==kCVReturnSuccess){loadingTexture=CVMetalTextureGetTexture(next);if(loadingFrame)CFRelease(loadingFrame);loadingFrame=next;static bool first=false;if(!first){first=true;fprintf(stderr,"[moltenvr] first decoded loading video frame: %zux%zu\n",CVPixelBufferGetWidth(pixel),CVPixelBufferGetHeight(pixel));}}
    CVPixelBufferRelease(pixel);
   }
  }
 }
 return loadingTexture;
}
static void drawLoading(id<MTLCommandBuffer> cmd,id<MTLTexture> dst,id<MTLTexture> src,const XrView &view) {
 if(!loadingPipeline) {
  NSError *error=nil;id<MTLLibrary> lib=[device newLibraryWithSource:[NSString stringWithUTF8String:kl_reproject_equirect_msl()] options:nil error:&error];
  MTLRenderPipelineDescriptor *pd=[MTLRenderPipelineDescriptor new];pd.vertexFunction=[lib newFunctionWithName:@"kl_eq_v"];pd.fragmentFunction=[lib newFunctionWithName:@"kl_eq_f"];pd.colorAttachments[0].pixelFormat=pixelFormat;loadingPipeline=[device newRenderPipelineStateWithDescriptor:pd error:&error];
  if(!loadingPipeline){fprintf(stderr,"[moltenvr] loading shader: %s\n",error.localizedDescription.UTF8String);return;}
 }
 struct Eq {simd_float4x4 inv_proj,world_rot;uint32_t slice,flip,srgb,visible,test;float hscale;} u{};
 auto f=view.fov;u.inv_proj=simd_inverse(kl_reproject_projection(-tanf(f.angleLeft),tanf(f.angleRight),tanf(f.angleUp),-tanf(f.angleDown),.03f));
 auto q=view.pose.orientation;
 // Square loading movies span 180 degrees horizontally in the original
 // frontend. A 2:1 panorama spans 360 degrees; retain square angular pixels.
 u.hscale=2.0f*float(src.height)/float(src.width);
 for(int i=0;i<kl_ovrp_overlay_count();i++) {
  kl_ovrp_overlay ov{};if(!kl_ovrp_overlay_get(i,&ov)||ov.shape!=5)continue;
  XrQuaternionf layerRotation{ov.pose[0],ov.pose[1],ov.pose[2],ov.pose[3]};
  if(ov.head_locked){float x,y,z,hx,hy,hz,hw;kl_ovrp_get_head_pose(&x,&y,&z,&hx,&hy,&hz,&hw);layerRotation=multiply({hx,hy,hz,hw},layerRotation);}
  float norm=layerRotation.x*layerRotation.x+layerRotation.y*layerRotation.y+layerRotation.z*layerRotation.z+layerRotation.w*layerRotation.w;
  if(norm>0.5f)q=multiply(inverse(layerRotation),q);
  if(ov.eq_hscale>0)u.hscale=ov.eq_hscale;
  break;
 }
 u.world_rot=simd_matrix4x4(simd_quaternion(q.x,q.y,q.z,q.w));u.visible=1;
 MTLRenderPassDescriptor *rp=[MTLRenderPassDescriptor renderPassDescriptor];rp.colorAttachments[0].texture=dst;rp.colorAttachments[0].loadAction=MTLLoadActionLoad;rp.colorAttachments[0].storeAction=MTLStoreActionStore;
 id<MTLRenderCommandEncoder> enc=[cmd renderCommandEncoderWithDescriptor:rp];[enc setRenderPipelineState:loadingPipeline];[enc setVertexBytes:&u length:sizeof(u) atIndex:0];[enc setFragmentBytes:&u length:sizeof(u) atIndex:0];[enc setFragmentTexture:src atIndex:0];[enc setFragmentSamplerState:sampler atIndex:0];[enc drawPrimitives:MTLPrimitiveTypeTriangle vertexStart:0 vertexCount:3];[enc endEncoding];
}
static simd_float4x4 poseMatrix(XrPosef pose) {
 auto q=pose.orientation;auto m=simd_matrix4x4(simd_quaternion(q.x,q.y,q.z,q.w));m.columns[3]={pose.position.x,pose.position.y,pose.position.z,1};return m;
}
static void drawPanels(id<MTLCommandBuffer> cmd,id<MTLTexture> dst,int eye,XrPosef head,const XrCompositionLayerProjectionView &view) {
 if(!panelPipeline) {
  NSError *error=nil;id<MTLLibrary> lib=[device newLibraryWithSource:[NSString stringWithUTF8String:kl_reproject_overlay_msl()] options:nil error:&error];
  MTLRenderPipelineDescriptor *pd=[MTLRenderPipelineDescriptor new];pd.vertexFunction=[lib newFunctionWithName:@"kl_ov_v"];pd.fragmentFunction=[lib newFunctionWithName:@"kl_ov_f"];auto a=pd.colorAttachments[0];a.pixelFormat=pixelFormat;a.blendingEnabled=YES;a.sourceRGBBlendFactor=MTLBlendFactorSourceAlpha;a.destinationRGBBlendFactor=MTLBlendFactorOneMinusSourceAlpha;a.sourceAlphaBlendFactor=MTLBlendFactorOne;a.destinationAlphaBlendFactor=MTLBlendFactorOneMinusSourceAlpha;
  panelPipeline=[device newRenderPipelineStateWithDescriptor:pd error:&error];if(!panelPipeline){fprintf(stderr,"[moltenvr] panel shader: %s\n",error.localizedDescription.UTF8String);return;}
 }
 auto devicePose=poseMatrix(head);auto eyePose=poseMatrix(view.pose);auto f=view.fov;
 auto projection=kl_reproject_projection(-tanf(f.angleLeft),tanf(f.angleRight),tanf(f.angleUp),-tanf(f.angleDown),.03f);
 MTLRenderPassDescriptor *rp=[MTLRenderPassDescriptor renderPassDescriptor];rp.colorAttachments[0].texture=dst;rp.colorAttachments[0].loadAction=MTLLoadActionLoad;rp.colorAttachments[0].storeAction=MTLStoreActionStore;
 id<MTLRenderCommandEncoder> enc=[cmd renderCommandEncoderWithDescriptor:rp];
 for(int i=0;i<kl_ovrp_overlay_count();i++) {
  kl_ovrp_overlay ov{};if(!kl_ovrp_overlay_get(i,&ov)||(ov.shape!=0&&ov.shape!=1))continue;
  auto u=kl_overlay_build(&ov,eye,devicePose,simd_mul(simd_inverse(devicePose),eyePose),projection);if(!u.visible)continue;
  int w=0,h=0;void *t=kl_vulkan_layer_mtl_texture(ov.layer_id,ov.stage,eye,&w,&h);if(!t)t=kl_glfb_layer_mtl_texture(ov.layer_id,ov.stage,&w,&h);if(!t&&ov.tex)t=kl_vulkan_mtl_for_handle(ov.tex);if(!t)continue;
  id<MTLTexture> texture=(__bridge id<MTLTexture>)t;
  if(texture.textureType!=MTLTextureType2D)continue;
  [enc setRenderPipelineState:panelPipeline];[enc setVertexBytes:&u length:sizeof(u) atIndex:0];[enc setFragmentBytes:&u length:sizeof(u) atIndex:0];[enc setFragmentTexture:texture atIndex:0];[enc setFragmentSamplerState:sampler atIndex:0];[enc drawPrimitives:MTLPrimitiveTypeTriangleStrip vertexStart:0 vertexCount:kl_overlay_strip_vertices(&u)];
 }
 [enc endEncoding];
}
static void draw(id<MTLCommandBuffer> cmd,id<MTLTexture> dst,id<MTLTexture> src,int eye,int slice,const kl_ovrp_render_pose *record,const kl_ovrp_overlay *overlay=nullptr,const XrFovf *nativeFov=nullptr,const XrQuaternionf *displayRotation=nullptr) {
 MTLRenderPassDescriptor *rp=[MTLRenderPassDescriptor renderPassDescriptor];rp.colorAttachments[0].texture=dst;rp.colorAttachments[0].loadAction=MTLLoadActionClear;rp.colorAttachments[0].storeAction=MTLStoreActionStore;rp.colorAttachments[0].clearColor=MTLClearColorMake(.015,.02,.035,1);
 id<MTLRenderCommandEncoder> enc=[cmd renderCommandEncoderWithDescriptor:rp];
 if(src) {
  if(src.device.registryID!=device.registryID){fprintf(stderr,"[moltenvr] guest and runtime use different GPUs\n");std::exit(2);}
  struct Params {simd_float4 rect,uvmap;uint32_t slice,flip,encode,pad;simd_float4 rotation,rendered,display;uint32_t warp;} p{{0,0,1,1},{0,0,1,1},uint32_t(slice),uint32_t(!kl_glfb_eye_mtl_origin_top_left(eye,record?record->stage:0)),uint32_t(pixelFormat!=MTLPixelFormatBGRA8Unorm_sRGB&&pixelFormat!=MTLPixelFormatRGBA8Unorm_sRGB),0};
  if(record&&record->viewport[eye][2]>0&&record->viewport[eye][3]>0) {
   float w=record->viewport_of[0]>0?record->viewport_of[0]:src.width,h=record->viewport_of[1]>0?record->viewport_of[1]:src.height;
   p.rect={record->viewport[eye][0]/w,record->viewport[eye][1]/h,record->viewport[eye][2]/w,record->viewport[eye][3]/h};
  }
  if(nativeFov&&record) {
   // Map destination display rays into the cone actually rendered by the guest.
   // UV origin is top-left; tangents are positive left/right/up/down extents.
   const float *t=record->tangents[eye];
   float l=-tanf(nativeFov->angleLeft),r=tanf(nativeFov->angleRight);
   float u=tanf(nativeFov->angleUp),d=-tanf(nativeFov->angleDown);
   if(t[0]+t[1]>.01f&&t[2]+t[3]>.01f)
    p.uvmap={(t[0]-l)/(t[0]+t[1]),(t[2]-u)/(t[2]+t[3]),(l+r)/(t[0]+t[1]),(u+d)/(t[2]+t[3])};
   if(displayRotation&&t[0]+t[1]>.01f&&t[2]+t[3]>.01f) {
    auto delta=multiply(inverse({record->qx,record->qy,record->qz,record->qw}),*displayRotation);
    p.rotation={delta.x,delta.y,delta.z,delta.w};p.rendered={t[0],t[1],t[2],t[3]};p.display={l,r,u,d};p.warp=1;
   }
  }
  if(overlay) {
   p.pad=1; p.flip=!overlay->origin_top_left;
   auto v=overlay->viewport[eye];
   if(v[2]>0&&v[3]>0)p.rect={float(v[0])/src.width,float(v[1])/src.height,float(v[2])/src.width,float(v[3])/src.height};
  }
  [enc setRenderPipelineState:src.textureType==MTLTextureType2DArray?pipelineArray:pipeline2d];[enc setFragmentTexture:src atIndex:0];[enc setFragmentSamplerState:sampler atIndex:0];[enc setFragmentBytes:&p length:sizeof(p) atIndex:0];[enc drawPrimitives:MTLPrimitiveTypeTriangle vertexStart:0 vertexCount:3];
 }
 [enc endEncoding];
}
extern "C" int kl_moltenvr_rotation_selftest(void) { @autoreleasepool {
 device=MTLCreateSystemDefaultDevice();if(!device)return 1;
 queue=[device newCommandQueue];pixelFormat=MTLPixelFormatRGBA8Unorm;initPipelines();
 kl_ovrp_render_pose record{};record.qw=1;for(int e=0;e<2;e++)for(int i=0;i<4;i++)record.tangents[e][i]=1;
 XrFovf fov{-atanf(1),atanf(1),atanf(1),-atanf(1)};
 int good=1;
 for(int array=0;array<2;array++) {
  auto desc=[MTLTextureDescriptor texture2DDescriptorWithPixelFormat:MTLPixelFormatRGBA8Unorm width:256 height:4 mipmapped:NO];desc.storageMode=MTLStorageModeShared;desc.usage=MTLTextureUsageShaderRead;
  if(array){desc.textureType=MTLTextureType2DArray;desc.arrayLength=2;}
  id<MTLTexture> src=[device newTextureWithDescriptor:desc];
  uint8_t pixels[256*4*4];for(int y=0;y<4;y++)for(int x=0;x<256;x++){int i=(y*256+x)*4;pixels[i]=pixels[i+1]=pixels[i+2]=x;pixels[i+3]=255;}
  for(int slice=0;slice<(array?2:1);slice++)[src replaceRegion:MTLRegionMake2D(0,0,256,4) mipmapLevel:0 slice:slice withBytes:pixels bytesPerRow:1024 bytesPerImage:4096];
  auto outDesc=[MTLTextureDescriptor texture2DDescriptorWithPixelFormat:pixelFormat width:16 height:16 mipmapped:NO];outDesc.storageMode=MTLStorageModeShared;outDesc.usage=MTLTextureUsageRenderTarget;
  id<MTLTexture> dst=[device newTextureWithDescriptor:outDesc];
  for(int direction=-1;direction<=1;direction++) {
   float angle=direction*.174532925f;XrQuaternionf current{0,sinf(angle/2),0,cosf(angle/2)};
   auto cmd=[queue commandBuffer];draw(cmd,dst,src,0,array?1:0,&record,nullptr,&fov,&current);[cmd commit];[cmd waitUntilCompleted];
   uint8_t got[4];[dst getBytes:got bytesPerRow:4 fromRegion:MTLRegionMake2D(8,8,1,1) mipmapLevel:0];
   auto ray=rotate(current,{.0625f,-.0625f,-1});float u=(ray.x/-ray.z+1)*.5f;
   float expected=255*(1.055f*powf(u,1/2.4f)-.055f);
   if(cmd.status==MTLCommandBufferStatusError||fabsf(got[0]-expected)>3){good=0;fprintf(stderr,"FAIL: rotation array=%d direction=%d got=%u expected=%.1f\n",array,direction,got[0],expected);}
  }
 }
 fprintf(stderr,"%s: native GPU rotation mapping, identity and both yaw directions, 2D and array textures\n",good?"PASS":"FAIL");return good?0:1;
}}
extern "C" int kl_view_available(void) {
 if(getenv("KL_MOLTENVR_INIT_ONLY")) {
  init();initPipelines();
  for(auto &c:eyes)for(auto &image:c.images) {
   id<MTLTexture> texture=(__bridge id<MTLTexture>)image.texture;
   if(!texture||texture.device.registryID!=device.registryID){fprintf(stderr,"[moltenvr] invalid swapchain Metal texture\n");std::exit(2);}
  }
  MTLTextureDescriptor *td=[MTLTextureDescriptor texture2DDescriptorWithPixelFormat:pixelFormat width:16 height:16 mipmapped:NO];td.usage=MTLTextureUsageRenderTarget|MTLTextureUsageShaderRead;
  id<MTLTexture> testSrc=[device newTextureWithDescriptor:td],testDst=[device newTextureWithDescriptor:td];
  XrView testView{XR_TYPE_VIEW};testView.pose.orientation.w=1;testView.fov={-.8f,.8f,.8f,-.8f};
  if(getenv("KL_MOLTENVR_VIDEO_TEST_PATH")) {
   for(int i=0;i<300&&!loadingVideo();i++){usleep(10000);}
   if(!loadingTexture){fprintf(stderr,"[moltenvr] video decoder selftest failed, status %ld: %s\n",(long)loadingPlayer.currentItem.status,loadingPlayer.currentItem.error.localizedDescription.UTF8String);std::exit(2);}
  }
  XrCompositionLayerProjectionView panelView{XR_TYPE_COMPOSITION_LAYER_PROJECTION_VIEW};panelView.pose=testView.pose;panelView.fov=testView.fov;
  id<MTLCommandBuffer> testCmd=[queue commandBuffer];drawLoading(testCmd,testDst,testSrc,testView);drawPanels(testCmd,testDst,0,testView.pose,panelView);[testCmd commit];[testCmd waitUntilCompleted];
  if(!loadingPipeline||testCmd.status==MTLCommandBufferStatusError){fprintf(stderr,"[moltenvr] loading compositor selftest failed\n");std::exit(2);}
  if(!kl_openxr_native_pose_selftest()){fprintf(stderr,"[moltenvr] native grip/aim pose selftest failed\n");std::exit(2);}
  fprintf(stderr,"[moltenvr] SELFTEST PASS: native grip/aim separation, Metal session, stereo swapchains, textures, shaders, Touch bindings, loading panorama GPU pass\n");
  for(auto &c:eyes)api.xrDestroySwapchain(c.handle);
  for(auto &s:inputs.spaces)api.xrDestroySpace(s);for(auto &s:inputs.aimSpaces)api.xrDestroySpace(s);
  api.xrDestroySpace(localSpace);if(haveStage)api.xrDestroySpace(stageSpace);api.xrDestroySpace(headSpace);
  api.xrDestroySession(session);api.xrDestroyActionSet(inputs.set);api.xrDestroyInstance(instance);std::exit(0);
 }
 return 1;
}
extern "C" float kl_view_display_hz(void) { init();const char *v=getenv("KL_DISPLAY_HZ");if(v)frequency=atof(v);return float(frequency); }
extern "C" int kl_view_main(const char *,int) {
 @autoreleasepool {
 init();initPipelines();signal(SIGINT,signal_stop);signal(SIGTERM,signal_stop);
 auto started=std::chrono::steady_clock::now();uint64_t frames=0,pictures=0;bool reported=false;
 fprintf(stderr,"[moltenvr] Open Brush bridge ready; connect MoltenVR and wear Quest. Ctrl+C stops.\n");
 while(!interrupted) { @autoreleasepool {
  XrEventDataBuffer event{XR_TYPE_EVENT_DATA_BUFFER};
  while(api.xrPollEvent(instance,&event)==XR_SUCCESS) {
   if(event.type==XR_TYPE_EVENT_DATA_SESSION_STATE_CHANGED){auto state=((XrEventDataSessionStateChanged*)&event)->state;fprintf(stderr,"[moltenvr] session state %d\n",int(state));if(state==XR_SESSION_STATE_READY){XrSessionBeginInfo bi{XR_TYPE_SESSION_BEGIN_INFO};bi.primaryViewConfigurationType=XR_VIEW_CONFIGURATION_TYPE_PRIMARY_STEREO;xrcheck(api.xrBeginSession(session,&bi),"begin session");running=true;}if(state==XR_SESSION_STATE_STOPPING){api.xrEndSession(session);running=false;interrupted=1;}if(state==XR_SESSION_STATE_EXITING||state==XR_SESSION_STATE_LOSS_PENDING)interrupted=1;}
   if(event.type==XR_TYPE_EVENT_DATA_REFERENCE_SPACE_CHANGE_PENDING) {
    auto *change=(XrEventDataReferenceSpaceChangePending*)&event;
    pendingRecenters.push_back(change->changeTime);
    fprintf(stderr,"[moltenvr] reference-space change pending: type %d, time %lld, valid %d\n",int(change->referenceSpaceType),(long long)change->changeTime,int(change->poseValid));
   }
   event={XR_TYPE_EVENT_DATA_BUFFER};
  }
  if(!running){if(std::chrono::steady_clock::now()-started>std::chrono::seconds(90)){fprintf(stderr,"[moltenvr] headset/session timeout\n");break;}usleep(10000);continue;}
  XrFrameWaitInfo wi{XR_TYPE_FRAME_WAIT_INFO};XrFrameState fs{XR_TYPE_FRAME_STATE};xrcheck(api.xrWaitFrame(session,&wi,&fs),"wait frame");XrFrameBeginInfo bi{XR_TYPE_FRAME_BEGIN_INFO};xrcheck(api.xrBeginFrame(session,&bi),"begin frame");
  XrSpace base=(haveStage&&kl_ovrp_tracking_origin()!=0)?stageSpace:localSpace;
  XrSpaceLocation head{XR_TYPE_SPACE_LOCATION};
  XrViewLocateInfo vl{XR_TYPE_VIEW_LOCATE_INFO};vl.viewConfigurationType=XR_VIEW_CONFIGURATION_TYPE_PRIMARY_STEREO;vl.displayTime=fs.predictedDisplayTime;vl.space=base;XrViewState vs{XR_TYPE_VIEW_STATE};XrView views[2]={{XR_TYPE_VIEW},{XR_TYPE_VIEW}};uint32_t n=0;xrcheck(api.xrLocateViews(session,&vl,&vs,2,&n,views),"views");
  bool tracked=kl_stereo_head(views,n,vs.viewStateFlags,&head.pose);
  if(tracked) {
   auto p=head.pose.position;auto q=head.pose.orientation;kl_ovrp_set_head_pose_time(seconds(fs.predictedDisplayTime));kl_ovrp_set_head_pose(p.x,p.y,p.z,q.x,q.y,q.z,q.w);
   for(int e=0;e<2;e++){auto f=views[e].fov;kl_ovrp_set_eye_frustum(e,-tanf(f.angleLeft),tanf(f.angleRight),tanf(f.angleUp),-tanf(f.angleDown));auto ep=views[e].pose.position;auto delta=rotate(inverse(q),{ep.x-p.x,ep.y-p.y,ep.z-p.z});kl_ovrp_set_eye_offset(e,delta.x,delta.y,delta.z);auto eq=multiply(inverse(q),views[e].pose.orientation);kl_ovrp_set_eye_rotation(e,eq.x,eq.y,eq.z,eq.w);}
  }
  inputs.update(base,fs.predictedDisplayTime);
  // Some native runtimes update LOCAL after a Quest system recenter without
  // issuing ReferenceSpaceChangePending. A rigid transform between reference
  // spaces changes only with their origins, not when the wearer moves.
  if(haveStage&&getenv("KL_MOLTENVR_RECENTER_WATCH")) {
   XrSpaceLocation rel{XR_TYPE_SPACE_LOCATION};
   if(XR_SUCCEEDED(api.xrLocateSpace(localSpace,stageSpace,fs.predictedDisplayTime,&rel))&&
      (rel.locationFlags&XR_SPACE_LOCATION_POSITION_VALID_BIT)&&(rel.locationFlags&XR_SPACE_LOCATION_ORIENTATION_VALID_BIT)) {
    if(haveLocalStage) {
     auto a=previousLocalStage.position,b=rel.pose.position;auto qa=previousLocalStage.orientation,qb=rel.pose.orientation;
     float dx=b.x-a.x,dy=b.y-a.y,dz=b.z-a.z;
     float dot=fabsf(qa.x*qb.x+qa.y*qb.y+qa.z*qb.z+qa.w*qb.w);dot=fminf(1.0f,dot);
     float degrees=2*acosf(dot)*57.2957795f;
     if(dx*dx+dy*dy+dz*dz>.0004f||degrees>1.0f) {
      fprintf(stderr,"[moltenvr] reference origins changed: delta %.3f %.3f %.3f m, %.2f deg\n",dx,dy,dz,degrees);
      deliverRecenter(fs.predictedDisplayTime,"LOCAL/STAGE origin change");
     }
    }
    previousLocalStage=rel.pose;haveLocalStage=true;
   }
  }
  for(auto it=pendingRecenters.begin();it!=pendingRecenters.end();) {
   if(*it<=fs.predictedDisplayTime) {
    // A runtime can report LOCAL and STAGE for the same system recenter.
    if(*it>lastRecenter){deliverRecenter(fs.predictedDisplayTime,"OpenXR event");lastRecenter=*it;}
    it=pendingRecenters.erase(it);
   } else ++it;
  }
  kl_view_pace_publish();
  if(fs.predictedDisplayPeriod>0){frequency=1e9/fs.predictedDisplayPeriod;kl_ovrp_set_display_frequency(frequency);}
  kl_ovrp_proj_layer projections[8]{};kl_ovrp_render_pose record{};
  int projectionCount=kl_ovrp_projection_frame_snapshot(projections,8,&record);
  // OpenXR selects its image through the projection layer. Read that image's
  // completed pose record, not the independently changing last-complete slot.
  // Otherwise the picture can carry one frame's head pose and another frame's
  // viewport/ray mapping, producing motion-dependent swimming.
  int stage=projectionCount>0&&projections[0].slot[0]>=0?projections[0].slot[0]:kl_ovrp_last_complete_stage();
  bool haveRecord=projectionCount>0?record.serial&&record.complete:
      stage>=0&&kl_ovrp_stage_render_pose(stage,&record)&&record.complete;
  // Low-rate timing summary: no image readback or per-frame log traffic.
  if(getenv("KL_MOLTENVR_TIMING")&&haveRecord) {
   static uint64_t previousSerial=0,previousNs=0;static unsigned count=0,fresh=0,repeated=0,skipped=0;
   static double ageSum=0,ageMax=0,gapMax=0;
   struct timespec ts;clock_gettime(CLOCK_MONOTONIC,&ts);uint64_t now=uint64_t(ts.tv_sec)*1000000000ull+ts.tv_nsec;
   double age=record.submit_ns&&now>=record.submit_ns?(now-record.submit_ns)/1e6:0;
   if(record.serial==previousSerial)repeated++;else{fresh++;if(previousSerial&&record.serial>previousSerial+1)skipped+=unsigned(record.serial-previousSerial-1);}
   if(previousNs)gapMax=fmax(gapMax,(now-previousNs)/1e6);
   previousNs=now;previousSerial=record.serial;ageSum+=age;ageMax=fmax(ageMax,age);
   if(++count==120){fprintf(stderr,"[timing] 120 display frames: new=%u repeated=%u skipped=%u pose_age_ms mean=%.2f max=%.2f display_gap_max=%.2f stage=%d serial=%llu\n",fresh,repeated,skipped,ageSum/count,ageMax,gapMax,stage,(unsigned long long)record.serial);count=fresh=repeated=skipped=0;ageSum=ageMax=gapMax=0;}
  }
  int slices[2]={0,0};id<MTLTexture> sources[2]={nil,nil};if(stage>=0)for(int e=0;e<2;e++)sources[e]=(__bridge id<MTLTexture>)kl_glfb_eye_mtl_texture(e,stage,&slices[e]);
  if(projectionCount>0)for(int e=0;e<2;e++)if(projections[0].slot[e]>=0)sources[e]=(__bridge id<MTLTexture>)kl_glfb_eye_mtl_texture(e,projections[0].slot[e],&slices[e]);
  // Exchange eye images and matching crop/FOV metadata, keeping tracking intact.
  if(getenv("KL_MOLTENVR_SWAP_EYES")&&strcmp(getenv("KL_MOLTENVR_SWAP_EYES"),"1")==0) {
   auto texture=sources[0];sources[0]=sources[1];sources[1]=texture;
   int slice=slices[0];slices[0]=slices[1];slices[1]=slice;
   for(int i=0;i<4;i++) {
    auto v=record.viewport[0][i];record.viewport[0][i]=record.viewport[1][i];record.viewport[1][i]=v;
    float t=record.tangents[0][i];record.tangents[0][i]=record.tangents[1][i];record.tangents[1][i]=t;
    if(projectionCount>0){float f=projections[0].tangents[0][i];projections[0].tangents[0][i]=projections[0].tangents[1][i];projections[0].tangents[1][i]=f;}
   }
   static bool said=false;if(!said){said=true;fprintf(stderr,"[moltenvr] eye-image order exchanged (Syberia stereo test)\n");}
  }
  bool image=sources[0]&&sources[1];if(image&&!reported){fprintf(stderr,"[moltenvr] first stereo image: %lux%lu, type %lu, projection layers %d\n",(unsigned long)sources[0].width,(unsigned long)sources[0].height,(unsigned long)sources[0].textureType,projectionCount);reported=true;}
  XrCompositionLayerProjectionView pv[2]={{XR_TYPE_COMPOSITION_LAYER_PROJECTION_VIEW},{XR_TYPE_COMPOSITION_LAYER_PROJECTION_VIEW}};
  XrCompositionLayerQuad quads[32]{}; int quadCount=0;
  std::vector<XrSwapchain> panelReleases;
  bool render=fs.shouldRender&&tracked&&n==2;
  if(render) {
   id<MTLTexture> video=loadingVideo();
   unsigned visualShot=getenv("KL_VISUAL_TURN_PROBE")?kl_visual_probe_shot():0;
   // One bounded compositor capture without injecting controller input.
   // Includes quad/video layers that are absent from raw eye images.
   const char *captureAt=getenv("KL_MOLTENVR_CAPTURE_AT");
   if(captureAt&&frames>=strtoull(captureAt,nullptr,10)&&!lastVisualShot)visualShot=1;
   bool visualCapture=visualShot>lastVisualShot;
   id<MTLBuffer> visualBuffer[2]={nil,nil};NSUInteger visualStride[2]={},visualW[2]={},visualH[2]={};
   id<MTLCommandBuffer> cmd=[queue commandBuffer];uint32_t indices[2]{};
   uint64_t fence=kl_glfb_gpu_fence_value();
   bool compositePanels=getenv("KL_MOLTENVR_COMPOSITE_PANELS")!=nullptr;
   bool loadingIndependent=compositePanels&&kl_loadingvideo_active();
   bool guestReady=!fence||!sharedEvent||sharedEvent.signaledValue>=fence;
   if(fence&&sharedEvent&&!loadingIndependent)[cmd encodeWaitForEvent:sharedEvent value:fence];
   if(loadingIndependent&&!guestReady){static bool said=false;if(!said){said=true;fprintf(stderr,"[moltenvr] loading video runs independently while guest GPU frame is pending\n");}}
   for(int e=0;e<2;e++) {
    XrSwapchainImageAcquireInfo ai{XR_TYPE_SWAPCHAIN_IMAGE_ACQUIRE_INFO};xrcheck(api.xrAcquireSwapchainImage(eyes[e].handle,&ai,&indices[e]),"acquire image");XrSwapchainImageWaitInfo swi{XR_TYPE_SWAPCHAIN_IMAGE_WAIT_INFO};swi.timeout=XR_INFINITE_DURATION;xrcheck(api.xrWaitSwapchainImage(eyes[e].handle,&swi),"wait image");
    id<MTLTexture> dst=(__bridge id<MTLTexture>)eyes[e].images[indices[e]].texture;
    const char *warpMode=getenv("KL_MOLTENVR_LOCAL_ROTATION_WARP");
    bool localWarp=warpMode&&!strcmp(warpMode,"1")&&haveRecord&&!loadingIndependent;
    if(localWarp){static bool said=false;if(!said){said=true;fprintf(stderr,"[moltenvr] local rotation correction enabled; submitted orientation matches corrected pixels\n");}}
    draw(cmd,dst,loadingIndependent?nil:sources[e],e,slices[e],haveRecord?&record:nullptr,nullptr,getenv("KL_MOLTENVR_NATIVE_CONE")?&views[e].fov:nullptr,localWarp?&views[e].pose.orientation:nullptr);
    pv[e].pose=views[e].pose;pv[e].fov=views[e].fov;
    if(image&&haveRecord) {
     XrQuaternionf q{record.qx,record.qy,record.qz,record.qw};XrVector3f p{record.px,record.py,record.pz};
     if(projectionCount>0){auto &l=projections[0];pv[e].fov={-atanf(l.tangents[e][0]),atanf(l.tangents[e][1]),atanf(l.tangents[e][2]),-atanf(l.tangents[e][3])};}
     else pv[e].fov={-atanf(record.tangents[e][0]),atanf(record.tangents[e][1]),atanf(record.tangents[e][2]),-atanf(record.tangents[e][3])};
     auto hp=head.pose.position,ep=views[e].pose.position;auto offset=rotate(q,rotate(inverse(head.pose.orientation),{ep.x-hp.x,ep.y-hp.y,ep.z-hp.z}));pv[e].pose={q,{p.x+offset.x,p.y+offset.y,p.z+offset.z}};
    }
    if(getenv("KL_MOLTENVR_NATIVE_CONE"))pv[e].fov=views[e].fov;
    // The pixels have already been rotated to this orientation. Submitting
    // the old orientation here would ask the runtime to apply it twice.
    if(localWarp)pv[e].pose.orientation=views[e].pose.orientation;
    if(video){drawLoading(cmd,dst,video,views[e]);pv[e].pose=views[e].pose;pv[e].fov=views[e].fov;}
    if(compositePanels&&(!loadingIndependent||guestReady))drawPanels(cmd,dst,e,head.pose,pv[e]);
    if(visualCapture&&(pixelFormat==MTLPixelFormatBGRA8Unorm||pixelFormat==MTLPixelFormatBGRA8Unorm_sRGB||pixelFormat==MTLPixelFormatRGBA8Unorm||pixelFormat==MTLPixelFormatRGBA8Unorm_sRGB)){
     visualW[e]=dst.width;visualH[e]=dst.height;visualStride[e]=(dst.width*4+255)&~NSUInteger(255);
     visualBuffer[e]=[device newBufferWithLength:visualStride[e]*dst.height options:MTLResourceStorageModeShared];
     if(visualBuffer[e]){id<MTLBlitCommandEncoder> blit=[cmd blitCommandEncoder];[blit copyFromTexture:dst sourceSlice:0 sourceLevel:0 sourceOrigin:MTLOriginMake(0,0,0) sourceSize:MTLSizeMake(dst.width,dst.height,1) toBuffer:visualBuffer[e] destinationOffset:0 destinationBytesPerRow:visualStride[e] destinationBytesPerImage:visualStride[e]*dst.height];[blit endEncoding];}
    }
    pv[e].subImage.swapchain=eyes[e].handle;pv[e].subImage.imageRect={{0,0},{int32_t(eyes[e].width),int32_t(eyes[e].height)}};
   }
   // OVRPlugin menus can be entirely separate from the eye images.
   // Copy each submitted panel to a native OpenXR quad, retaining its pose,
   // per-eye crop, alpha and head-locked reference space.
   int overlays=(getenv("KL_MOLTENVR_DISABLE_PANELS")||compositePanels)?0:kl_ovrp_overlay_count();
   for(int i=0;i<overlays&&i<16;i++) {
    kl_ovrp_overlay ov{}; if(!kl_ovrp_overlay_get(i,&ov)||ov.shape!=0||ov.size[0]<=0||ov.size[1]<=0)continue;
    for(int e=0;e<2;e++) {
     if((ov.eye_visibility==1&&e!=0)||(ov.eye_visibility==2&&e!=1))continue;
     int w=0,h=0;
     void *t=ov.tex?kl_vulkan_mtl_for_handle(ov.tex):nullptr;
     if(!t)t=kl_vulkan_layer_mtl_texture(ov.layer_id,ov.stage,e,&w,&h);
     if(!t)t=kl_glfb_layer_mtl_texture(ov.layer_id,ov.stage,&w,&h);
     id<MTLTexture> src=(__bridge id<MTLTexture>)t; if(!src)continue;
     auto &c=panels[i][e];
     auto v=ov.viewport[e]; uint32_t pw=v[2]>0?v[2]:src.width, ph=v[3]>0?v[3]:src.height;
     if(c.handle&&(c.width!=pw||c.height!=ph)){api.xrDestroySwapchain(c.handle);c=Chain{};}
     if(!c.handle) {
      XrSwapchainCreateInfo ci{XR_TYPE_SWAPCHAIN_CREATE_INFO};ci.usageFlags=XR_SWAPCHAIN_USAGE_COLOR_ATTACHMENT_BIT|XR_SWAPCHAIN_USAGE_SAMPLED_BIT;ci.format=pixelFormat;ci.sampleCount=1;ci.width=pw;ci.height=ph;ci.faceCount=1;ci.arraySize=1;ci.mipCount=1;
      xrcheck(api.xrCreateSwapchain(session,&ci,&c.handle),"panel swapchain");c.width=pw;c.height=ph;
      uint32_t count=0;xrcheck(api.xrEnumerateSwapchainImages(c.handle,0,&count,nullptr),"panel images");c.images.resize(count,{XR_TYPE_SWAPCHAIN_IMAGE_METAL_KHR});xrcheck(api.xrEnumerateSwapchainImages(c.handle,count,&count,(XrSwapchainImageBaseHeader*)c.images.data()),"panel textures");
      fprintf(stderr,"[moltenvr] panel %d eye %d: %ux%u\n",ov.layer_id,e,pw,ph);
     }
     uint32_t index=0;XrSwapchainImageAcquireInfo ai{XR_TYPE_SWAPCHAIN_IMAGE_ACQUIRE_INFO};xrcheck(api.xrAcquireSwapchainImage(c.handle,&ai,&index),"panel acquire");XrSwapchainImageWaitInfo wi{XR_TYPE_SWAPCHAIN_IMAGE_WAIT_INFO};wi.timeout=XR_INFINITE_DURATION;xrcheck(api.xrWaitSwapchainImage(c.handle,&wi),"panel wait");
     draw(cmd,(__bridge id<MTLTexture>)c.images[index].texture,src,e,src.textureType==MTLTextureType2DArray?e:0,nullptr,&ov);
     auto &q=quads[quadCount++];q.type=XR_TYPE_COMPOSITION_LAYER_QUAD;q.layerFlags=XR_COMPOSITION_LAYER_BLEND_TEXTURE_SOURCE_ALPHA_BIT;q.space=ov.head_locked?headSpace:base;q.eyeVisibility=e?XR_EYE_VISIBILITY_RIGHT:XR_EYE_VISIBILITY_LEFT;q.pose={{ov.pose[0],ov.pose[1],ov.pose[2],ov.pose[3]},{ov.pose[4],ov.pose[5],ov.pose[6]}};q.size={ov.size[0],ov.size[1]};q.subImage.swapchain=c.handle;q.subImage.imageRect={{0,0},{int32_t(c.width),int32_t(c.height)}};panelReleases.push_back(c.handle);
    }
   }
   [cmd commit];[cmd waitUntilCompleted];if(cmd.status==MTLCommandBufferStatusError){fprintf(stderr,"[moltenvr] GPU: %s\n",cmd.error.localizedDescription.UTF8String);break;}
   if(visualCapture){lastVisualShot=visualShot;const char *dir=getenv("KL_VK_OUT");
    for(int e=0;e<2;e++)if(dir&&visualBuffer[e]){std::vector<uint8_t> rgba(visualW[e]*visualH[e]*4);const uint8_t *src=(const uint8_t*)visualBuffer[e].contents;bool bgra=pixelFormat==MTLPixelFormatBGRA8Unorm||pixelFormat==MTLPixelFormatBGRA8Unorm_sRGB;
     for(NSUInteger y=0;y<visualH[e];y++)for(NSUInteger x=0;x<visualW[e];x++){const uint8_t *v=src+y*visualStride[e]+x*4;uint8_t *d=rgba.data()+(y*visualW[e]+x)*4;d[0]=v[bgra?2:0];d[1]=v[1];d[2]=v[bgra?0:2];d[3]=v[3];}
     char path[1024];snprintf(path,sizeof path,"%s/final_turn_%02u_eye%d.png",dir,visualShot,e);kl_visual_write_png(path,rgba.data(),(int)visualW[e],(int)visualH[e]);
     fprintf(stderr,"[visual] turn checkpoint %u eye%d viewport %d,%d %dx%d of %dx%d tangents %.3f %.3f %.3f %.3f overlays %d\n",visualShot,e,record.viewport[e][0],record.viewport[e][1],record.viewport[e][2],record.viewport[e][3],record.viewport_of[0],record.viewport_of[1],record.tangents[e][0],record.tangents[e][1],record.tangents[e][2],record.tangents[e][3],kl_ovrp_overlay_count());
    }
   }
   for(auto chain:panelReleases){XrSwapchainImageReleaseInfo ri{XR_TYPE_SWAPCHAIN_IMAGE_RELEASE_INFO};xrcheck(api.xrReleaseSwapchainImage(chain,&ri),"panel release");}
   for(auto &chain:eyes){XrSwapchainImageReleaseInfo ri{XR_TYPE_SWAPCHAIN_IMAGE_RELEASE_INFO};xrcheck(api.xrReleaseSwapchainImage(chain.handle,&ri),"release image");}if(image)++pictures;
  }
  XrCompositionLayerProjection layer{XR_TYPE_COMPOSITION_LAYER_PROJECTION};layer.space=base;layer.viewCount=2;layer.views=pv;std::vector<const XrCompositionLayerBaseHeader*> layers{(XrCompositionLayerBaseHeader*)&layer};for(int i=0;i<quadCount;i++)layers.push_back((XrCompositionLayerBaseHeader*)&quads[i]);XrFrameEndInfo ei{XR_TYPE_FRAME_END_INFO};ei.displayTime=fs.predictedDisplayTime;ei.environmentBlendMode=XR_ENVIRONMENT_BLEND_MODE_OPAQUE;ei.layerCount=render?layers.size():0;ei.layers=render?layers.data():nullptr;xrcheck(api.xrEndFrame(session,&ei),"end frame");
  if(++frames%600==0)fprintf(stderr,"[moltenvr] frames %llu, stereo %llu, %.1f Hz, overlays %d\n",(unsigned long long)frames,(unsigned long long)pictures,frequency,kl_ovrp_overlay_count());
 }}
 kl_view_pace_stop();for(auto &pair:panels)for(auto &c:pair)if(c.handle)api.xrDestroySwapchain(c.handle);for(auto &c:eyes)api.xrDestroySwapchain(c.handle);for(auto &s:inputs.spaces)api.xrDestroySpace(s);for(auto &s:inputs.aimSpaces)api.xrDestroySpace(s);api.xrDestroySpace(localSpace);if(haveStage)api.xrDestroySpace(stageSpace);api.xrDestroySpace(headSpace);api.xrDestroySession(session);api.xrDestroyActionSet(inputs.set);api.xrDestroyInstance(instance);
 return 0;
 }
}
