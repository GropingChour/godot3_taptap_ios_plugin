/*************************************************************************/
/*  godot3_taptap.mm - 简洁版本                                         */
/*************************************************************************/
/* 参考 Android 版本实现和官方 iOS 插件模式                              */
/*************************************************************************/

#include "godot3_taptap.h"

#if VERSION_MAJOR == 4
#include "core/io/json.h"
#import "platform/ios/app_delegate.h"

#else
#include "core/io/json.h"
#import "platform/iphone/app_delegate.h"

#endif

#import <TapTapComplianceSDK/TapTapCompliance.h>
#import <TapTapComplianceSDK/TapTapComplianceOptions.h>
#import <TapTapCoreSDK/TapTapSDK.h>
#import <TapTapLoginSDK/TapTapLoginSDK-Swift.h>
#import <TapTapCloudSaveSDK/TapTapCloudSaveSDK-Swift.h>
#import <objc/message.h>
#import <objc/runtime.h>
#include <zlib.h>
#include <dirent.h>
#include <sys/stat.h>

#if VERSION_MAJOR == 4
typedef PackedStringArray GodotStringArray;
#else
typedef PoolStringArray GodotStringArray;
#endif

// MARK: - Objective-C Delegate

@interface GodotTapTapDelegate : NSObject <TapTapComplianceDelegate, TapTapCloudSaveCallback>

@property(nonatomic, strong) NSString *clientId;
@property(nonatomic, strong) NSString *clientToken;
@property(nonatomic, assign) BOOL sdkInitialized;

- (NSString *)getDecryptKey;
- (NSString *)decryptToken:(NSString *)encryptedToken;
- (void)initSDKWithClientId:(NSString *)clientId clientToken:(NSString *)clientToken enableLog:(BOOL)enableLog;
- (void)loginWithProfile:(BOOL)useProfile friends:(BOOL)useFriends;
- (BOOL)isLoggedIn;
- (NSDictionary *)getUserProfile;
- (void)logout;
- (void)startComplianceWithUserId:(NSString *)userId;
- (void)exitCompliance;

// Cloud Save
- (void)onResult:(NSInteger)resultCode;
- (void)createArchiveWithMetadata:(NSDictionary *)metadata filePath:(NSString *)filePath coverPath:(NSString *)coverPath;
- (void)getArchiveList;
- (void)downloadArchiveTo:(NSString *)localPath archiveUUID:(NSString *)archiveUUID fileID:(NSString *)fileID;
- (void)updateArchiveUUID:(NSString *)archiveUUID metadata:(NSDictionary *)metadata filePath:(NSString *)filePath coverPath:(NSString *)coverPath;
- (void)deleteArchiveUUID:(NSString *)archiveUUID;
- (void)getArchiveCoverUUID:(NSString *)archiveUUID fileID:(NSString *)fileID;

@end

@implementation GodotTapTapDelegate

- (instancetype)init {
	self = [super init];
	if (self) {
		_sdkInitialized = NO;
		[TapTapCompliance registerComplianceDelegate:self];
		[TapTapCloudSave ensureInitialization];
		[TapTapCloudSave registerCloudSaveCallback:self];
	}
	return self;
}

- (NSString *)getDecryptKey {
	NSDictionary *infoPlist = [[NSBundle mainBundle] infoDictionary];
	NSString *key = [infoPlist objectForKey:@"TapTapDecryptKey"];
	return key ?: @"TapTapz9mdoNZSItSxJOvG";
}

- (NSString *)decryptToken:(NSString *)encryptedToken {
	if (!encryptedToken || encryptedToken.length == 0) return @"";

	NSString *decryptKey = [self getDecryptKey];
	// NSLog(@"[TapTap] Decrypting token with key: %@", decryptKey);
	NSData *encryptedData = [[NSData alloc] initWithBase64EncodedString:encryptedToken options:0];
	if (!encryptedData) return @"";

	NSData *keyData = [decryptKey dataUsingEncoding:NSUTF8StringEncoding];
	NSMutableData *decryptedData = [NSMutableData dataWithLength:encryptedData.length];

	const uint8_t *encBytes = (const uint8_t *)[encryptedData bytes];
	const uint8_t *keyBytes = (const uint8_t *)[keyData bytes];
	uint8_t *decBytes = (uint8_t *)[decryptedData mutableBytes];

	for (NSUInteger i = 0; i < encryptedData.length; i++) {
		decBytes[i] = encBytes[i] ^ keyBytes[i % keyData.length];
	}

	return [[NSString alloc] initWithData:decryptedData encoding:NSUTF8StringEncoding] ?: @"";
}

- (void)initSDKWithClientId:(NSString *)clientId clientToken:(NSString *)clientToken enableLog:(BOOL)enableLog {
	// dispatch_async(dispatch_get_main_queue(), ^{

	// NSLog(@"[TapTap] SDK init with clientId: %@, clientToken: %@", clientId, clientToken);
	self.clientId = clientId;
	self.clientToken = clientToken;

	TapTapSdkOptions *options = [[TapTapSdkOptions alloc] init];
	options.clientId = clientId;
	options.clientToken = clientToken;
	options.region = TapTapRegionTypeCN;
	options.enableLog = enableLog;

	// Method 2: TapTapEventOptions configuration
	Class eventOptionsClass = NSClassFromString(@"TapTapEventOptions");
	if (eventOptionsClass && [options respondsToSelector:@selector(setEventOptions:)]) {
		id eventOptions = [[eventOptionsClass alloc] init];
		if (eventOptions && [eventOptions respondsToSelector:@selector(setEnable:)]) {
			[eventOptions setValue:@NO forKey:@"enable"];
			[options setValue:eventOptions forKey:@"eventOptions"];
			NSLog(@"[TapTap ObjC]   ✓ Disabled via TapTapEventOptions");
		}
	} else {
		NSLog(@"[TapTap ObjC]   ✗ TapTapEventOptions not available");
	}

	/// 合规认证配置
	TapTapComplianceOptions *complianceOptions = [[TapTapComplianceOptions alloc] init];

	complianceOptions.showSwitchAccount = YES; // 是否显示切换账号按钮
	complianceOptions.useAgeRange = NO; // 游戏是否需要获取真实年龄段信息

	// 其他模块配置项
	NSArray *otherOptions = @[ complianceOptions ];

	// TapSDK 初始化
	[TapTapSDK initWithOptions:options otherOptions:otherOptions];
	self.sdkInitialized = YES;

	NSLog(@"[TapTap] SDK initialized");

	// });
}

- (void)loginWithProfile:(BOOL)useProfile friends:(BOOL)useFriends {
	// dispatch_async(dispatch_get_main_queue(), ^{
	NSMutableArray *scopes = [NSMutableArray array];
	if (useProfile) {
		[scopes addObject:@"public_profile"];
	} else {
		[scopes addObject:@"basic_info"];
	}
	if (useFriends) {
		[scopes addObject:@"user_friends"];
	}

	// 发起 Tap 登录
	[TapTapLogin LoginWithScopes:scopes
						 handler:^(BOOL isCancel, NSError *_Nullable error, TapTapAccount *_Nullable account) {
							 NSLog(@"[TapTap] Login callback, isCancel: %d, error: %@, account: %@", isCancel, error, account);
							 if (isCancel) {
								 Godot3TapTap::get_singleton()->emit_signal("onLoginCancel");
							 } else if (error != nil) {
								 String message = String::utf8([[error localizedDescription] UTF8String]);
								 Godot3TapTap::get_singleton()->emit_signal("onLoginFail", message);
							 } else {
								 Godot3TapTap::get_singleton()->emit_signal("onLoginSuccess");
							 }
						 }];
	// });
}

- (BOOL)isLoggedIn {
	TapTapAccount *account = [TapTapLogin getCurrentTapAccount];
	if (account != nil) {
		AccessToken *token = account.accessToken;
		UserInfo *userInfo = account.userInfo;
		if (token != nil && userInfo != nil) {
			// 用户已登录
			return YES;
		} else {
			// 用户未登录
			return NO;
		}
	} else {
		// 用户未登录
		return NO;
	}
}

- (NSDictionary *)getUserProfile {
	TapTapAccount *account = [TapTapLogin getCurrentTapAccount];

	if (account && account.userInfo) {
		return @{
			@"openId" : account.userInfo.openId ?: @"",
			@"unionId" : account.userInfo.unionId ?: @"",
			@"name" : account.userInfo.name ?: @"",
			@"avatar" : account.userInfo.avatar ?: @""
		};
	}

	return @{ @"error" : @"User not logged in" };
}

- (void)logout {
	[TapTapLogin logout];
}

- (void)startComplianceWithUserId:(NSString *)userId {
	dispatch_async(dispatch_get_main_queue(), ^{
		if (!userId || userId.length == 0) {
			Godot3TapTap::get_singleton()->emit_signal("onComplianceResult", -1, "Invalid user ID");
			return;
		}

		[TapTapCompliance startup:userId];
	});
}

- (void)exitCompliance {
	[TapTapCompliance exit];
}

- (void)complianceCallbackWithCode:(TapComplianceResultHandlerCode)code extra:(NSString *_Nullable)extra {
	String info = String::utf8([extra UTF8String] ?: "");
	Godot3TapTap::get_singleton()->emit_signal("onComplianceResult", (int)code, info);
}

// MARK: - Cloud Save delegate methods

- (void)onResult:(NSInteger)resultCode {
	NSLog(@"[TapTap CloudSave] onResult: resultCode=%ld", (long)resultCode);
	Godot3TapTap::get_singleton()->emit_signal("onCloudSaveCallback", (int)resultCode);
}

- (ArchiveMetadata *)buildMetadata:(NSDictionary *)metadata {
	NSString *name    = metadata[@"name"]    ?: @"";
	NSString *summary = metadata[@"summary"] ?: @"";
	NSString *extra   = metadata[@"extra"]   ?: @"";
	int64_t  playtime = [metadata[@"playtime"] longLongValue];
	return [[ArchiveMetadata alloc] initWithName:name summary:summary extra:extra playtime:playtime];
}

- (NSString *)zipAndGetPath:(NSString *)filePath tempSuffix:(NSString **)outTempPath {
	NSFileManager *fm = [NSFileManager defaultManager];
	BOOL isDir = NO;
	if (![fm fileExistsAtPath:filePath isDirectory:&isDir]) {
		NSLog(@"[TapTap CloudSave] zipAndGetPath: source path not found: %@", filePath);
		return nil;
	}
	if (isDir) {
		NSLog(@"[TapTap CloudSave] zipAndGetPath: compressing directory: %@", filePath);
		NSString *tempZip = [filePath stringByAppendingString:@".cloudsave.tmp.zip"];
		NSData *zipData = [GodotZipHelper zipPath:filePath];
		if (!zipData) {
			NSLog(@"[TapTap CloudSave] zipAndGetPath: failed to compress directory: %@", filePath);
			return nil;
		}
		[zipData writeToFile:tempZip atomically:YES];
		NSLog(@"[TapTap CloudSave] zipAndGetPath: zip written to: %@ (%lu bytes)", tempZip, (unsigned long)zipData.length);
		if (outTempPath) *outTempPath = tempZip;
		return tempZip;
	}
	NSLog(@"[TapTap CloudSave] zipAndGetPath: using file as-is: %@", filePath);
	return filePath;
}

- (void)cleanupTempFile:(NSString *)tempPath {
	if (tempPath && tempPath.length > 0) {
		[[NSFileManager defaultManager] removeItemAtPath:tempPath error:nil];
	}
}

- (void)createArchiveWithMetadata:(NSDictionary *)metadata filePath:(NSString *)filePath coverPath:(NSString *)coverPath {
	NSLog(@"[TapTap CloudSave] createArchive: filePath=%@, coverPath=%@, metadata=%@", filePath, coverPath, metadata);
	dispatch_async(dispatch_get_main_queue(), ^{
		NSString *tempZip = nil;
		NSString *actualPath = [self zipAndGetPath:filePath tempSuffix:&tempZip];
		if (!actualPath) {
			NSLog(@"[TapTap CloudSave] createArchive: file/zip failed, aborting");
			Godot3TapTap::get_singleton()->emit_signal("onCreateArchiveFailed", String("{\"error\":\"File not found or zip failed\"}"));
			return;
		}
		NSLog(@"[TapTap CloudSave] createArchive: uploading actualPath=%@", actualPath);
		ArchiveMetadata *meta = [self buildMetadata:metadata];
		NSString *coverArg = (coverPath && coverPath.length > 0) ? coverPath : nil;
		GodotCloudSaveCallback *cb = [[GodotCloudSaveCallback alloc] initWithSuccess:@"onCreateArchiveSuccess"
		                                                                       error:@"onCreateArchiveFailed"
		                                                                   localPath:nil
		                                                                     tempZip:tempZip];
		[TapTapCloudSave createArchiveWithArchiveMetadata:meta
		                                  archiveFilePath:actualPath
		                                 archiveCoverPath:coverArg
		                                         callback:cb];  // cleanup happens in callback
	});
}

- (void)getArchiveList {
	NSLog(@"[TapTap CloudSave] getArchiveList: requesting archive list");
	dispatch_async(dispatch_get_main_queue(), ^{
		GodotCloudSaveCallback *cb = [[GodotCloudSaveCallback alloc] initWithSuccess:@"onGetArchiveListSuccess"
		                                                                       error:@"onGetArchiveListFailed"
		                                                                   localPath:nil];
		[TapTapCloudSave getArchiveListWithCallback:cb];
	});
}

- (void)downloadArchiveTo:(NSString *)localPath archiveUUID:(NSString *)archiveUUID fileID:(NSString *)fileID {
	NSLog(@"[TapTap CloudSave] downloadArchive: uuid=%@, fileID=%@, localPath=%@", archiveUUID, fileID, localPath);
	dispatch_async(dispatch_get_main_queue(), ^{
		GodotCloudSaveCallback *cb = [[GodotCloudSaveCallback alloc] initWithSuccess:@"onDownloadArchiveDataSuccess"
		                                                                       error:@"onDownloadArchiveDataFailed"
		                                                                   localPath:localPath];
		[TapTapCloudSave getArchiveDataWithArchiveUUID:archiveUUID archiveFileID:fileID callback:cb];
	});
}

- (void)updateArchiveUUID:(NSString *)archiveUUID metadata:(NSDictionary *)metadata filePath:(NSString *)filePath coverPath:(NSString *)coverPath {
	NSLog(@"[TapTap CloudSave] updateArchive: uuid=%@, filePath=%@, coverPath=%@, metadata=%@", archiveUUID, filePath, coverPath, metadata);
	dispatch_async(dispatch_get_main_queue(), ^{
		NSString *tempZip = nil;
		NSString *actualPath = [self zipAndGetPath:filePath tempSuffix:&tempZip];
		if (!actualPath) {
			NSLog(@"[TapTap CloudSave] updateArchive: file/zip failed, aborting");
			Godot3TapTap::get_singleton()->emit_signal("onUpdateArchiveFailed", String("{\"error\":\"File not found or zip failed\"}"));
			return;
		}
		NSLog(@"[TapTap CloudSave] updateArchive: uploading actualPath=%@", actualPath);
		ArchiveMetadata *meta = [self buildMetadata:metadata];
		NSString *coverArg = (coverPath && coverPath.length > 0) ? coverPath : nil;
		GodotCloudSaveCallback *cb = [[GodotCloudSaveCallback alloc] initWithSuccess:@"onUpdateArchiveSuccess"
		                                                                       error:@"onUpdateArchiveFailed"
		                                                                   localPath:nil
		                                                                     tempZip:tempZip];
		[TapTapCloudSave updateArchiveWithArchiveUUID:archiveUUID
		                              archiveMetadata:meta
		                              archiveFilePath:actualPath
		                             archiveCoverPath:coverArg
		                                     callback:cb];  // cleanup happens in callback
	});
}

- (void)deleteArchiveUUID:(NSString *)archiveUUID {
	NSLog(@"[TapTap CloudSave] deleteArchive: uuid=%@", archiveUUID);
	dispatch_async(dispatch_get_main_queue(), ^{
		GodotCloudSaveCallback *cb = [[GodotCloudSaveCallback alloc] initWithSuccess:@"onDeleteArchiveSuccess"
		                                                                       error:@"onDeleteArchiveFailed"
		                                                                   localPath:nil];
		[TapTapCloudSave deleteArchiveWithArchiveUUID:archiveUUID callback:cb];
	});
}

- (void)getArchiveCoverUUID:(NSString *)archiveUUID fileID:(NSString *)fileID {
	NSLog(@"[TapTap CloudSave] getArchiveCover: uuid=%@, fileID=%@", archiveUUID, fileID);
	dispatch_async(dispatch_get_main_queue(), ^{
		GodotCloudSaveCallback *cb = [[GodotCloudSaveCallback alloc] initWithSuccess:@"onGetArchiveCoverSuccess"
		                                                                       error:@"onGetArchiveCoverFailed"
		                                                                   localPath:nil];
		[TapTapCloudSave getArchiveCoverWithArchiveUUID:archiveUUID archiveFileID:fileID callback:cb];
	});
}

@end

// MARK: - TapTap Injector for OpenURL

@interface TapTapInjector : NSObject
@end

@implementation TapTapInjector

+ (void)load {
	static dispatch_once_t onceToken;
	dispatch_once(&onceToken, ^{
		[self injectAppDelegate];
		if (@available(iOS 13.0, *)) {
			[self injectSceneDelegate];
		}
	});
}

+ (void)injectAppDelegate {
	Class appDelegateClass = NSClassFromString(@"AppDelegate");
	if (!appDelegateClass) {
		appDelegateClass = NSClassFromString(@"GodotApplicalitionDelegate");
	}

	if (appDelegateClass) {
		SEL originalSelector = @selector(application:openURL:options:);
		SEL swizzledSelector = @selector(taptap_application:openURL:options:);

		Method originalMethod = class_getInstanceMethod(appDelegateClass, originalSelector);
		Method swizzledMethod = class_getInstanceMethod([self class], swizzledSelector);

		if (!originalMethod) {
			// Original method doesn't exist, just add our implementation directly
			class_addMethod(appDelegateClass,
					originalSelector,
					imp_implementationWithBlock(^BOOL(id self, UIApplication *app, NSURL *url, NSDictionary *options) {
						return [TapTapLogin openWithUrl:url];
					}),
					"B@:@@@");
		} else if (swizzledMethod) {
			// Original method exists, perform method swizzling
			class_addMethod(appDelegateClass,
					swizzledSelector,
					method_getImplementation(swizzledMethod),
					method_getTypeEncoding(swizzledMethod));

			Method newMethod = class_getInstanceMethod(appDelegateClass, swizzledSelector);
			if (newMethod) {
				method_exchangeImplementations(originalMethod, newMethod);
			}
		}
	}
}

+ (void)injectSceneDelegate {
	Class sceneDelegateClass = NSClassFromString(@"SceneDelegate");
	if (sceneDelegateClass) {
		SEL originalSelector = @selector(scene:openURLContexts:);
		SEL swizzledSelector = @selector(taptap_scene:openURLContexts:);

		Method originalMethod = class_getInstanceMethod(sceneDelegateClass, originalSelector);
		Method swizzledMethod = class_getInstanceMethod([self class], swizzledSelector);

		if (!originalMethod) {
			// Original method doesn't exist, just add our implementation directly
			class_addMethod(sceneDelegateClass,
					originalSelector,
					imp_implementationWithBlock(^(id self, UIScene *scene, NSSet<UIOpenURLContext *> *URLContexts) {
						for (UIOpenURLContext *context in URLContexts) {
							[TapTapLogin openWithUrl:context.URL];
						}
					}),
					"v@:@@");
		} else if (swizzledMethod) {
			// Original method exists, perform method swizzling
			class_addMethod(sceneDelegateClass,
					swizzledSelector,
					method_getImplementation(swizzledMethod),
					method_getTypeEncoding(swizzledMethod));

			Method newMethod = class_getInstanceMethod(sceneDelegateClass, swizzledSelector);
			if (newMethod) {
				method_exchangeImplementations(originalMethod, newMethod);
			}
		}
	}
}

- (BOOL)taptap_application:(UIApplication *)app openURL:(NSURL *)url options:(NSDictionary<UIApplicationOpenURLOptionsKey, id> *)options {
	// Handle TapTap login callback
	if ([TapTapLogin openWithUrl:url]) {
		return YES;
	}

	// Call original implementation (which is now swizzled to taptap_application:openURL:options:)
	return [self taptap_application:app openURL:url options:options];
}

- (void)taptap_scene:(UIScene *)scene openURLContexts:(NSSet<UIOpenURLContext *> *)URLContexts API_AVAILABLE(ios(13.0)) {
	// Handle TapTap login callback
	for (UIOpenURLContext *context in URLContexts) {
		[TapTapLogin openWithUrl:context.URL];
	}

	// Call original implementation (which is now swizzled to taptap_scene:openURLContexts:)
	[self taptap_scene:scene openURLContexts:URLContexts];
}

@end

// MARK: - Static delegate instance
static GodotTapTapDelegate *taptap_delegate = nil;

// MARK: - ZIP Helper (using libz for standard ZIP format)

static void zip_write_le16(NSMutableData *buf, uint16_t v) {
	uint8_t b[2] = { (uint8_t)(v & 0xFF), (uint8_t)(v >> 8) };
	[buf appendBytes:b length:2];
}

static void zip_write_le32(NSMutableData *buf, uint32_t v) {
	uint8_t b[4] = { (uint8_t)(v & 0xFF), (uint8_t)((v >> 8) & 0xFF), (uint8_t)((v >> 16) & 0xFF), (uint8_t)(v >> 24) };
	[buf appendBytes:b length:4];
}

static uint16_t zip_read_le16(const uint8_t *p) {
	return (uint16_t)(p[0] | ((uint16_t)p[1] << 8));
}

static uint32_t zip_read_le32(const uint8_t *p) {
	return (uint32_t)(p[0] | ((uint32_t)p[1] << 8) | ((uint32_t)p[2] << 16) | ((uint32_t)p[3] << 24));
}

static const uint32_t kZipLFHSig  = 0x04034b50U;
static const uint32_t kZipCDHSig  = 0x02014b50U;
static const uint32_t kZipEOCDSig = 0x06054b50U;

@interface GodotZipHelper : NSObject

+ (NSData *)zipPath:(NSString *)sourcePath;
+ (BOOL)unzipData:(NSData *)zipData toPath:(NSString *)destPath;

@end

@implementation GodotZipHelper

/// Compress one file and append local header + compressed data to buf.
/// Adds a central directory entry dict to entries.
+ (void)addFile:(NSString *)filePath entryName:(NSString *)entryName buf:(NSMutableData *)buf entries:(NSMutableArray *)entries {
	NSData *raw = [NSData dataWithContentsOfFile:filePath];
	if (!raw) return;

	uint32_t crc = (uint32_t)crc32(0, (const Bytef *)raw.bytes, (uInt)raw.length);

	// Deflate with raw stream (wbits = -15)
	uLongf bound = compressBound((uLong)raw.length) + 32;
	NSMutableData *comp = [NSMutableData dataWithLength:bound];
	z_stream zs;
	memset(&zs, 0, sizeof(zs));
	deflateInit2(&zs, Z_DEFAULT_COMPRESSION, Z_DEFLATED, -15, 8, Z_DEFAULT_STRATEGY);
	zs.next_in  = (Bytef *)raw.bytes;
	zs.avail_in = (uInt)raw.length;
	zs.next_out = (Bytef *)comp.mutableBytes;
	zs.avail_out = (uInt)bound;
	deflate(&zs, Z_FINISH);
	deflateEnd(&zs);
	uint32_t compSize = (uint32_t)(bound - zs.avail_out);
	[comp setLength:compSize];

	NSData *nameBytes = [entryName dataUsingEncoding:NSUTF8StringEncoding];
	uint32_t offset = (uint32_t)buf.length;

	// Local file header
	zip_write_le32(buf, kZipLFHSig);
	zip_write_le16(buf, 20);                         // version needed
	zip_write_le16(buf, 0);                          // flags
	zip_write_le16(buf, 8);                          // DEFLATE
	zip_write_le16(buf, 0);                          // mod time
	zip_write_le16(buf, 0);                          // mod date
	zip_write_le32(buf, crc);
	zip_write_le32(buf, compSize);
	zip_write_le32(buf, (uint32_t)raw.length);
	zip_write_le16(buf, (uint16_t)nameBytes.length);
	zip_write_le16(buf, 0);                          // extra len
	[buf appendData:nameBytes];
	[buf appendData:comp];

	[entries addObject:@{
		@"name"           : entryName,
		@"crc32"          : @(crc),
		@"compressedSize" : @(compSize),
		@"uncompSize"     : @((uint32_t)raw.length),
		@"offset"         : @(offset),
		@"compression"    : @(8),
		@"isDir"          : @NO
	}];
}

/// Add a directory entry (0-byte stored entry with trailing /)
+ (void)addDirEntry:(NSString *)entryName buf:(NSMutableData *)buf entries:(NSMutableArray *)entries {
	NSString *nameWithSlash = [entryName hasSuffix:@"/"] ? entryName : [entryName stringByAppendingString:@"/"];
	NSData *nameBytes = [nameWithSlash dataUsingEncoding:NSUTF8StringEncoding];
	uint32_t offset = (uint32_t)buf.length;

	zip_write_le32(buf, kZipLFHSig);
	zip_write_le16(buf, 20);
	zip_write_le16(buf, 0);
	zip_write_le16(buf, 0);  // STORE
	zip_write_le16(buf, 0);
	zip_write_le16(buf, 0);
	zip_write_le32(buf, 0);
	zip_write_le32(buf, 0);
	zip_write_le32(buf, 0);
	zip_write_le16(buf, (uint16_t)nameBytes.length);
	zip_write_le16(buf, 0);
	[buf appendData:nameBytes];

	[entries addObject:@{
		@"name"           : nameWithSlash,
		@"crc32"          : @(0U),
		@"compressedSize" : @(0U),
		@"uncompSize"     : @(0U),
		@"offset"         : @(offset),
		@"compression"    : @(0),
		@"isDir"          : @YES
	}];
}

/// Recursively add directory contents.
+ (void)addDirectory:(NSString *)dirPath base:(NSString *)base buf:(NSMutableData *)buf entries:(NSMutableArray *)entries {
	NSFileManager *fm = [NSFileManager defaultManager];
	NSArray *items = [fm contentsOfDirectoryAtPath:dirPath error:nil];
	for (NSString *item in items) {
		NSString *fullPath = [dirPath stringByAppendingPathComponent:item];
		NSString *entryName = base.length ? [base stringByAppendingPathComponent:item] : item;
		BOOL isDir = NO;
		[fm fileExistsAtPath:fullPath isDirectory:&isDir];
		if (isDir) {
			[self addDirEntry:entryName buf:buf entries:entries];
			[self addDirectory:fullPath base:entryName buf:buf entries:entries];
		} else {
			[self addFile:fullPath entryName:entryName buf:buf entries:entries];
		}
	}
}

+ (NSData *)zipPath:(NSString *)sourcePath {
	NSFileManager *fm = [NSFileManager defaultManager];
	NSMutableData *buf     = [NSMutableData data];
	NSMutableArray *entries = [NSMutableArray array];

	BOOL isDir = NO;
	if (![fm fileExistsAtPath:sourcePath isDirectory:&isDir]) {
		NSLog(@"[TapTap CloudSave] zipPath: not found: %@", sourcePath);
		return nil;
	}

	if (isDir) {
		[self addDirectory:sourcePath base:@"" buf:buf entries:entries];
	} else {
		[self addFile:sourcePath entryName:[sourcePath lastPathComponent] buf:buf entries:entries];
	}

	// Central directory
	uint32_t cdOffset = (uint32_t)buf.length;
	for (NSDictionary *e in entries) {
		NSData *nameBytes = [e[@"name"] dataUsingEncoding:NSUTF8StringEncoding];
		zip_write_le32(buf, kZipCDHSig);
		zip_write_le16(buf, 20);  // version made
		zip_write_le16(buf, 20);  // version needed
		zip_write_le16(buf, 0);   // flags
		zip_write_le16(buf, [e[@"compression"] unsignedShortValue]);
		zip_write_le16(buf, 0);   // mod time
		zip_write_le16(buf, 0);   // mod date
		zip_write_le32(buf, [e[@"crc32"] unsignedIntValue]);
		zip_write_le32(buf, [e[@"compressedSize"] unsignedIntValue]);
		zip_write_le32(buf, [e[@"uncompSize"] unsignedIntValue]);
		zip_write_le16(buf, (uint16_t)nameBytes.length);
		zip_write_le16(buf, 0);   // extra len
		zip_write_le16(buf, 0);   // comment len
		zip_write_le16(buf, 0);   // disk start
		zip_write_le16(buf, 0);   // internal attr
		zip_write_le32(buf, [e[@"isDir"] boolValue] ? 0x10 : 0x20);  // external attr (dir/file)
		zip_write_le32(buf, [e[@"offset"] unsignedIntValue]);
		[buf appendData:nameBytes];
	}

	uint32_t cdSize  = (uint32_t)buf.length - cdOffset;
	uint16_t count   = (uint16_t)entries.count;

	// End of central directory
	zip_write_le32(buf, kZipEOCDSig);
	zip_write_le16(buf, 0);      // disk number
	zip_write_le16(buf, 0);      // cd start disk
	zip_write_le16(buf, count);  // entries on disk
	zip_write_le16(buf, count);  // total entries
	zip_write_le32(buf, cdSize);
	zip_write_le32(buf, cdOffset);
	zip_write_le16(buf, 0);      // comment len

	return [NSData dataWithData:buf];
}

+ (BOOL)unzipData:(NSData *)zipData toPath:(NSString *)destPath {
	if (!zipData || zipData.length < 22) return NO;

	const uint8_t *bytes = (const uint8_t *)zipData.bytes;
	NSUInteger size = zipData.length;
	NSFileManager *fm = [NSFileManager defaultManager];

	// Find EOCD record (search from end)
	NSUInteger eocdPos = NSNotFound;
	for (NSInteger i = (NSInteger)size - 22; i >= 0; i--) {
		if (zip_read_le32(bytes + i) == kZipEOCDSig) {
			eocdPos = (NSUInteger)i;
			break;
		}
	}
	if (eocdPos == NSNotFound) {
		NSLog(@"[TapTap CloudSave] unzip: EOCD not found");
		return NO;
	}

	uint16_t totalEntries = zip_read_le16(bytes + eocdPos + 10);
	uint32_t cdOffset     = zip_read_le32(bytes + eocdPos + 16);

	[fm createDirectoryAtPath:destPath withIntermediateDirectories:YES attributes:nil error:nil];

	NSUInteger pos = cdOffset;
	for (int i = 0; i < totalEntries; i++) {
		if (pos + 46 > size || zip_read_le32(bytes + pos) != kZipCDHSig) break;

		uint16_t compression  = zip_read_le16(bytes + pos + 10);
		uint32_t compSize     = zip_read_le32(bytes + pos + 20);
		uint32_t uncompSize   = zip_read_le32(bytes + pos + 24);
		uint16_t nameLen      = zip_read_le16(bytes + pos + 28);
		uint16_t extraLen     = zip_read_le16(bytes + pos + 30);
		uint16_t commentLen   = zip_read_le16(bytes + pos + 32);
		uint32_t localOffset  = zip_read_le32(bytes + pos + 42);

		NSString *entryName = [[NSString alloc] initWithBytes:bytes + pos + 46 length:nameLen encoding:NSUTF8StringEncoding];
		if (!entryName) {
			entryName = [[NSString alloc] initWithBytes:bytes + pos + 46 length:nameLen encoding:NSISOLatin1StringEncoding];
		}
		pos += 46 + nameLen + extraLen + commentLen;
		if (!entryName) continue;

		NSString *outPath = [destPath stringByAppendingPathComponent:entryName];

		// Directory entry
		if ([entryName hasSuffix:@"/"] || (compSize == 0 && uncompSize == 0)) {
			[fm createDirectoryAtPath:outPath withIntermediateDirectories:YES attributes:nil error:nil];
			continue;
		}

		// Ensure parent directory exists
		[fm createDirectoryAtPath:[outPath stringByDeletingLastPathComponent]
		  withIntermediateDirectories:YES attributes:nil error:nil];

		// Locate actual data via local file header
		if ((NSUInteger)localOffset + 30 > size) continue;
		uint16_t lfhNameLen  = zip_read_le16(bytes + localOffset + 26);
		uint16_t lfhExtraLen = zip_read_le16(bytes + localOffset + 28);
		NSUInteger dataStart = (NSUInteger)localOffset + 30 + lfhNameLen + lfhExtraLen;
		if (dataStart + compSize > size) continue;

		const uint8_t *compData = bytes + dataStart;
		NSData *fileData = nil;

		if (compression == 0) {
			fileData = [NSData dataWithBytes:compData length:compSize];
		} else if (compression == 8) {
			NSMutableData *inflated = [NSMutableData dataWithLength:uncompSize];
			z_stream zs;
			memset(&zs, 0, sizeof(zs));
			inflateInit2(&zs, -15);
			zs.next_in   = (Bytef *)compData;
			zs.avail_in  = compSize;
			zs.next_out  = (Bytef *)inflated.mutableBytes;
			zs.avail_out = uncompSize;
			int ret = inflate(&zs, Z_FINISH);
			inflateEnd(&zs);
			if (ret == Z_STREAM_END || ret == Z_OK) {
				fileData = [NSData dataWithData:inflated];
			}
		}

		if (fileData) {
			[fileData writeToFile:outPath atomically:YES];
		}
	}
	return YES;
}

@end

// MARK: - Cloud Save Request Callback

@interface GodotCloudSaveCallback : NSObject <TapTapCloudSaveRequestCallback>

@property(nonatomic, copy) NSString *successSignal;
@property(nonatomic, copy) NSString *errorSignal;
@property(nonatomic, copy) NSString *localPath;    // used for download
@property(nonatomic, copy) NSString *tempZipPath;  // temp file to delete after upload

- (instancetype)initWithSuccess:(NSString *)success error:(NSString *)error localPath:(NSString *)localPath;
- (instancetype)initWithSuccess:(NSString *)success error:(NSString *)error localPath:(NSString *)localPath tempZip:(NSString *)tempZip;

@end

@implementation GodotCloudSaveCallback

- (instancetype)initWithSuccess:(NSString *)success error:(NSString *)error localPath:(NSString *)lp {
	return [self initWithSuccess:success error:error localPath:lp tempZip:nil];
}

- (instancetype)initWithSuccess:(NSString *)success error:(NSString *)error localPath:(NSString *)lp tempZip:(NSString *)tz {
	self = [super init];
	if (self) {
		_successSignal = success;
		_errorSignal   = error;
		_localPath     = lp;
		_tempZipPath   = tz;
	}
	return self;
}

- (void)cleanupTempZip {
	if (_tempZipPath && _tempZipPath.length > 0) {
		[[NSFileManager defaultManager] removeItemAtPath:_tempZipPath error:nil];
		_tempZipPath = nil;
	}
}

- (NSString *)archiveToJSON:(ArchiveData *)archive {
	NSDictionary *d = @{
		@"uuid"         : archive.uuid ?: @"",
		@"name"         : archive.name ?: @"",
		@"summary"      : archive.summary ?: @"",
		@"extra"        : archive.extra ?: @"",
		@"playtime"     : @(archive.playtime),
		@"fileId"       : archive.fileId ?: @"",
		@"coverSize"    : @(archive.coverSize),
		@"createdTime"  : @(archive.createdTime),
		@"modifiedTime" : @(archive.modifiedTime),
		@"saveSize"     : @(archive.saveSize)
	};
	NSData *jsonData = [NSJSONSerialization dataWithJSONObject:d options:0 error:nil];
	return jsonData ? [[NSString alloc] initWithData:jsonData encoding:NSUTF8StringEncoding] : @"{}";
}

- (void)onArchiveCreatedWithArchive:(ArchiveData *)archive {
	NSLog(@"[TapTap CloudSave] callback onArchiveCreated: uuid=%@, name=%@", archive.uuid, archive.name);
	NSString *json = [self archiveToJSON:archive];
	[self cleanupTempZip];
	Godot3TapTap::get_singleton()->emit_signal(_successSignal.UTF8String, String::utf8(json.UTF8String));
}

- (void)onArchiveUpdatedWithArchive:(ArchiveData *)archive {
	NSLog(@"[TapTap CloudSave] callback onArchiveUpdated: uuid=%@, name=%@", archive.uuid, archive.name);
	NSString *json = [self archiveToJSON:archive];
	[self cleanupTempZip];
	Godot3TapTap::get_singleton()->emit_signal(_successSignal.UTF8String, String::utf8(json.UTF8String));
}

- (void)onArchiveDeletedWithArchive:(ArchiveData *)archive {
	NSLog(@"[TapTap CloudSave] callback onArchiveDeleted: uuid=%@", archive.uuid);
	NSString *json = [self archiveToJSON:archive];
	Godot3TapTap::get_singleton()->emit_signal(_successSignal.UTF8String, String::utf8(json.UTF8String));
}

- (void)onArchiveListResultWithArchives:(NSArray<ArchiveData *> *)archives {
	NSLog(@"[TapTap CloudSave] callback onArchiveListResult: count=%lu", (unsigned long)archives.count);
	NSMutableArray *arr = [NSMutableArray array];
	for (ArchiveData *a in archives) {
		[arr addObject:@{
			@"uuid"         : a.uuid ?: @"",
			@"name"         : a.name ?: @"",
			@"summary"      : a.summary ?: @"",
			@"extra"        : a.extra ?: @"",
			@"playtime"     : @(a.playtime),
			@"fileId"       : a.fileId ?: @"",
			@"coverSize"    : @(a.coverSize),
			@"createdTime"  : @(a.createdTime),
			@"modifiedTime" : @(a.modifiedTime),
			@"saveSize"     : @(a.saveSize)
		}];
	}
	NSDictionary *result = @{ @"archives": arr, @"count": @(arr.count) };
	NSData *jsonData = [NSJSONSerialization dataWithJSONObject:result options:0 error:nil];
	NSString *json = jsonData ? [[NSString alloc] initWithData:jsonData encoding:NSUTF8StringEncoding] : @"{\"archives\":[],\"count\":0}";
	Godot3TapTap::get_singleton()->emit_signal(_successSignal.UTF8String, String::utf8(json.UTF8String));
}

- (void)onArchiveDataResultWithArchiveUUID:(NSString *)archiveUUID archiveFileID:(NSString *)archiveFileID data:(NSData *)data {
	NSLog(@"[TapTap CloudSave] callback onArchiveDataResult: uuid=%@, fileID=%@, dataSize=%lu bytes", archiveUUID, archiveFileID, (unsigned long)data.length);
	if (!_localPath || _localPath.length == 0) {
		NSString *err = @"{\"error\":\"localPath not specified\"}";
		Godot3TapTap::get_singleton()->emit_signal(_errorSignal.UTF8String, String::utf8(err.UTF8String));
		return;
	}

	NSFileManager *fm = [NSFileManager defaultManager];
	// Clean existing target
	BOOL isDir = NO;
	if ([fm fileExistsAtPath:_localPath isDirectory:&isDir]) {
		if (isDir) {
			NSArray *contents = [fm contentsOfDirectoryAtPath:_localPath error:nil];
			for (NSString *item in contents) {
				[fm removeItemAtPath:[_localPath stringByAppendingPathComponent:item] error:nil];
			}
		} else {
			[fm removeItemAtPath:_localPath error:nil];
		}
	}

	// Check if data is a standard ZIP (magic: PK\x03\x04)
	const uint8_t zipMagic[4] = { 0x50, 0x4B, 0x03, 0x04 };
	BOOL isZip = data.length >= 4 && memcmp(data.bytes, zipMagic, 4) == 0;
	NSLog(@"[TapTap CloudSave] onArchiveDataResult: isZip=%@, destPath=%@", isZip ? @"YES" : @"NO", _localPath);
	BOOL success = NO;

	if (isZip) {
		NSLog(@"[TapTap CloudSave] onArchiveDataResult: unzipping to %@", _localPath);
		success = [GodotZipHelper unzipData:data toPath:_localPath];
		NSLog(@"[TapTap CloudSave] onArchiveDataResult: unzip %@", success ? @"succeeded" : @"failed");
	}
	if (!success) {
		// Not a zip or unzip failed — write raw data directly
		NSLog(@"[TapTap CloudSave] onArchiveDataResult: writing raw data to %@", _localPath);
		[fm createDirectoryAtPath:[_localPath stringByDeletingLastPathComponent]
		  withIntermediateDirectories:YES attributes:nil error:nil];
		success = [data writeToFile:_localPath atomically:YES];
		NSLog(@"[TapTap CloudSave] onArchiveDataResult: raw write %@", success ? @"succeeded" : @"failed");
	}

	if (success) {
		NSDictionary *result = @{ @"path": _localPath, @"size": @((uint32_t)data.length) };
		NSData *jsonData = [NSJSONSerialization dataWithJSONObject:result options:0 error:nil];
		NSString *json = jsonData ? [[NSString alloc] initWithData:jsonData encoding:NSUTF8StringEncoding] : @"{}";
		Godot3TapTap::get_singleton()->emit_signal(_successSignal.UTF8String, String::utf8(json.UTF8String));
	} else {
		NSString *err = @"{\"error\":\"Failed to write archive data\"}";
		Godot3TapTap::get_singleton()->emit_signal(_errorSignal.UTF8String, String::utf8(err.UTF8String));
	}
}

- (void)onArchiveCoverResultWithArchiveUUID:(NSString *)archiveUUID archiveFileID:(NSString *)archiveFileID coverData:(NSData *)coverData {
	NSLog(@"[TapTap CloudSave] callback onArchiveCoverResult: uuid=%@, fileID=%@, coverSize=%lu bytes", archiveUUID, archiveFileID, (unsigned long)coverData.length);
	// Pass raw cover bytes as PoolByteArray
	if (coverData && coverData.length > 0) {
		PoolByteArray pba;
		pba.resize((int)coverData.length);
		PoolByteArray::Write w = pba.write();
		memcpy(w.ptr(), coverData.bytes, coverData.length);
		Godot3TapTap::get_singleton()->emit_signal(_successSignal.UTF8String, pba);
	} else {
		NSString *err = @"{\"error\":\"Empty cover data\"}";
		Godot3TapTap::get_singleton()->emit_signal(_errorSignal.UTF8String, String::utf8(err.UTF8String));
	}
}

- (void)onRequestErrorWithErrorCode:(NSInteger)errorCode errorMessage:(NSString *)errorMessage {
	NSLog(@"[TapTap CloudSave] callback onRequestError: code=%ld, message=%@", (long)errorCode, errorMessage);
	[self cleanupTempZip];
	NSDictionary *errDict = @{ @"code": @(errorCode), @"message": errorMessage ?: @"" };
	NSData *jsonData = [NSJSONSerialization dataWithJSONObject:errDict options:0 error:nil];
	NSString *json = jsonData ? [[NSString alloc] initWithData:jsonData encoding:NSUTF8StringEncoding] : @"{\"error\":\"unknown\"}";
	Godot3TapTap::get_singleton()->emit_signal(_errorSignal.UTF8String, String::utf8(json.UTF8String));
}

@end

// MARK: - C++ Plugin Implementation

Godot3TapTap *Godot3TapTap::instance = NULL;

void Godot3TapTap::_bind_methods() {
	// SDK 初始化
	ClassDB::bind_method(D_METHOD("initSdk"), &Godot3TapTap::initSdk);
	ClassDB::bind_method(D_METHOD("initSdkWithEncryptedToken"), &Godot3TapTap::initSdkWithEncryptedToken);

	// 登录
	ClassDB::bind_method(D_METHOD("login"), &Godot3TapTap::login);
	ClassDB::bind_method(D_METHOD("isLogin"), &Godot3TapTap::isLogin);
	ClassDB::bind_method(D_METHOD("getUserProfile"), &Godot3TapTap::getUserProfile);
	ClassDB::bind_method(D_METHOD("logout"), &Godot3TapTap::logout);
	ClassDB::bind_method(D_METHOD("logoutThenRestart"), &Godot3TapTap::logoutThenRestart);

	// 合规认证
	ClassDB::bind_method(D_METHOD("compliance"), &Godot3TapTap::compliance);
	ClassDB::bind_method(D_METHOD("complianceExit"), &Godot3TapTap::complianceExit);

	// License & DLC（iOS 不支持）
	ClassDB::bind_method(D_METHOD("checkLicense"), &Godot3TapTap::checkLicense);
	ClassDB::bind_method(D_METHOD("queryDLC"), &Godot3TapTap::queryDLC);
	ClassDB::bind_method(D_METHOD("purchaseDLC"), &Godot3TapTap::purchaseDLC);

	// IAP（iOS 不支持）
	ClassDB::bind_method(D_METHOD("queryProductDetailsAsync"), &Godot3TapTap::queryProductDetailsAsync);
	ClassDB::bind_method(D_METHOD("launchBillingFlow"), &Godot3TapTap::launchBillingFlow);
	ClassDB::bind_method(D_METHOD("finishPurchaseAsync"), &Godot3TapTap::finishPurchaseAsync);
	ClassDB::bind_method(D_METHOD("queryUnfinishedPurchaseAsync"), &Godot3TapTap::queryUnfinishedPurchaseAsync);

	// 工具方法
	ClassDB::bind_method(D_METHOD("showTip"), &Godot3TapTap::showTip);
	ClassDB::bind_method(D_METHOD("restartApp"), &Godot3TapTap::restartApp);

	// 云存档
	ClassDB::bind_method(D_METHOD("createArchive"), &Godot3TapTap::createArchive);
	ClassDB::bind_method(D_METHOD("getArchiveList"), &Godot3TapTap::getArchiveList);
	ClassDB::bind_method(D_METHOD("downloadArchiveData"), &Godot3TapTap::downloadArchiveData);
	ClassDB::bind_method(D_METHOD("updateArchive"), &Godot3TapTap::updateArchive);
	ClassDB::bind_method(D_METHOD("deleteArchive"), &Godot3TapTap::deleteArchive);
	ClassDB::bind_method(D_METHOD("getArchiveCover"), &Godot3TapTap::getArchiveCover);

	// 信号（与 Android 版本完全一致）
	ADD_SIGNAL(MethodInfo("onLoginSuccess"));
	ADD_SIGNAL(MethodInfo("onLoginFail", PropertyInfo(Variant::STRING, "message")));
	ADD_SIGNAL(MethodInfo("onLoginCancel"));
	ADD_SIGNAL(MethodInfo("onComplianceResult", PropertyInfo(Variant::INT, "code"), PropertyInfo(Variant::STRING, "info")));
	ADD_SIGNAL(MethodInfo("onLicenseSuccess"));
	ADD_SIGNAL(MethodInfo("onLicenseFailed"));
	ADD_SIGNAL(MethodInfo("onDLCQueryResult", PropertyInfo(Variant::STRING, "jsonString")));
	ADD_SIGNAL(MethodInfo("onDLCPurchaseResult", PropertyInfo(Variant::STRING, "skuId"), PropertyInfo(Variant::INT, "status")));
	ADD_SIGNAL(MethodInfo("onProductDetailsResponse", PropertyInfo(Variant::STRING, "jsonString")));
	ADD_SIGNAL(MethodInfo("onPurchaseUpdated", PropertyInfo(Variant::STRING, "jsonString")));
	ADD_SIGNAL(MethodInfo("onFinishPurchaseResponse", PropertyInfo(Variant::STRING, "jsonString")));
	ADD_SIGNAL(MethodInfo("onQueryUnfinishedPurchaseResponse", PropertyInfo(Variant::STRING, "jsonString")));
	ADD_SIGNAL(MethodInfo("onLaunchBillingFlowResult", PropertyInfo(Variant::STRING, "jsonString")));

	// 云存档信号
	ADD_SIGNAL(MethodInfo("onCloudSaveCallback", PropertyInfo(Variant::INT, "resultCode")));
	ADD_SIGNAL(MethodInfo("onCreateArchiveSuccess", PropertyInfo(Variant::STRING, "jsonString")));
	ADD_SIGNAL(MethodInfo("onCreateArchiveFailed", PropertyInfo(Variant::STRING, "jsonString")));
	ADD_SIGNAL(MethodInfo("onGetArchiveListSuccess", PropertyInfo(Variant::STRING, "jsonString")));
	ADD_SIGNAL(MethodInfo("onGetArchiveListFailed", PropertyInfo(Variant::STRING, "jsonString")));
	ADD_SIGNAL(MethodInfo("onDownloadArchiveDataSuccess", PropertyInfo(Variant::STRING, "jsonString")));
	ADD_SIGNAL(MethodInfo("onDownloadArchiveDataFailed", PropertyInfo(Variant::STRING, "jsonString")));
	ADD_SIGNAL(MethodInfo("onUpdateArchiveSuccess", PropertyInfo(Variant::STRING, "jsonString")));
	ADD_SIGNAL(MethodInfo("onUpdateArchiveFailed", PropertyInfo(Variant::STRING, "jsonString")));
	ADD_SIGNAL(MethodInfo("onDeleteArchiveSuccess", PropertyInfo(Variant::STRING, "jsonString")));
	ADD_SIGNAL(MethodInfo("onDeleteArchiveFailed", PropertyInfo(Variant::STRING, "jsonString")));
	ADD_SIGNAL(MethodInfo("onGetArchiveCoverSuccess", PropertyInfo(Variant::POOL_BYTE_ARRAY, "coverData")));
	ADD_SIGNAL(MethodInfo("onGetArchiveCoverFailed", PropertyInfo(Variant::STRING, "jsonString")));
}

// SDK 初始化
void Godot3TapTap::initSdk(const String &p_client_id, const String &p_client_token, bool p_enable_log, bool p_with_iap) {
	NSString *clientId = [[NSString alloc] initWithUTF8String:p_client_id.utf8().get_data()];
	NSString *clientToken = [[NSString alloc] initWithUTF8String:p_client_token.utf8().get_data()];

	[taptap_delegate initSDKWithClientId:clientId clientToken:clientToken enableLog:p_enable_log];
}

void Godot3TapTap::initSdkWithEncryptedToken(const String &p_client_id, const String &p_encrypted_token, bool p_enable_log, bool p_with_iap) {
	NSString *clientId = [[NSString alloc] initWithUTF8String:p_client_id.utf8().get_data()];
	NSString *encryptedToken = [[NSString alloc] initWithUTF8String:p_encrypted_token.utf8().get_data()];

	NSString *decryptedToken = [taptap_delegate decryptToken:encryptedToken];
	[taptap_delegate initSDKWithClientId:clientId clientToken:decryptedToken enableLog:p_enable_log];
}

// 登录
void Godot3TapTap::login(bool p_use_profile, bool p_use_friends) {
	[taptap_delegate loginWithProfile:p_use_profile friends:p_use_friends];
}

bool Godot3TapTap::isLogin() {
	return [taptap_delegate isLoggedIn];
}

String Godot3TapTap::getUserProfile() {
	NSDictionary *profile = [taptap_delegate getUserProfile];

	NSError *error = nil;
	NSData *jsonData = [NSJSONSerialization dataWithJSONObject:profile options:0 error:&error];
	if (!jsonData) return "{}";

	NSString *jsonString = [[NSString alloc] initWithData:jsonData encoding:NSUTF8StringEncoding];
	return String::utf8([jsonString UTF8String]);
}

void Godot3TapTap::logout() {
	[taptap_delegate logout];
}

void Godot3TapTap::logoutThenRestart() {
	logout();
	restartApp();
}

// 合规认证
void Godot3TapTap::compliance() {
	if (![taptap_delegate isLoggedIn]) {
		emit_signal("onComplianceResult", -1, "Not logged in");
		return;
	}

	TapTapAccount *account = [TapTapLogin getCurrentTapAccount];
	if (account && account.userInfo && account.userInfo.unionId) {
		[taptap_delegate startComplianceWithUserId:account.userInfo.unionId];
	}
}

void Godot3TapTap::complianceExit() {
	[taptap_delegate exitCompliance];
}

// License & DLC（iOS 不支持，返回占位）
void Godot3TapTap::checkLicense(bool p_force_check) {
	NSLog(@"[TapTap] License check not supported on iOS");
	emit_signal("onLicenseSuccess");
}

void Godot3TapTap::queryDLC(const Array &p_sku_ids) {
	NSLog(@"[TapTap] DLC query not supported on iOS");
	emit_signal("onDLCQueryResult", "{}");
}

void Godot3TapTap::purchaseDLC(const String &p_sku_id) {
	NSLog(@"[TapTap] DLC purchase not supported on iOS");
	emit_signal("onDLCPurchaseResult", p_sku_id, -1);
}

// IAP（iOS 不支持，返回占位）
void Godot3TapTap::queryProductDetailsAsync(const Array &p_products) {
	NSLog(@"[TapTap] IAP not supported on iOS");
	emit_signal("onProductDetailsResponse", "{}");
}

void Godot3TapTap::launchBillingFlow(const String &p_product_id, const String &p_account_id) {
	NSLog(@"[TapTap] IAP not supported on iOS");
	emit_signal("onLaunchBillingFlowResult", "{}");
}

void Godot3TapTap::finishPurchaseAsync(const String &p_order_id, const String &p_token) {
	NSLog(@"[TapTap] IAP not supported on iOS");
	emit_signal("onFinishPurchaseResponse", "{}");
}

void Godot3TapTap::queryUnfinishedPurchaseAsync() {
	NSLog(@"[TapTap] IAP not supported on iOS");
	emit_signal("onQueryUnfinishedPurchaseResponse", "{}");
}

// 工具方法
void Godot3TapTap::showTip(const String &p_text) {
	NSString *message = [[NSString alloc] initWithUTF8String:p_text.utf8().get_data()];
	dispatch_async(dispatch_get_main_queue(), ^{
		// 创建 Toast 视图
		UIView *toastView = [[UIView alloc] init];
		toastView.backgroundColor = [[UIColor blackColor] colorWithAlphaComponent:0.8];
		toastView.layer.cornerRadius = 10.0;
		toastView.clipsToBounds = YES;

		// 创建标签
		UILabel *label = [[UILabel alloc] init];
		label.text = message;
		label.textColor = [UIColor whiteColor];
		label.textAlignment = NSTextAlignmentCenter;
		label.font = [UIFont systemFontOfSize:14.0];
		label.numberOfLines = 0;
		[toastView addSubview:label];

		// 计算尺寸
		CGSize screenSize = [UIScreen mainScreen].bounds.size;
		CGFloat maxWidth = screenSize.width * 0.8;
		CGSize textSize = [message boundingRectWithSize:CGSizeMake(maxWidth, CGFLOAT_MAX)
												options:NSStringDrawingUsesLineFragmentOrigin
											 attributes:@{ NSFontAttributeName : label.font }
												context:nil]
								  .size;

		CGFloat padding = 20.0;
		toastView.frame = CGRectMake((screenSize.width - textSize.width - padding * 2) / 2,
				screenSize.height - 150,
				textSize.width + padding * 2,
				textSize.height + padding * 2);
		label.frame = CGRectMake(padding, padding, textSize.width, textSize.height);

		// 添加到窗口
		UIWindow *keyWindow = [UIApplication sharedApplication].keyWindow;
		[keyWindow addSubview:toastView];

		// 动画显示
		toastView.alpha = 0.0;
		[UIView animateWithDuration:0.3
				animations:^{
					toastView.alpha = 1.0;
				}
				completion:^(BOOL finished) {
					// 延迟消失
					dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(2.0 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
						[UIView animateWithDuration:0.3
								animations:^{
									toastView.alpha = 0.0;
								}
								completion:^(BOOL finished) {
									[toastView removeFromSuperview];
								}];
					});
				}];
	});
}

void Godot3TapTap::restartApp() {
	exit(0);
}

// MARK: - Cloud Save C++ Implementations

static NSDictionary *dictionaryFromGodotDict(const Dictionary &d) {
	NSMutableDictionary *result = [NSMutableDictionary dictionary];
	Array keys = d.keys();
	for (int i = 0; i < keys.size(); i++) {
		String key = keys[i];
		NSString *nsKey = [[NSString alloc] initWithUTF8String:key.utf8().get_data()];
		Variant val = d[keys[i]];
		if (val.get_type() == Variant::STRING) {
			String sv = val;
			result[nsKey] = [[NSString alloc] initWithUTF8String:sv.utf8().get_data()];
		} else if (val.get_type() == Variant::INT) {
			int64_t iv = val;
			result[nsKey] = @(iv);
		} else if (val.get_type() == Variant::REAL) {
			double dv = val;
			result[nsKey] = @(dv);
		} else {
			String sv = val;
			result[nsKey] = [[NSString alloc] initWithUTF8String:sv.utf8().get_data()];
		}
	}
	return [NSDictionary dictionaryWithDictionary:result];
}

void Godot3TapTap::createArchive(const Dictionary &p_metadata, const String &p_archive_file_path, const String &p_archive_cover_path) {
	NSDictionary *meta = dictionaryFromGodotDict(p_metadata);
	NSString *filePath  = [[NSString alloc] initWithUTF8String:p_archive_file_path.utf8().get_data()];
	NSString *coverPath = [[NSString alloc] initWithUTF8String:p_archive_cover_path.utf8().get_data()];
	[taptap_delegate createArchiveWithMetadata:meta filePath:filePath coverPath:coverPath];
}

void Godot3TapTap::getArchiveList() {
	[taptap_delegate getArchiveList];
}

void Godot3TapTap::downloadArchiveData(const String &p_archive_uuid, const String &p_archive_file_id, const String &p_local_archive_path) {
	NSString *uuid      = [[NSString alloc] initWithUTF8String:p_archive_uuid.utf8().get_data()];
	NSString *fileID    = [[NSString alloc] initWithUTF8String:p_archive_file_id.utf8().get_data()];
	NSString *localPath = [[NSString alloc] initWithUTF8String:p_local_archive_path.utf8().get_data()];
	[taptap_delegate downloadArchiveTo:localPath archiveUUID:uuid fileID:fileID];
}

void Godot3TapTap::updateArchive(const String &p_archive_uuid, const Dictionary &p_metadata, const String &p_archive_file_path, const String &p_archive_cover_path) {
	NSString *uuid      = [[NSString alloc] initWithUTF8String:p_archive_uuid.utf8().get_data()];
	NSDictionary *meta  = dictionaryFromGodotDict(p_metadata);
	NSString *filePath  = [[NSString alloc] initWithUTF8String:p_archive_file_path.utf8().get_data()];
	NSString *coverPath = [[NSString alloc] initWithUTF8String:p_archive_cover_path.utf8().get_data()];
	[taptap_delegate updateArchiveUUID:uuid metadata:meta filePath:filePath coverPath:coverPath];
}

void Godot3TapTap::deleteArchive(const String &p_archive_uuid) {
	NSString *uuid = [[NSString alloc] initWithUTF8String:p_archive_uuid.utf8().get_data()];
	[taptap_delegate deleteArchiveUUID:uuid];
}

void Godot3TapTap::getArchiveCover(const String &p_archive_uuid, const String &p_archive_file_id) {
	NSString *uuid   = [[NSString alloc] initWithUTF8String:p_archive_uuid.utf8().get_data()];
	NSString *fileID = [[NSString alloc] initWithUTF8String:p_archive_file_id.utf8().get_data()];
	[taptap_delegate getArchiveCoverUUID:uuid fileID:fileID];
}

Godot3TapTap *Godot3TapTap::get_singleton() {
	return instance;
}

Godot3TapTap::Godot3TapTap() {
	ERR_FAIL_COND(instance != NULL);
	instance = this;

	taptap_delegate = [[GodotTapTapDelegate alloc] init];
}

Godot3TapTap::~Godot3TapTap() {
	instance = NULL;
	taptap_delegate = nil;
}
