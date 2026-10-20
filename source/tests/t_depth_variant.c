#define VK_NO_PROTOTYPES
#include <vulkan/vulkan.h>
#include <pthread.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <assert.h>
static int kl_env_on(const char *key,int fallback){return 1;}
#include "kl_vk_depth_variant.h"
#define H(t,n) ((t)(uintptr_t)(n))
static VkResult VKAPI_CALL fake_rp(VkDevice d,const VkRenderPassCreateInfo2 *ci,const VkAllocationCallbacks *a,VkRenderPass *out){assert(!ci->pSubpasses[2].pDepthStencilAttachment);*out=H(VkRenderPass,9);return VK_SUCCESS;}
int main(void){
 VkAttachmentReference2 dep={.attachment=0};VkSubpassDescription2 sub[3]={{.pDepthStencilAttachment=&dep},{.pDepthStencilAttachment=&dep},{.pDepthStencilAttachment=&dep}};
 VkRenderPassCreateInfo2 ci={.subpassCount=3,.pSubpasses=sub};VkRenderPass rp=H(VkRenderPass,1), no=H(VkRenderPass,2);VkPipeline pipe=H(VkPipeline,3),alt=H(VkPipeline,4);VkCommandBuffer cb=H(VkCommandBuffer,5);
 nd_note_rp(0,&ci,rp,0,fake_rp);assert(sub[2].pDepthStencilAttachment==&dep);assert(nd_alt_rp(rp)==H(VkRenderPass,9));
 sub[2].pDepthStencilAttachment=NULL;nd_note_rp(0,&ci,no,0,fake_rp);nd_add_pipe(pipe,alt);
 nd_register_cb(cb,H(VkCommandPool,6));nd_begin(cb,no);assert(nd_bind(cb,pipe)==pipe);nd_next(cb);assert(nd_bind(cb,pipe)==pipe);nd_next(cb);assert(nd_bind(cb,pipe)==alt);
 nd_begin(cb,rp);nd_next(cb);nd_next(cb);assert(nd_bind(cb,pipe)==pipe);
 nd_begin(cb,no);assert(nd_bind(cb,pipe)==pipe);nd_forget_cb(0,H(VkCommandPool,6));assert(nd_cbs==NULL);
 assert(nd_drop_pipe(pipe)==alt);assert(nd_drop_pipe(pipe)==0);assert(nd_drop_rp(rp)==H(VkRenderPass,9));nd_drop_rp(no);assert(!nd_rps&&!nd_pipes);puts("PASS: depth variant selection, unchanged guest descriptions, and lifetime cleanup");
}
