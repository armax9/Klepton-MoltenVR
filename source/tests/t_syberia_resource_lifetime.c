#define VK_NO_PROTOTYPES
#include <vulkan/vulkan.h>
#include <stdio.h>
#include <stdlib.h>
#include <dlfcn.h>
#include "kl_vulkan.h"
#define LOAD(n) PFN_vk##n n=(PFN_vk##n)kl_vulkan_sym("vk"#n);if(!n)return 2
#define OK(c) do{VkResult r=(c);if(r){fprintf(stderr,"FAIL %s: %d\n",#c,r);return 3;}}while(0)
extern unsigned long long lifetime_gpu_bytes(void);
int main(void){
 setenv("KL_VK_PARK_INSTANCE","0",1);
 LOAD(GetDeviceQueue);LOAD(CreateCommandPool);LOAD(DestroyCommandPool);LOAD(AllocateCommandBuffers);LOAD(ResetCommandPool);LOAD(BeginCommandBuffer);LOAD(EndCommandBuffer);LOAD(QueueSubmit);LOAD(QueueWaitIdle);LOAD(CreateRenderPass);LOAD(DestroyRenderPass);LOAD(CreateFramebuffer);LOAD(DestroyFramebuffer);LOAD(CreateImageView);LOAD(DestroyImageView);LOAD(CmdBeginRenderPass);LOAD(CmdEndRenderPass);LOAD(CreateInstance);LOAD(EnumeratePhysicalDevices);LOAD(CreateDevice);LOAD(CreateImage);LOAD(GetImageMemoryRequirements);LOAD(AllocateMemory);LOAD(BindImageMemory);LOAD(DestroyImage);LOAD(FreeMemory);LOAD(DestroyDevice);LOAD(DestroyInstance);
 VkApplicationInfo ap={.sType=VK_STRUCTURE_TYPE_APPLICATION_INFO,.apiVersion=VK_API_VERSION_1_1};VkInstanceCreateInfo ic={.sType=VK_STRUCTURE_TYPE_INSTANCE_CREATE_INFO,.pApplicationInfo=&ap};VkInstance inst;OK(CreateInstance(&ic,0,&inst));
 uint32_t n=1;VkPhysicalDevice ph;OK(EnumeratePhysicalDevices(inst,&n,&ph));float pri=1;VkDeviceQueueCreateInfo qc={.sType=VK_STRUCTURE_TYPE_DEVICE_QUEUE_CREATE_INFO,.queueCount=1,.pQueuePriorities=&pri};VkDeviceCreateInfo dc={.sType=VK_STRUCTURE_TYPE_DEVICE_CREATE_INFO,.queueCreateInfoCount=1,.pQueueCreateInfos=&qc};VkDevice dev;OK(CreateDevice(ph,&dc,0,&dev));
 char path[4096];snprintf(path,sizeof path,"%s/libMoltenVK.dylib",getenv("KL_MVK_DIR"));void *lib=dlopen(path,RTLD_NOW|RTLD_LOCAL);void(*mtl)(VkImage,void**)=(void*)dlsym(lib,"vkGetMTLTextureMVK");if(!mtl)return 4;
 VkQueue queue;GetDeviceQueue(dev,0,0,&queue);VkCommandPool pool;VkCommandPoolCreateInfo pc={.sType=VK_STRUCTURE_TYPE_COMMAND_POOL_CREATE_INFO};OK(CreateCommandPool(dev,&pc,0,&pool));
 VkCommandBuffer cb;VkCommandBufferAllocateInfo ca={.sType=VK_STRUCTURE_TYPE_COMMAND_BUFFER_ALLOCATE_INFO,.commandPool=pool,.commandBufferCount=1};OK(AllocateCommandBuffers(dev,&ca,&cb));
 VkAttachmentDescription ad={.format=VK_FORMAT_D32_SFLOAT_S8_UINT,.samples=4,.loadOp=VK_ATTACHMENT_LOAD_OP_CLEAR,.storeOp=VK_ATTACHMENT_STORE_OP_DONT_CARE,.stencilLoadOp=VK_ATTACHMENT_LOAD_OP_CLEAR,.stencilStoreOp=VK_ATTACHMENT_STORE_OP_DONT_CARE,.initialLayout=VK_IMAGE_LAYOUT_UNDEFINED,.finalLayout=VK_IMAGE_LAYOUT_DEPTH_STENCIL_ATTACHMENT_OPTIMAL};VkAttachmentReference ar={0,VK_IMAGE_LAYOUT_DEPTH_STENCIL_ATTACHMENT_OPTIMAL};VkSubpassDescription sub={.pipelineBindPoint=VK_PIPELINE_BIND_POINT_GRAPHICS,.pDepthStencilAttachment=&ar};VkRenderPassCreateInfo rc={.sType=VK_STRUCTURE_TYPE_RENDER_PASS_CREATE_INFO,.attachmentCount=1,.pAttachments=&ad,.subpassCount=1,.pSubpasses=&sub};VkRenderPass rp;OK(CreateRenderPass(dev,&rc,0,&rp));
 unsigned long long start=lifetime_gpu_bytes();
 VkImageView heldViews[60]={0};
 for(int i=0;i<60;i++){
  VkImageCreateInfo ci={.sType=VK_STRUCTURE_TYPE_IMAGE_CREATE_INFO,.imageType=VK_IMAGE_TYPE_2D,.format=VK_FORMAT_D32_SFLOAT_S8_UINT,.extent={2688,2304,1},.mipLevels=1,.arrayLayers=2,.samples=VK_SAMPLE_COUNT_4_BIT,.tiling=VK_IMAGE_TILING_OPTIMAL,.usage=VK_IMAGE_USAGE_DEPTH_STENCIL_ATTACHMENT_BIT|VK_IMAGE_USAGE_INPUT_ATTACHMENT_BIT|VK_IMAGE_USAGE_TRANSIENT_ATTACHMENT_BIT};
  VkImage img;OK(CreateImage(dev,&ci,0,&img));VkMemoryRequirements req;GetImageMemoryRequirements(dev,img,&req);unsigned type=0;while(type<32&&!(req.memoryTypeBits&(1u<<type)))type++;
  VkMemoryAllocateInfo ai={.sType=VK_STRUCTURE_TYPE_MEMORY_ALLOCATE_INFO,.allocationSize=req.size,.memoryTypeIndex=type};VkDeviceMemory mem;OK(AllocateMemory(dev,&ai,0,&mem));OK(BindImageMemory(dev,img,mem,0));void *tex=0;mtl(img,&tex);if(!tex)return 5;
  VkImageViewCreateInfo vc={.sType=VK_STRUCTURE_TYPE_IMAGE_VIEW_CREATE_INFO,.image=img,.viewType=VK_IMAGE_VIEW_TYPE_2D_ARRAY,.format=ci.format,.subresourceRange={VK_IMAGE_ASPECT_DEPTH_BIT|VK_IMAGE_ASPECT_STENCIL_BIT,0,1,0,2}};VkImageView view;OK(CreateImageView(dev,&vc,0,&view));VkFramebufferCreateInfo fc={.sType=VK_STRUCTURE_TYPE_FRAMEBUFFER_CREATE_INFO,.renderPass=rp,.attachmentCount=1,.pAttachments=&view,.width=2688,.height=2304,.layers=2};VkFramebuffer fb;OK(CreateFramebuffer(dev,&fc,0,&fb));VkCommandBufferBeginInfo bc={.sType=VK_STRUCTURE_TYPE_COMMAND_BUFFER_BEGIN_INFO};OK(BeginCommandBuffer(cb,&bc));VkClearValue clear={.depthStencil={1,0}};VkRenderPassBeginInfo rb={.sType=VK_STRUCTURE_TYPE_RENDER_PASS_BEGIN_INFO,.renderPass=rp,.framebuffer=fb,.renderArea={{0,0},{2688,2304}},.clearValueCount=1,.pClearValues=&clear};CmdBeginRenderPass(cb,&rb,VK_SUBPASS_CONTENTS_INLINE);CmdEndRenderPass(cb);OK(EndCommandBuffer(cb));VkSubmitInfo si={.sType=VK_STRUCTURE_TYPE_SUBMIT_INFO,.commandBufferCount=1,.pCommandBuffers=&cb};OK(QueueSubmit(queue,1,&si,0));OK(QueueWaitIdle(queue));OK(ResetCommandPool(dev,pool,0));DestroyFramebuffer(dev,fb,0);if(getenv("LIFETIME_KEEP_VIEWS"))heldViews[i]=view;else DestroyImageView(dev,view,0);
  DestroyImage(dev,img,0);FreeMemory(dev,mem,0);
  unsigned long long now=lifetime_gpu_bytes();if(i%10==9)fprintf(stderr,"lifetime %d: GPU %.1f MiB above baseline\n",i+1,(double)(now-start)/1048576.0);
  if(i==0)start=now;
  if(now>start+512ull*1024*1024){extern void kl_vulkan_memory_report(void);kl_vulkan_memory_report();fprintf(stderr,"FAIL: destroyed resources remain allocated\n");return 6;}
 }
 for(int i=0;i<60;i++)if(heldViews[i])DestroyImageView(dev,heldViews[i],0);
 extern void kl_vulkan_memory_report(void);kl_vulkan_memory_report();
 DestroyRenderPass(dev,rp,0);DestroyCommandPool(dev,pool,0);DestroyDevice(dev,0);DestroyInstance(inst,0);fprintf(stderr,"PASS: 60 large MSAA depth allocations released without growing GPU memory\n");return 0;
}
