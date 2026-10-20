#define VK_NO_PROTOTYPES
#define VK_USE_PLATFORM_ANDROID_KHR 1
#include <vulkan/vulkan.h>
#include <CoreVideo/CoreVideo.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <dlfcn.h>
#include "kl_vulkan.h"
#include "kl_mediandk.h"
#define LOAD(n) PFN_vk##n n=(PFN_vk##n)kl_vulkan_sym("vk"#n);if(!n)return 2
#define OK(call) do{VkResult r=(call);if(r!=VK_SUCCESS){fprintf(stderr,"FAIL %s: %d\n",#call,r);return 3;}}while(0)
int main(void) {
 setenv("KL_VK_VIDEO_IMPORT","1",1);setenv("KL_VK_PARK_INSTANCE","0",1);
 LOAD(CreateInstance);LOAD(EnumeratePhysicalDevices);LOAD(CreateDevice);LOAD(GetAndroidHardwareBufferPropertiesANDROID);LOAD(CreateImage);LOAD(AllocateMemory);LOAD(BindImageMemory2);LOAD(DestroyImage);LOAD(FreeMemory);LOAD(DestroyDevice);LOAD(DestroyInstance);
 VkApplicationInfo app={.sType=VK_STRUCTURE_TYPE_APPLICATION_INFO,.apiVersion=VK_API_VERSION_1_1};
 VkInstanceCreateInfo ic={.sType=VK_STRUCTURE_TYPE_INSTANCE_CREATE_INFO,.pApplicationInfo=&app};VkInstance inst;OK(CreateInstance(&ic,NULL,&inst));
 uint32_t count=1;VkPhysicalDevice phys;OK(EnumeratePhysicalDevices(inst,&count,&phys));float priority=1;
 VkDeviceQueueCreateInfo qc={.sType=VK_STRUCTURE_TYPE_DEVICE_QUEUE_CREATE_INFO,.queueFamilyIndex=0,.queueCount=1,.pQueuePriorities=&priority};
 VkDeviceCreateInfo dc={.sType=VK_STRUCTURE_TYPE_DEVICE_CREATE_INFO,.queueCreateInfoCount=1,.pQueueCreateInfos=&qc};VkDevice dev;OK(CreateDevice(phys,&dc,NULL,&dev));
 CFMutableDictionaryRef attrs=CFDictionaryCreateMutable(NULL,0,&kCFTypeDictionaryKeyCallBacks,&kCFTypeDictionaryValueCallBacks);CFDictionaryRef empty=CFDictionaryCreate(NULL,NULL,NULL,0,&kCFTypeDictionaryKeyCallBacks,&kCFTypeDictionaryValueCallBacks);CFDictionarySetValue(attrs,kCVPixelBufferIOSurfacePropertiesKey,empty);CFDictionarySetValue(attrs,kCVPixelBufferMetalCompatibilityKey,kCFBooleanTrue);
 CVPixelBufferRef pb=NULL;if(CVPixelBufferCreate(NULL,64,32,kCVPixelFormatType_32BGRA,attrs,&pb)!=kCVReturnSuccess)return 4;CFRelease(attrs);CFRelease(empty);
 CVPixelBufferLockBaseAddress(pb,0);memset(CVPixelBufferGetBaseAddress(pb),0x59,CVPixelBufferGetBytesPerRow(pb)*32);CVPixelBufferUnlockBaseAddress(pb,0);
 void *handle=kl_mediandk_buffer_from_pixels(pb);
 VkAndroidHardwareBufferFormatPropertiesANDROID fmt={.sType=VK_STRUCTURE_TYPE_ANDROID_HARDWARE_BUFFER_FORMAT_PROPERTIES_ANDROID};VkAndroidHardwareBufferPropertiesANDROID prop={.sType=VK_STRUCTURE_TYPE_ANDROID_HARDWARE_BUFFER_PROPERTIES_ANDROID,.pNext=&fmt};OK(GetAndroidHardwareBufferPropertiesANDROID(dev,handle,&prop));if(fmt.format!=VK_FORMAT_B8G8R8A8_UNORM||fmt.externalFormat||!prop.memoryTypeBits)return 5;
 VkExternalMemoryImageCreateInfo ext={.sType=VK_STRUCTURE_TYPE_EXTERNAL_MEMORY_IMAGE_CREATE_INFO,.handleTypes=VK_EXTERNAL_MEMORY_HANDLE_TYPE_ANDROID_HARDWARE_BUFFER_BIT_ANDROID};
 VkImageCreateInfo ci={.sType=VK_STRUCTURE_TYPE_IMAGE_CREATE_INFO,.pNext=&ext,.imageType=VK_IMAGE_TYPE_2D,.format=fmt.format,.extent={64,32,1},.mipLevels=1,.arrayLayers=1,.samples=1,.tiling=VK_IMAGE_TILING_OPTIMAL,.usage=VK_IMAGE_USAGE_SAMPLED_BIT};VkImage image;OK(CreateImage(dev,&ci,NULL,&image));
 uint32_t type=0;while(!((prop.memoryTypeBits>>type)&1))type++;
 VkMemoryDedicatedAllocateInfo dedicated={.sType=VK_STRUCTURE_TYPE_MEMORY_DEDICATED_ALLOCATE_INFO,.image=image};VkImportAndroidHardwareBufferInfoANDROID import={.sType=VK_STRUCTURE_TYPE_IMPORT_ANDROID_HARDWARE_BUFFER_INFO_ANDROID,.buffer=handle};VkMemoryAllocateInfo ai={.sType=VK_STRUCTURE_TYPE_MEMORY_ALLOCATE_INFO,.pNext=&dedicated,.allocationSize=0,.memoryTypeIndex=type};VkDeviceMemory mem;dedicated.pNext=&import;OK(AllocateMemory(dev,&ai,NULL,&mem));
 // The imported memory must keep the decoded frame alive after AImage release.
 kl_mediandk_buffer_release(handle);CVPixelBufferRelease(pb);
 VkBindImageMemoryInfo bind={.sType=VK_STRUCTURE_TYPE_BIND_IMAGE_MEMORY_INFO,.image=image,.memory=mem};OK(BindImageMemory2(dev,1,&bind));
 char dylib[4096];snprintf(dylib,sizeof(dylib),"%s/libMoltenVK.dylib",getenv("KL_MVK_DIR"));void *lib=dlopen(dylib,RTLD_NOW|RTLD_LOCAL);
 void (*get_texture)(VkImage,void**)=(void*)dlsym(lib,"vkGetMTLTextureMVK");void *texture=NULL;if(get_texture)get_texture(image,&texture);if(!texture)return 6;
 extern int video_test_pixels(void *);if(!video_test_pixels(texture))return 7;
 DestroyImage(dev,image,NULL);FreeMemory(dev,mem,NULL);DestroyDevice(dev,NULL);DestroyInstance(inst,NULL);
 fprintf(stderr,"PASS: decoded buffer properties, Vulkan import, lifetime, Metal texture and exact pixel contents\n");return 0;
}
