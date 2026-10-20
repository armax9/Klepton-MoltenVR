#import <Metal/Metal.h>
#include <mach/mach.h>
#include <stdlib.h>
unsigned long long lifetime_gpu_bytes(void){
 if(getenv("LIFETIME_FOOTPRINT")){task_vm_info_data_t t={0};mach_msg_type_number_t n=TASK_VM_INFO_COUNT;task_info(mach_task_self(),TASK_VM_INFO,(task_info_t)&t,&n);return t.phys_footprint;}
 return MTLCreateSystemDefaultDevice().currentAllocatedSize;
}
