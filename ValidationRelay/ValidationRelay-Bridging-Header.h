//
//  Use this file to import your target's public headers that you would like to expose to Swift.
//

#import "absd.h"
#import <Foundation/Foundation.h>
#import <mach/mach.h>
#import <sys/sysctl.h>

extern kern_return_t bootstrap_look_up(mach_port_t bp, const char *service_name, mach_port_t *sp);

mach_port_t ABSD_PORT = MACH_PORT_NULL;

uint32_t NAC_MAGIC = 0x50936603;

int NACInit(NSData *certificate, uint64_t *out_val_ctx, NSData **out_session_request) {
    if (ABSD_PORT == MACH_PORT_NULL) {
        kern_return_t kret = bootstrap_look_up(bootstrap_port, "com.apple.absd", &ABSD_PORT);
        if (kret != KERN_SUCCESS) {
            NSLog(@"bootstrap_look_up failed");
            return kret;
        }
    }
    
    vm_offset_t session_request = 0;
    mach_msg_type_number_t session_requestCnt = 0;
    uint64_t val_ctx = 0;
    
    int ret = rawNACInit(ABSD_PORT, NAC_MAGIC, (vm_offset_t)[certificate bytes], [certificate length], &val_ctx, &session_request, &session_requestCnt);
    if (ret != 0) {
        NSLog(@"remoteNACInit failed: %d", ret);
        return ret;
    }
    NSLog(@"done");
    *out_val_ctx = val_ctx;
    *out_session_request = [NSData dataWithBytes:(void *)session_request length:session_requestCnt];
    //rawNACInit(
    return 0;
}

int NACKeyEstablishment(uint64_t val_ctx, NSData *session_response) {
    return rawNACKeyEstablishment(ABSD_PORT, NAC_MAGIC, val_ctx, (vm_offset_t)[session_response bytes], [session_response length]);
}

int NACSign(uint64_t val_ctx, NSData *data, NSData **out_signature) {
    vm_offset_t signature = 0;
    mach_msg_type_number_t signatureCnt = 0;
    int ret = rawNACSign(ABSD_PORT, NAC_MAGIC, val_ctx, (vm_offset_t)[data bytes], [data length], &signature, &signatureCnt);
    if (ret != 0) {
        NSLog(@"remoteNACSign failed: %d", ret);
        return ret;
    }
    *out_signature = [NSData dataWithBytes:(void *)signature length:signatureCnt];
    return 0;
}

NSString* buildNumber() {
    size_t malloc_size = 10;
    char *buildNumberBuf = malloc(malloc_size);
    sysctlbyname("kern.osversion\0", (void *)buildNumberBuf, &malloc_size, NULL, 0);

    // we don't need to free `buildNumberBuf` if we pass it into this method
    NSString *buildNumber = [NSString stringWithCString:buildNumberBuf encoding:NSUTF8StringEncoding];
    return buildNumber;
}

extern CFTypeRef MGCopyAnswer(CFStringRef property);
