/* Opt-in UE final-subpass compatibility variants. No shader/state is removed:
 * Vulkan ignores depth/stencil tests when the subpass has no such attachment.
 * Keep the original pipeline for passes that do have depth/stencil. */
typedef struct nd_rp { VkRenderPass rp,alternate; uint32_t depth; struct nd_rp *next; } nd_rp;
typedef struct nd_pipe { VkPipeline pipe,alternate; struct nd_pipe *next; } nd_pipe;
typedef struct nd_cb { VkCommandBuffer cb; VkCommandPool pool; VkRenderPass rp; unsigned sub; struct nd_cb *next; } nd_cb;
static nd_rp *nd_rps; static nd_pipe *nd_pipes; static nd_cb *nd_cbs;
static pthread_mutex_t nd_mu=PTHREAD_MUTEX_INITIALIZER;
static int nd_on(void){static int v=-1;if(v<0)v=kl_env_on("KL_VK_DEPTH_VARIANT",0);return v;}
static void nd_note_rp(VkDevice dev,const VkRenderPassCreateInfo2 *ci,VkRenderPass rp,const VkAllocationCallbacks *a,PFN_vkCreateRenderPass2 real){
 if(!nd_on()||!ci||ci->subpassCount>32)return;
 nd_rp *p=calloc(1,sizeof *p);if(!p)return;p->rp=rp;
 for(unsigned i=0;i<ci->subpassCount;i++)if(ci->pSubpasses[i].pDepthStencilAttachment&&ci->pSubpasses[i].pDepthStencilAttachment->attachment!=VK_ATTACHMENT_UNUSED)p->depth|=1u<<i;
 if(ci->subpassCount==3&&(p->depth&4)){
  VkSubpassDescription2 sub[3];memcpy(sub,ci->pSubpasses,sizeof sub);sub[2].pDepthStencilAttachment=NULL;
  VkRenderPassCreateInfo2 alt=*ci;alt.pSubpasses=sub;
  if(real(dev,&alt,a,&p->alternate)!=VK_SUCCESS)p->alternate=VK_NULL_HANDLE;
 }
 pthread_mutex_lock(&nd_mu);p->next=nd_rps;nd_rps=p;pthread_mutex_unlock(&nd_mu);
}
static VkRenderPass nd_alt_rp(VkRenderPass rp){VkRenderPass alt=VK_NULL_HANDLE;pthread_mutex_lock(&nd_mu);for(nd_rp *p=nd_rps;p;p=p->next)if(p->rp==rp){alt=p->alternate;break;}pthread_mutex_unlock(&nd_mu);return alt;}
static void nd_begin(VkCommandBuffer cb,VkRenderPass rp){if(!nd_on())return;pthread_mutex_lock(&nd_mu);nd_cb *c=nd_cbs;for(;c&&c->cb!=cb;c=c->next){}if(!c){c=calloc(1,sizeof *c);if(c){c->cb=cb;c->next=nd_cbs;nd_cbs=c;}}if(c){c->rp=rp;c->sub=0;}pthread_mutex_unlock(&nd_mu);}
static void nd_next(VkCommandBuffer cb){if(!nd_on())return;pthread_mutex_lock(&nd_mu);for(nd_cb *c=nd_cbs;c;c=c->next)if(c->cb==cb){c->sub++;break;}pthread_mutex_unlock(&nd_mu);}
static void nd_add_pipe(VkPipeline pipe,VkPipeline alt){nd_pipe *p=malloc(sizeof *p);if(!p)return;p->pipe=pipe;p->alternate=alt;pthread_mutex_lock(&nd_mu);p->next=nd_pipes;nd_pipes=p;pthread_mutex_unlock(&nd_mu);}
static VkPipeline nd_bind(VkCommandBuffer cb,VkPipeline pipe){if(!nd_on())return pipe;pthread_mutex_lock(&nd_mu);int missing=0;for(nd_cb *c=nd_cbs;c;c=c->next)if(c->cb==cb){for(nd_rp *p=nd_rps;p;p=p->next)if(p->rp==c->rp){missing=c->sub<32&&!(p->depth&(1u<<c->sub));break;}break;}if(missing)for(nd_pipe *p=nd_pipes;p;p=p->next)if(p->pipe==pipe){pipe=p->alternate;static int said;if(said++<4)fprintf(stderr,"[vk] selected depth-free final-subpass pipeline variant\n");break;}pthread_mutex_unlock(&nd_mu);return pipe;}
static VkPipeline nd_drop_pipe(VkPipeline pipe){VkPipeline alt=VK_NULL_HANDLE;pthread_mutex_lock(&nd_mu);for(nd_pipe **p=&nd_pipes;*p;p=&(*p)->next)if((*p)->pipe==pipe){nd_pipe *old=*p;*p=old->next;alt=old->alternate;free(old);break;}pthread_mutex_unlock(&nd_mu);return alt;}
static VkRenderPass nd_drop_rp(VkRenderPass rp){VkRenderPass alt=VK_NULL_HANDLE;pthread_mutex_lock(&nd_mu);for(nd_rp **p=&nd_rps;*p;p=&(*p)->next)if((*p)->rp==rp){nd_rp *old=*p;*p=old->next;alt=old->alternate;free(old);break;}pthread_mutex_unlock(&nd_mu);return alt;}

static void nd_register_cb(VkCommandBuffer cb,VkCommandPool pool){if(!nd_on())return;nd_begin(cb,VK_NULL_HANDLE);pthread_mutex_lock(&nd_mu);for(nd_cb *c=nd_cbs;c;c=c->next)if(c->cb==cb){c->pool=pool;break;}pthread_mutex_unlock(&nd_mu);}
static void nd_forget_cb(VkCommandBuffer cb,VkCommandPool pool){if(!nd_on())return;pthread_mutex_lock(&nd_mu);for(nd_cb **p=&nd_cbs;*p;){nd_cb *c=*p;if((cb&&c->cb==cb)||(pool&&c->pool==pool)){*p=c->next;free(c);}else p=&c->next;}pthread_mutex_unlock(&nd_mu);}
