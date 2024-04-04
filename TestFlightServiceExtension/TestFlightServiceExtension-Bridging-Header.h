//
//  Use this file to import your target's public headers that you would like to expose to Swift.
//

// From AppStoreDaemon.tbd
@interface ASDTestFlightServiceExtension
- (void) init;
//- (void)beginRequestWithExtensionContext:(NSExtensionContext *)context;
@end

// From FrontBoardServices.tbd
#import <objc/NSObject.h>

@class BSServiceConnection;
@protocol OS_dispatch_queue;

typedef void (^CDUnknownBlockType)(void);

@interface FBSOpenApplicationService : NSObject
{
    NSObject<OS_dispatch_queue> *_callbackQueue;
    BSServiceConnection *_connection;
}

+ (_Bool)currentProcessServicesDefaultShellEndpoint;
+ (id)serviceWithDefaultShellEndpoint;
+ (id)serviceWithEndpoint:(id)arg1;
+ (id)serviceName;
+ (id)new;
//- (void).cxx_destruct;
- (void)_openApplication:(id)arg1 withOptions:(id)arg2 clientHandle:(id)arg3 completion:(CDUnknownBlockType)arg4;
- (id)_remoteTarget;
- (void)openApplication:(id)arg1 withOptions:(id)arg2 completion:(CDUnknownBlockType)arg3;
- (_Bool)canOpenApplication:(id)arg1 reason:(long long *)arg2;
- (void)openApplication:(id)arg1 withOptions:(id)arg2 clientHandle:(id)arg3 completion:(CDUnknownBlockType)arg4;
- (void)dealloc;
- (id)_initWithEndpoint:(id)arg1;
- (id)init;

@end

#import <Foundation/Foundation.h>

// From FrontBoardServices.tbd
@interface FBSOpenApplicationOptions : NSObject <NSCopying>
{
    NSMutableDictionary *_payload;
}

+ (_Bool)supportsBSXPCSecureCoding;
+ (id)optionsWithDictionary:(id)arg1;
@property(copy, nonatomic) NSDictionary *dictionary; // @synthesize dictionary=_payload;
- (void)_updateOption:(id)arg1 forKey:(id)arg2;
- (void)_sanitizeAndValidatePayload;
- (id)descriptionBuilderWithMultilinePrefix:(id)arg1;
- (id)descriptionWithMultilinePrefix:(id)arg1;
- (id)succinctDescriptionBuilder;
- (id)succinctDescription;
@property(readonly, copy) NSString *description;
- (void)encodeWithBSXPCCoder:(id)arg1;
- (id)initWithBSXPCCoder:(id)arg1;
- (void)encodeWithXPCDictionary:(id)arg1;
- (id)initWithXPCDictionary:(id)arg1;
- (id)copyWithZone:(struct _NSZone *)arg1;
@property(readonly, nonatomic) NSURL *url;

// Remaining properties
@property(readonly, copy) NSString *debugDescription;
@property(readonly) unsigned long long hash;
@property(readonly) Class superclass;

@end

/*
_FBSOpenApplicationOptionClickAttribution,
_FBSOpenApplicationOptionKeyActions,
_FBSOpenApplicationOptionKeyActivateAsClassic,
_FBSOpenApplicationOptionKeyActivateForEvent,
_FBSOpenApplicationOptionKeyActivateSuspended,
_FBSOpenApplicationOptionKeyAppLink,
_FBSOpenApplicationOptionKeyAppLink4LS,
_FBSOpenApplicationOptionKeyBrowserAppLinkState,
_FBSOpenApplicationOptionKeyBrowserAppLinkState4LS,
_FBSOpenApplicationOptionKeyDebuggingOptions,
_FBSOpenApplicationOptionKeyDocumentOpen4LS,
_FBSOpenApplicationOptionKeyIsSensitiveURL,
_FBSOpenApplicationOptionKeyLSCacheGUID,
_FBSOpenApplicationOptionKeyLSSequenceNumber,
_FBSOpenApplicationOptionKeyLaunchImageName,
_FBSOpenApplicationOptionKeyLaunchIntent,
_FBSOpenApplicationOptionKeyLaunchOrigin,
_FBSOpenApplicationOptionKeyPayloadAnnotation,
_FBSOpenApplicationOptionKeyPayloadIsValid,
_FBSOpenApplicationOptionKeyPayloadIsValid4LS,
_FBSOpenApplicationOptionKeyPayloadOptions,
_FBSOpenApplicationOptionKeyPayloadURL,
_FBSOpenApplicationOptionKeyPromptUnlockDevice,
_FBSOpenApplicationOptionKeyServiceAvailabilityTimeout,
_FBSOpenApplicationOptionKeyUnlockDevice,
_FBSOpenApplicationOptionKeyUserActivity4LS,
*/

// define extenal symbols for keys
extern NSString *const FBSOpenApplicationOptionKeyUnlockDevice;
