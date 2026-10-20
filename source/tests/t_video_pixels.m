#import <Metal/Metal.h>
int video_test_pixels(void *p) {
 id<MTLTexture> texture=(__bridge id<MTLTexture>)p;
 if(texture.width!=64||texture.height!=32||texture.pixelFormat!=MTLPixelFormatBGRA8Unorm)return 0;
 unsigned char pixel[4]={0};[texture getBytes:pixel bytesPerRow:4 fromRegion:MTLRegionMake2D(0,0,1,1) mipmapLevel:0];
 return pixel[0]==0x59&&pixel[1]==0x59&&pixel[2]==0x59&&pixel[3]==0x59;
}
