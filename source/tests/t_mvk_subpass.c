#include <vulkan/vulkan.h>
#include <stdio.h>
#include <stdint.h>
#define OK(x) do { VkResult r=(x); if(r!=VK_SUCCESS){fprintf(stderr,"FAIL %s: %d\n",#x,r);return 1;} }while(0)
static uint32_t memory_type(VkPhysicalDevice p,uint32_t bits,VkMemoryPropertyFlags flags) {
    VkPhysicalDeviceMemoryProperties m;vkGetPhysicalDeviceMemoryProperties(p,&m);
    for(uint32_t i=0;i<m.memoryTypeCount;i++)if((bits&(1u<<i))&&(m.memoryTypes[i].propertyFlags&flags)==flags)return i;
    return UINT32_MAX;
}
int main(void) {
    VkApplicationInfo app={.sType=VK_STRUCTURE_TYPE_APPLICATION_INFO,.apiVersion=VK_API_VERSION_1_1};
    VkInstanceCreateInfo ic={.sType=VK_STRUCTURE_TYPE_INSTANCE_CREATE_INFO,.pApplicationInfo=&app};VkInstance inst;OK(vkCreateInstance(&ic,0,&inst));
    uint32_t count=1;VkPhysicalDevice ph;OK(vkEnumeratePhysicalDevices(inst,&count,&ph));
    VkPhysicalDeviceMultiviewFeatures mv={.sType=VK_STRUCTURE_TYPE_PHYSICAL_DEVICE_MULTIVIEW_FEATURES,.multiview=VK_TRUE};
    float priority=1;VkDeviceQueueCreateInfo qc={.sType=VK_STRUCTURE_TYPE_DEVICE_QUEUE_CREATE_INFO,.queueCount=1,.pQueuePriorities=&priority};
    VkDeviceCreateInfo dc={.sType=VK_STRUCTURE_TYPE_DEVICE_CREATE_INFO,.pNext=&mv,.queueCreateInfoCount=1,.pQueueCreateInfos=&qc};VkDevice dev;OK(vkCreateDevice(ph,&dc,0,&dev));
    VkImageCreateInfo ci={.sType=VK_STRUCTURE_TYPE_IMAGE_CREATE_INFO,.imageType=VK_IMAGE_TYPE_2D,.format=VK_FORMAT_R8G8B8A8_UNORM,.extent={8,8,1},.mipLevels=1,.arrayLayers=2,.samples=1,.tiling=VK_IMAGE_TILING_OPTIMAL,.usage=VK_IMAGE_USAGE_COLOR_ATTACHMENT_BIT|VK_IMAGE_USAGE_TRANSFER_SRC_BIT|VK_IMAGE_USAGE_INPUT_ATTACHMENT_BIT};
    VkImage img;OK(vkCreateImage(dev,&ci,0,&img));VkMemoryRequirements req;vkGetImageMemoryRequirements(dev,img,&req);
    VkMemoryAllocateInfo ai={.sType=VK_STRUCTURE_TYPE_MEMORY_ALLOCATE_INFO,.allocationSize=req.size,.memoryTypeIndex=memory_type(ph,req.memoryTypeBits,0)};VkDeviceMemory mem;OK(vkAllocateMemory(dev,&ai,0,&mem));OK(vkBindImageMemory(dev,img,mem,0));
    VkImageViewCreateInfo vc={.sType=VK_STRUCTURE_TYPE_IMAGE_VIEW_CREATE_INFO,.image=img,.viewType=VK_IMAGE_VIEW_TYPE_2D_ARRAY,.format=ci.format,.subresourceRange={VK_IMAGE_ASPECT_COLOR_BIT,0,1,0,2}};VkImageView view;OK(vkCreateImageView(dev,&vc,0,&view));
    VkAttachmentDescription attachment={.format=ci.format,.samples=1,.loadOp=VK_ATTACHMENT_LOAD_OP_CLEAR,.storeOp=VK_ATTACHMENT_STORE_OP_STORE,.initialLayout=VK_IMAGE_LAYOUT_UNDEFINED,.finalLayout=VK_IMAGE_LAYOUT_TRANSFER_SRC_OPTIMAL};
    VkAttachmentReference color={0,VK_IMAGE_LAYOUT_COLOR_ATTACHMENT_OPTIMAL},input={0,VK_IMAGE_LAYOUT_SHADER_READ_ONLY_OPTIMAL};
    VkSubpassDescription sub[2]={{.pipelineBindPoint=VK_PIPELINE_BIND_POINT_GRAPHICS,.colorAttachmentCount=1,.pColorAttachments=&color},{.pipelineBindPoint=VK_PIPELINE_BIND_POINT_GRAPHICS,.inputAttachmentCount=1,.pInputAttachments=&input}};
    VkSubpassDependency dep[2]={{.srcSubpass=0,.dstSubpass=1,.srcStageMask=VK_PIPELINE_STAGE_COLOR_ATTACHMENT_OUTPUT_BIT,.dstStageMask=VK_PIPELINE_STAGE_FRAGMENT_SHADER_BIT,.srcAccessMask=VK_ACCESS_COLOR_ATTACHMENT_WRITE_BIT,.dstAccessMask=VK_ACCESS_INPUT_ATTACHMENT_READ_BIT,.dependencyFlags=VK_DEPENDENCY_BY_REGION_BIT},{.srcSubpass=1,.dstSubpass=VK_SUBPASS_EXTERNAL,.srcStageMask=VK_PIPELINE_STAGE_FRAGMENT_SHADER_BIT,.dstStageMask=VK_PIPELINE_STAGE_TRANSFER_BIT,.srcAccessMask=VK_ACCESS_INPUT_ATTACHMENT_READ_BIT,.dstAccessMask=VK_ACCESS_TRANSFER_READ_BIT}};
    uint32_t masks[2]={3,3},correlation=3;VkRenderPassMultiviewCreateInfo multiview={.sType=VK_STRUCTURE_TYPE_RENDER_PASS_MULTIVIEW_CREATE_INFO,.subpassCount=2,.pViewMasks=masks,.correlationMaskCount=1,.pCorrelationMasks=&correlation};
    VkRenderPassCreateInfo rc={.sType=VK_STRUCTURE_TYPE_RENDER_PASS_CREATE_INFO,.pNext=&multiview,.attachmentCount=1,.pAttachments=&attachment,.subpassCount=2,.pSubpasses=sub,.dependencyCount=2,.pDependencies=dep};VkRenderPass pass;OK(vkCreateRenderPass(dev,&rc,0,&pass));
    VkFramebufferCreateInfo fc={.sType=VK_STRUCTURE_TYPE_FRAMEBUFFER_CREATE_INFO,.renderPass=pass,.attachmentCount=1,.pAttachments=&view,.width=8,.height=8,.layers=1};VkFramebuffer fb;OK(vkCreateFramebuffer(dev,&fc,0,&fb));
    VkBufferCreateInfo bc={.sType=VK_STRUCTURE_TYPE_BUFFER_CREATE_INFO,.size=512,.usage=VK_BUFFER_USAGE_TRANSFER_DST_BIT};VkBuffer buffer;OK(vkCreateBuffer(dev,&bc,0,&buffer));vkGetBufferMemoryRequirements(dev,buffer,&req);ai.allocationSize=req.size;ai.memoryTypeIndex=memory_type(ph,req.memoryTypeBits,VK_MEMORY_PROPERTY_HOST_VISIBLE_BIT|VK_MEMORY_PROPERTY_HOST_COHERENT_BIT);VkDeviceMemory bm;OK(vkAllocateMemory(dev,&ai,0,&bm));OK(vkBindBufferMemory(dev,buffer,bm,0));
    VkCommandPoolCreateInfo pc={.sType=VK_STRUCTURE_TYPE_COMMAND_POOL_CREATE_INFO};VkCommandPool pool;OK(vkCreateCommandPool(dev,&pc,0,&pool));VkCommandBufferAllocateInfo ca={.sType=VK_STRUCTURE_TYPE_COMMAND_BUFFER_ALLOCATE_INFO,.commandPool=pool,.commandBufferCount=1};VkCommandBuffer cb;OK(vkAllocateCommandBuffers(dev,&ca,&cb));VkCommandBufferBeginInfo begin={.sType=VK_STRUCTURE_TYPE_COMMAND_BUFFER_BEGIN_INFO};OK(vkBeginCommandBuffer(cb,&begin));
    VkClearValue clear={.color={{0,1,0,1}}};VkRenderPassBeginInfo rb={.sType=VK_STRUCTURE_TYPE_RENDER_PASS_BEGIN_INFO,.renderPass=pass,.framebuffer=fb,.renderArea={{0,0},{8,8}},.clearValueCount=1,.pClearValues=&clear};vkCmdBeginRenderPass(cb,&rb,VK_SUBPASS_CONTENTS_INLINE);vkCmdNextSubpass(cb,VK_SUBPASS_CONTENTS_INLINE);vkCmdEndRenderPass(cb);
    VkBufferImageCopy copy={.imageSubresource={VK_IMAGE_ASPECT_COLOR_BIT,0,0,2},.imageExtent={8,8,1}};vkCmdCopyImageToBuffer(cb,img,VK_IMAGE_LAYOUT_TRANSFER_SRC_OPTIMAL,buffer,1,&copy);
    VkMemoryBarrier host={.sType=VK_STRUCTURE_TYPE_MEMORY_BARRIER,.srcAccessMask=VK_ACCESS_TRANSFER_WRITE_BIT,.dstAccessMask=VK_ACCESS_HOST_READ_BIT};vkCmdPipelineBarrier(cb,VK_PIPELINE_STAGE_TRANSFER_BIT,VK_PIPELINE_STAGE_HOST_BIT,0,1,&host,0,0,0,0);OK(vkEndCommandBuffer(cb));
    VkQueue queue;vkGetDeviceQueue(dev,0,0,&queue);VkSubmitInfo si={.sType=VK_STRUCTURE_TYPE_SUBMIT_INFO,.commandBufferCount=1,.pCommandBuffers=&cb};OK(vkQueueSubmit(queue,1,&si,0));OK(vkQueueWaitIdle(queue));
    uint8_t *bytes;OK(vkMapMemory(dev,bm,0,512,0,(void**)&bytes));int valid=1;for(int i=0;i<128;i++)if(bytes[i*4]!=0||bytes[i*4+1]!=255||bytes[i*4+2]!=0||bytes[i*4+3]!=255){valid=0;fprintf(stderr,"FAIL: layer %d pixel %d = %u %u %u %u\n",i/64,i%64,bytes[i*4],bytes[i*4+1],bytes[i*4+2],bytes[i*4+3]);break;}vkUnmapMemory(dev,bm);
    vkDestroyCommandPool(dev,pool,0);vkDestroyFramebuffer(dev,fb,0);vkDestroyRenderPass(dev,pass,0);vkDestroyImageView(dev,view,0);vkDestroyImage(dev,img,0);vkFreeMemory(dev,mem,0);vkDestroyBuffer(dev,buffer,0);vkFreeMemory(dev,bm,0);vkDestroyDevice(dev,0);vkDestroyInstance(inst,0);
    if(valid)puts("PASS: two-view two-subpass attachment transition and exact pixels in both layers (no fragment shader sampling tested)");return valid?0:1;
}
