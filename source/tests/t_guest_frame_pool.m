#import <Foundation/Foundation.h>
#include <stdio.h>
#include <stdlib.h>
extern void kl_moltenvr_guest_pool_begin(void),kl_moltenvr_guest_pool_end(void);
extern void *objc_autorelease(void *);
static unsigned gone;
@interface FrameProbe : NSObject @end
@implementation FrameProbe
-(void)dealloc{gone++;}
@end
int main(void){
 setenv("KL_MOLTENVR_GUEST_POOL","1",1);
 for(unsigned frame=0;frame<60;frame++){
  kl_moltenvr_guest_pool_begin();kl_moltenvr_guest_pool_begin();
  for(int i=0;i<2000;i++){void *p=(__bridge_retained void*)[FrameProbe new];objc_autorelease(p);}
  if(gone!=frame*2000)return 2;
  kl_moltenvr_guest_pool_end();kl_moltenvr_guest_pool_end();
  if(gone!=(frame+1)*2000)return 3;
 }
 fprintf(stderr,"PASS: 120000 temporary objects released at frame end, duplicate begin/end safe\n");return 0;
}
