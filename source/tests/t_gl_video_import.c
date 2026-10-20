#include "kl_glfb.h"
#include "kl_avdec.h"
#include "kl_vtdec.h"
#include <unistd.h>
#include <CoreVideo/CoreVideo.h>
#include <stdio.h>
#include <stdlib.h>
#include <dlfcn.h>
#include <string.h>
#define GL(n,ret,args) ret(*n)args=dlsym(lib,"gl"#n);if(!n)return 2
int main(int argc,char **argv){
 setenv("KL_GLFB","1",1);if(!kl_glfb_init())return 2;kl_glfb_make_current();
 char path[4096];snprintf(path,sizeof path,"%s/libGLESv2.dylib",getenv("KL_ANGLE_DIR"));void *lib=dlopen(path,RTLD_NOW|RTLD_LOCAL);if(!lib)return 2;
 GL(GenTextures,void,(int,unsigned*));GL(BindTexture,void,(unsigned,unsigned));GL(GenFramebuffers,void,(int,unsigned*));GL(BindFramebuffer,void,(unsigned,unsigned));GL(FramebufferTexture2D,void,(unsigned,unsigned,unsigned,unsigned,int));GL(CheckFramebufferStatus,unsigned,(unsigned));GL(ReadPixels,void,(int,int,int,int,unsigned,unsigned,void*));GL(GetError,unsigned,(void));
 CFMutableDictionaryRef attrs=CFDictionaryCreateMutable(NULL,0,&kCFTypeDictionaryKeyCallBacks,&kCFTypeDictionaryValueCallBacks);CFDictionaryRef empty=CFDictionaryCreate(NULL,NULL,NULL,0,&kCFTypeDictionaryKeyCallBacks,&kCFTypeDictionaryValueCallBacks);CFDictionarySetValue(attrs,kCVPixelBufferIOSurfacePropertiesKey,empty);CFDictionarySetValue(attrs,kCVPixelBufferMetalCompatibilityKey,kCFBooleanTrue);
 CVPixelBufferRef pb=NULL;int r=CVPixelBufferCreate(NULL,64,32,kCVPixelFormatType_32BGRA,attrs,&pb);CFRelease(attrs);CFRelease(empty);if(r)return 3;
 CVPixelBufferLockBaseAddress(pb,0);for(int y=0;y<32;y++){unsigned char *row=CVPixelBufferGetBaseAddress(pb)+y*CVPixelBufferGetBytesPerRow(pb);for(int x=0;x<64;x++){row[x*4]=37;row[x*4+1]=83;row[x*4+2]=191;row[x*4+3]=255;}}CVPixelBufferUnlockBaseAddress(pb,0);
 kl_vtdec *decoder=NULL;kl_avdemux *demux=NULL;
 if(argc>1){
  setenv("KL_VTDEC_BGRA","1",1);demux=kl_avdemux_open(argv[1],0,0);if(!demux)return 5;const char *mime=NULL;kl_avdemux_info(demux,NULL,NULL,&mime,NULL,NULL);decoder=kl_vtdec_create(mime);kl_vtdec_want_reorder(decoder,1);uint8_t *au=malloc(16u<<20);int found=0;
  for(int i=0;i<250&&!found;i++){
   long n=kl_avdemux_read(demux,au,16u<<20);if(n<=0)break;kl_vtdec_submit(decoder,au,n,kl_avdemux_sample_time_us(demux));kl_avdemux_advance(demux);
   while(kl_vtdec_pending(decoder)>=12){int64_t pts=0;CVPixelBufferRef frame=kl_vtdec_pull(decoder,&pts);if(!frame){usleep(1000);continue;}if(pts>=2000000){CVPixelBufferRelease(pb);pb=frame;found=1;break;}CVPixelBufferRelease(frame);}
  }free(au);if(!found)return 6;
 }
 int width=(int)CVPixelBufferGetWidth(pb),height=(int)CVPixelBufferGetHeight(pb);unsigned char expected[4];CVPixelBufferLockBaseAddress(pb,kCVPixelBufferLock_ReadOnly);unsigned char *center=CVPixelBufferGetBaseAddress(pb)+(height/2)*CVPixelBufferGetBytesPerRow(pb)+(width/2)*4;expected[0]=center[2];expected[1]=center[1];expected[2]=center[0];expected[3]=center[3];CVPixelBufferUnlockBaseAddress(pb,kCVPixelBufferLock_ReadOnly);
 unsigned texture=0,fb=0;GenTextures(1,&texture);BindTexture(0xDE1,texture);void *image=kl_glfb_image_from_pixels(pb,NULL,NULL);if(!image||!kl_glfb_image_bind_texture(image,texture))return 4;
 GenFramebuffers(1,&fb);BindFramebuffer(0x8D40,fb);FramebufferTexture2D(0x8D40,0x8CE0,0xDE1,texture,0);unsigned status=CheckFramebufferStatus(0x8D40);unsigned char pixel[4]={0};ReadPixels(width/2,height/2,1,1,0x1908,0x1401,pixel);unsigned error=GetError();int good=status==0x8CD5&&!error&&!memcmp(pixel,expected,4);
 fprintf(stderr,"CPU expected rgba=%u,%u,%u,%u size=%dx%d\n",expected[0],expected[1],expected[2],expected[3],width,height);
 fprintf(stderr,"%s: BGRA decoded frame -> ANGLE GL texture: rgba=%u,%u,%u,%u status=%#x error=%#x\n",good?"PASS":"FAIL",pixel[0],pixel[1],pixel[2],pixel[3],status,error);
 kl_glfb_image_destroy(image);CVPixelBufferRelease(pb);if(decoder)kl_vtdec_destroy(decoder);if(demux)kl_avdemux_close(demux);return good?0:1;
}
