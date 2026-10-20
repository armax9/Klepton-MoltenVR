/* Opt-in diagnostic: make directly stored fragment color outputs magenta.
 * Preserves vertex shaders and all non-color outputs. Never enabled in profiles. */
#include <stdint.h>
#include <stdlib.h>
#include <string.h>
static uint32_t *kl_spirv_solid_fragment(const uint32_t *c,size_t nw,size_t *outw){
 if(!c||nw<5||c[0]!=0x07230203||!c[3]||c[3]>(1u<<20))return NULL;
 typedef struct{uint32_t ptr;unsigned char f32,v4,location,builtin,output;} Id;
 Id *ids=calloc(c[3],sizeof(Id));if(!ids)return NULL;
 uint32_t ft=0,vt=0;int fragment=0,stores=0;size_t firstfunc=0;
 for(size_t i=5;i<nw;){unsigned n=c[i]>>16,op=c[i]&65535;if(!n||i+n>nw){free(ids);return NULL;}
  if(op==15&&n>=3&&c[i+1]==4)fragment=1;
  if(op==71&&n>=3&&c[i+1]<c[3]){if(c[i+2]==30)ids[c[i+1]].location=1;if(c[i+2]==11)ids[c[i+1]].builtin=1;}
  if(op==22&&n==3&&c[i+1]<c[3]&&c[i+2]==32){ft=c[i+1];ids[ft].f32=1;}
  if(op==23&&n==4&&c[i+1]<c[3]&&c[i+2]<c[3]&&ids[c[i+2]].f32&&c[i+3]==4){vt=c[i+1];ids[vt].v4=1;}
  if(op==32&&n==4&&c[i+1]<c[3]&&c[i+2]==3)ids[c[i+1]].ptr=c[i+3];
  if(op==59&&n>=4&&c[i+1]<c[3]&&c[i+2]<c[3]&&c[i+3]==3)ids[c[i+2]].output=ids[c[i+1]].ptr==vt;
  if(op==54&&!firstfunc)firstfunc=i;
  if(op==62&&n>=3&&c[i+1]<c[3]&&ids[c[i+1]].output&&ids[c[i+1]].location&&!ids[c[i+1]].builtin)stores++;
  i+=n;
 }
 if(!fragment||!ft||!vt||!firstfunc||!stores){free(ids);return NULL;}
 uint32_t *r=malloc((nw+15)*4);if(!r){free(ids);return NULL;}memcpy(r,c,20);r[3]=c[3]+3;size_t j=5;
 for(size_t i=5;i<nw;){unsigned n=c[i]>>16,op=c[i]&65535;
  if(i==firstfunc){uint32_t decl[]={4u<<16|43,ft,c[3],0x3f800000,4u<<16|43,ft,c[3]+1,0,7u<<16|44,vt,c[3]+2,c[3],c[3]+1,c[3],c[3]};memcpy(r+j,decl,sizeof decl);j+=15;}
  memcpy(r+j,c+i,n*4);
  if(op==62&&n>=3&&c[i+1]<c[3]&&ids[c[i+1]].output&&ids[c[i+1]].location&&!ids[c[i+1]].builtin)r[j+2]=c[3]+2;
  j+=n;i+=n;
 }
 free(ids);*outw=j;return r;
}
