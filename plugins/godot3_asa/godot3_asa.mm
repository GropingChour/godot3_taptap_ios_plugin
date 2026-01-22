/*************************************************************************/
/*  godot3_asa.mm                                                        */
/*************************************************************************/
/*  iOS ASA (Apple Search Ads) Attribution Plugin for Godot 3.x          */
/*  使用AdServices框架实现客户端归因                                      */
/*************************************************************************/

#include "godot3_asa.h"

#if VERSION_MAJOR == 4
#include "core/io/json.h"
#import "platform/ios/app_delegate.h"
#else
#include "core/io/json.h"
#import "platform/iphone/app_delegate.h"
#endif

#import <AdServices/AdServices.h>
#import <Foundation/Foundation.h>

// MARK: - Objective-C Delegate

@interface GodotASADelegate : NSObject

- (void)requestAttributionToken;
- (void)requestAttributionDataWithToken:(NSString *)token;
- (void)performFullAttribution;
- (BOOL)isAdServicesSupported;
- (NSString *)getDeviceModel;
- (NSString *)getSystemVersion;

@end

@implementation GodotASADelegate

- (BOOL)isAdServicesSupported {
	if (@available(iOS 14.3, *)) {
		// 检查 AAAttribution 类是否存在（模拟器上可能不可用）
		Class aaClass = NSClassFromString(@"AAAttribution");
		if (aaClass == nil) {
			NSLog(@"[Godot3ASA] AAAttribution class not found (may not be available on simulator)");
			return NO;
		}
		return YES;
	}
	NSLog(@"[Godot3ASA] iOS version too old (requires iOS 14.3+)");
	return NO;
}

- (void)requestAttributionToken {
	if (@available(iOS 14.3, *)) {
		// 延迟执行以符合最佳实践（500-1000ms等待）
		dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.5 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
			NSError *error = nil;
			NSString *token = [AAAttribution attributionTokenWithError:&error];
			
			if (error != nil) {
				// 错误处理
				int errorCode = (int)[error code];
				NSString *errorMessage = [error localizedDescription];
				
				NSLog(@"[Godot3ASA] Token request failed: code=%ld, message=%@", (long)errorCode, errorMessage);
				
				// 发送失败信号给Godot
				Godot3ASA *singleton = Godot3ASA::get_singleton();
				if (singleton) {
					singleton->emit_signal(
						"onASATokenReceived",
						"",
						errorCode,
						String::utf8([errorMessage UTF8String])
					);
				} else {
					NSLog(@"[Godot3ASA] ERROR: Singleton is null, cannot emit signal");
				}
			} else if (token != nil && token.length > 0) {
				// 成功获取token
				NSLog(@"[Godot3ASA] Token received successfully, length: %lu", (unsigned long)token.length);
				
				// 发送成功信号给Godot
				Godot3ASA *singleton = Godot3ASA::get_singleton();
				if (singleton) {
					singleton->emit_signal(
						"onASATokenReceived",
						String::utf8([token UTF8String]),
						0,
						""
					);
				} else {
					NSLog(@"[Godot3ASA] ERROR: Singleton is null, cannot emit signal");
				}
			} else {
				// Token为空
				NSLog(@"[Godot3ASA] Token is empty");
				Godot3ASA *singleton = Godot3ASA::get_singleton();
				if (singleton) {
					singleton->emit_signal(
						"onASATokenReceived",
						"",
						-1,
						"Token is empty"
					);
				} else {
					NSLog(@"[Godot3ASA] ERROR: Singleton is null, cannot emit signal");
				}
			}
		});
	} else {
		// iOS版本不支持
		NSLog(@"[Godot3ASA] AdServices not supported on this iOS version (requires iOS 14.3+)");
		Godot3ASA *singleton = Godot3ASA::get_singleton();
		if (singleton) {
			singleton->emit_signal(
				"onASATokenReceived",
				"",
				-2,
				"AdServices not supported (iOS 14.3+ required)"
			);
		} else {
			NSLog(@"[Godot3ASA] ERROR: Singleton is null, cannot emit signal");
		}
	}
}

- (void)requestAttributionDataWithToken:(NSString *)token {
	if (!token || token.length == 0) {
		NSLog(@"[Godot3ASA] Invalid token");
		Godot3ASA *singleton = Godot3ASA::get_singleton();
		if (singleton) {
			singleton->emit_signal(
				"onASAAttributionReceived",
				"",
				400,
				"Invalid token"
			);
		} else {
			NSLog(@"[Godot3ASA] ERROR: Singleton is null, cannot emit signal");
		}
		return;
	}
	
	// 延迟执行以符合最佳实践（500-1000ms等待）
	dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.5 * NSEC_PER_SEC)), dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
		// 构建请求
		NSURL *url = [NSURL URLWithString:@"https://api-adservices.apple.com/api/v1/"];
		NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:url];
		[request setHTTPMethod:@"POST"];
		[request setValue:@"text/plain" forHTTPHeaderField:@"Content-Type"];
		[request setHTTPBody:[token dataUsingEncoding:NSUTF8StringEncoding]];
		[request setTimeoutInterval:5.0]; // 5秒超时
		
		NSLog(@"[Godot3ASA] Requesting attribution data...");
		
		// 发起请求
		NSURLSessionDataTask *task = [[NSURLSession sharedSession] dataTaskWithRequest:request
			completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
				
			NSHTTPURLResponse *httpResponse = (NSHTTPURLResponse *)response;
			int statusCode = (int)[httpResponse statusCode];
			
			if (error != nil) {
				// 网络错误
				NSLog(@"[Godot3ASA] Network error: %@", [error localizedDescription]);
				dispatch_async(dispatch_get_main_queue(), ^{
					Godot3ASA *singleton = Godot3ASA::get_singleton();
					if (singleton) {
						singleton->emit_signal(
							"onASAAttributionReceived",
							"",
							-1,
							String::utf8([[error localizedDescription] UTF8String])
						);
					} else {
						NSLog(@"[Godot3ASA] ERROR: Singleton is null, cannot emit signal");
					}
				});
				return;
			}
			
			if (statusCode == 200) {
				// 成功获取归因数据
				if (data && data.length > 0) {
					NSString *jsonString = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
					NSLog(@"[Godot3ASA] Attribution data received: %@", jsonString);
					
					dispatch_async(dispatch_get_main_queue(), ^{
						Godot3ASA *singleton = Godot3ASA::get_singleton();
						if (singleton) {
							singleton->emit_signal(
								"onASAAttributionReceived",
								String::utf8([jsonString UTF8String]),
								200,
								""
							);
						} else {
							NSLog(@"[Godot3ASA] ERROR: Singleton is null, cannot emit signal");
						}
					});
				} else {
					NSLog(@"[Godot3ASA] Empty response data");
					dispatch_async(dispatch_get_main_queue(), ^{
						Godot3ASA *singleton = Godot3ASA::get_singleton();
						if (singleton) {
							singleton->emit_signal(
								"onASAAttributionReceived",
								"",
								200,
								"Empty response"
							);
						} else {
							NSLog(@"[Godot3ASA] ERROR: Singleton is null, cannot emit signal");
						}
					});
				}
			} else {
				// HTTP错误
				NSString *errorMsg = [NSString stringWithFormat:@"HTTP %d", statusCode];
				NSLog(@"[Godot3ASA] HTTP error: %@", errorMsg);
				
				dispatch_async(dispatch_get_main_queue(), ^{
					Godot3ASA *singleton = Godot3ASA::get_singleton();
					if (singleton) {
						singleton->emit_signal(
							"onASAAttributionReceived",
							"",
							statusCode,
							String::utf8([errorMsg UTF8String])
						);
					} else {
						NSLog(@"[Godot3ASA] ERROR: Singleton is null, cannot emit signal");
					}
				});
			}
		}];
		
		[task resume];
	});
}

- (void)performFullAttribution {
	if (@available(iOS 14.3, *)) {
		// 先获取token
		dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.5 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
			NSError *error = nil;
			NSString *token = [AAAttribution attributionTokenWithError:&error];
			
			if (error != nil) {
				int errorCode = (int)[error code];
				NSString *errorMessage = [error localizedDescription];
				NSLog(@"[Godot3ASA] Full attribution failed at token stage: %@", errorMessage);
				
				Godot3ASA *singleton = Godot3ASA::get_singleton();
				if (singleton) {
					singleton->emit_signal(
						"onASAAttributionReceived",
						"",
						errorCode,
						String::utf8([errorMessage UTF8String])
					);
				} else {
					NSLog(@"[Godot3ASA] ERROR: Singleton is null, cannot emit signal");
				}
				return;
			}
			
			if (!token || token.length == 0) {
				NSLog(@"[Godot3ASA] Full attribution failed: empty token");
				Godot3ASA *singleton = Godot3ASA::get_singleton();
				if (singleton) {
					singleton->emit_signal(
						"onASAAttributionReceived",
						"",
						-1,
						"Empty token"
					);
				} else {
					NSLog(@"[Godot3ASA] ERROR: Singleton is null, cannot emit signal");
				}
				return;
			}
			
			// 获取token成功，继续请求归因数据
			[self requestAttributionDataWithToken:token];
		});
	} else {
		NSLog(@"[Godot3ASA] Full attribution not supported on this iOS version");
		Godot3ASA *singleton = Godot3ASA::get_singleton();
		if (singleton) {
			singleton->emit_signal(
				"onASAAttributionReceived",
				"",
				-2,
				"AdServices not supported (iOS 14.3+ required)"
			);
		} else {
			NSLog(@"[Godot3ASA] ERROR: Singleton is null, cannot emit signal");
		}
	}
}

- (NSString *)getDeviceModel {
	// 获取设备型号（iPhone、iPad等）
	NSString *model = [[UIDevice currentDevice] model];
	NSLog(@"[Godot3ASA] Device model: %@", model);
	return model;
}

- (NSString *)getSystemVersion {
	// 获取系统版本号（如16.3）
	NSString *version = [[UIDevice currentDevice] systemVersion];
	NSLog(@"[Godot3ASA] System version: %@", version);
	return version;
}

@end

// MARK: - Static Delegate Instance
static GodotASADelegate *asa_delegate = nil;

// MARK: - C++ Singleton Implementation

Godot3ASA *Godot3ASA::instance = NULL;

Godot3ASA *Godot3ASA::get_singleton() {
	return instance;
}

void Godot3ASA::_bind_methods() {
	ClassDB::bind_method(D_METHOD("requestAttributionToken"), &Godot3ASA::requestAttributionToken);
	ClassDB::bind_method(D_METHOD("requestAttributionData", "token"), &Godot3ASA::requestAttributionData);
	ClassDB::bind_method(D_METHOD("performAttribution"), &Godot3ASA::performAttribution);
	ClassDB::bind_method(D_METHOD("isSupported"), &Godot3ASA::isSupported);
	ClassDB::bind_method(D_METHOD("getDeviceModel"), &Godot3ASA::getDeviceModel);
	ClassDB::bind_method(D_METHOD("getSystemVersion"), &Godot3ASA::getSystemVersion);

	// 信号定义
	ADD_SIGNAL(MethodInfo("onASATokenReceived",
		PropertyInfo(Variant::STRING, "token"),
		PropertyInfo(Variant::INT, "error_code"),
		PropertyInfo(Variant::STRING, "error_message")
	));
	
	ADD_SIGNAL(MethodInfo("onASAAttributionReceived",
		PropertyInfo(Variant::STRING, "attribution_data"),
		PropertyInfo(Variant::INT, "error_code"),
		PropertyInfo(Variant::STRING, "error_message")
	));
}

void Godot3ASA::requestAttributionToken() {
	if (!asa_delegate) {
		asa_delegate = [[GodotASADelegate alloc] init];
	}
	[asa_delegate requestAttributionToken];
}

void Godot3ASA::requestAttributionData(const String &token) {
	if (!asa_delegate) {
		asa_delegate = [[GodotASADelegate alloc] init];
	}
	NSString *nsToken = [NSString stringWithUTF8String:token.utf8().get_data()];
	[asa_delegate requestAttributionDataWithToken:nsToken];
}

void Godot3ASA::performAttribution() {
	if (!asa_delegate) {
		asa_delegate = [[GodotASADelegate alloc] init];
	}
	[asa_delegate performFullAttribution];
}

bool Godot3ASA::isSupported() {
	if (!asa_delegate) {
		asa_delegate = [[GodotASADelegate alloc] init];
	}
	return [asa_delegate isAdServicesSupported];
}

String Godot3ASA::getDeviceModel() {
	if (!asa_delegate) {
		asa_delegate = [[GodotASADelegate alloc] init];
	}
	NSString *model = [asa_delegate getDeviceModel];
	return String::utf8([model UTF8String]);
}

String Godot3ASA::getSystemVersion() {
	if (!asa_delegate) {
		asa_delegate = [[GodotASADelegate alloc] init];
	}
	NSString *version = [asa_delegate getSystemVersion];
	return String::utf8([version UTF8String]);
}

Godot3ASA::Godot3ASA() {
	ERR_FAIL_COND(instance != NULL);
	instance = this;
	
	if (!asa_delegate) {
		asa_delegate = [[GodotASADelegate alloc] init];
	}
	
	NSLog(@"[Godot3ASA] Godot3ASA plugin initialized");
}

Godot3ASA::~Godot3ASA() {
	instance = NULL;
	
	if (asa_delegate) {
		asa_delegate = nil;
	}
}
