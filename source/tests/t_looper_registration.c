#include "kl_ndk.h"
#include <pthread.h>
#include <unistd.h>
#include <stdio.h>
#include <time.h>
#include <assert.h>
static void *(*prepare)(int);
static int (*poll_once)(int,int*,int*,void**);
static int (*add_fd)(void*,int,int,int,int(*)(int,int,void*),void*);
static void *looper;
static pthread_mutex_t lock=PTHREAD_MUTEX_INITIALIZER;
static pthread_cond_t ready=PTHREAD_COND_INITIALIZER;
static int calls,first_result,retired;
static int callback(int fd,int events,void *data) {
    (void)events;assert(data==&calls);char c;assert(read(fd,&c,1)==1);calls++;
    return 0; // Android removes a callback that returns zero.
}
static void *waiter(void *unused) {
    (void)unused;
    pthread_mutex_lock(&lock);looper=prepare(0);pthread_cond_signal(&ready);pthread_mutex_unlock(&lock);
    // The caller registers a ready command pipe while this thread waits on
    // the initial, empty descriptor snapshot. A timeout is a real failure.
    first_result=poll_once(2000,0,0,0);
    if(first_result==-1)poll_once(500,0,0,0);
    // Leave another byte unread. A zero-returning callback must be retired,
    // rather than called again just because its descriptor remains readable.
    int result=poll_once(0,0,0,0);
    if(result==-1)result=poll_once(0,0,0,0);
    retired=result==-3;
    return 0;
}
int main(void) {
    prepare=kl_ndk_lookup("ALooper_prepare");poll_once=kl_ndk_lookup("ALooper_pollOnce");add_fd=kl_ndk_lookup("ALooper_addFd");assert(prepare&&poll_once&&add_fd);
    int pipefd[2];assert(pipe(pipefd)==0);assert(write(pipefd[1],"ab",2)==2);
    pthread_t thread;pthread_mutex_lock(&lock);assert(!pthread_create(&thread,0,waiter,0));while(!looper)pthread_cond_wait(&ready,&lock);pthread_mutex_unlock(&lock);
    usleep(100000);
    assert(add_fd(looper,pipefd[0],-1,1,callback,&calls)==1);
    pthread_join(thread,0);close(pipefd[0]);close(pipefd[1]);
    if(first_result!=-1||calls!=1||!retired){fprintf(stderr,"FAIL: wake=%d callbacks=%d retired=%d\n",first_result,calls,retired);return 1;}
    puts("PASS: cross-thread descriptor registration wakes blocked looper; zero-returning callback is removed");return 0;
}
