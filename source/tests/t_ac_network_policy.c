#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/mman.h>
#include <pthread.h>
#include <libkern/OSCacheControl.h>
#include "kl_guestpatch.h"
typedef struct {unsigned char ident[16];uint16_t type,machine;uint32_t version;uint64_t entry,phoff,shoff;uint32_t flags;uint16_t ehsize,phentsize,phnum,shentsize,shnum,shstrndx;} Ehdr;
typedef struct {uint32_t type,flags;uint64_t offset,vaddr,paddr,filesz,memsz,align;} Phdr;
struct Map {unsigned char *base;size_t size;};
static uint32_t *at(void *v,uint64_t address){struct Map *m=v;return address+4<=m->size?(uint32_t*)(m->base+address):NULL;}
int main(int argc,char **argv) {
 if(argc!=2)return 2;FILE *f=fopen(argv[1],"rb");if(!f)return 2;
 fseek(f,0,SEEK_END);size_t n=ftell(f);rewind(f);unsigned char *file=malloc(n);if(fread(file,1,n,f)!=n)return 2;fclose(f);
 Ehdr *eh=(void*)file;if(memcmp(eh->ident,"\177ELF",4)||eh->machine!=183)return 2;
 Phdr *ph=(void*)(file+eh->phoff);size_t size=0;for(int i=0;i<eh->phnum;i++)if(ph[i].type==1&&ph[i].vaddr+ph[i].memsz>size)size=ph[i].vaddr+ph[i].memsz;
 struct Map m={mmap(NULL,size,PROT_READ|PROT_WRITE|PROT_EXEC,MAP_ANON|MAP_PRIVATE|MAP_JIT,-1,0),size};if(m.base==MAP_FAILED)return 2;
 pthread_jit_write_protect_np(0);
 for(int i=0;i<eh->phnum;i++)if(ph[i].type==1)memcpy(m.base+ph[i].vaddr,file+ph[i].offset,ph[i].filesz);free(file);
 setenv("KL_AC_FAST_NETWORK","1",1);unsigned groups=kl_guest_patch_apply("libubiservices.so",at,&m);if(groups!=1)return 3;
 sys_icache_invalidate(m.base,size);pthread_jit_write_protect_np(1);
 uint64_t retry[4]={0},timeout[2]={0};unsigned char config[56]={0};
 ((void(*)(void*,uint64_t,uint64_t,uint64_t,uint64_t))(m.base+0xc97980))(retry,1000,2000,3000,4000);
 ((void(*)(void*,uint64_t,uint64_t))(m.base+0xc97ea8))(timeout,15000,5000);
 ((void(*)(void*,unsigned,const void*,const void*))(m.base+0xc981f0))(config,9,retry,timeout);
 if(retry[0]||retry[1]||retry[2]||retry[3]||timeout[0]!=5000||timeout[1]||*(uint32_t*)config!=1)return 4;
 ((void(*)(void*,unsigned))(m.base+0xc98484))(config,99);
 ((void(*)(void*,uint64_t))(m.base+0xc97fc0))(timeout,99000);
 ((void(*)(void*,uint64_t))(m.base+0xc97bfc))(retry,88000);
 if(*(uint32_t*)config!=1||timeout[0]!=5000||retry[0])return 5;
 fprintf(stderr,"PASS: real ARM64 SDK constructors and setters: one retry, timeout 5000 ms, no backoff/increment\n");munmap(m.base,size);return 0;
}
