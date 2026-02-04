/*************************************************************************/
/*  godot3_storeview.mm                                                  */
/*************************************************************************/
/*                       This file is part of:                           */
/*                           GODOT ENGINE                                */
/*                      https://godotengine.org                          */
/*************************************************************************/
/* Copyright (c) 2007-2021 Juan Linietsky, Ariel Manzur.                 */
/* Copyright (c) 2014-2021 Godot Engine contributors (cf. AUTHORS.md).   */
/*                                                                       */
/* Permission is hereby granted, free of charge, to any person obtaining */
/* a copy of this software and associated documentation files (the       */
/* "Software"), to deal in the Software without restriction, including   */
/* without limitation the rights to use, copy, modify, merge, publish,   */
/* distribute, sublicense, and/or sell copies of the Software, and to    */
/* permit persons to whom the Software is furnished to do so, subject to */
/* the following conditions:                                             */
/*                                                                       */
/* The above copyright notice and this permission notice shall be        */
/* included in all copies or substantial portions of the Software.       */
/*                                                                       */
/* THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND,       */
/* EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF    */
/* MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT.*/
/* IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY  */
/* CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT,  */
/* TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE     */
/* SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.                */
/*************************************************************************/

#include "godot3_storeview.h"

#import <Foundation/Foundation.h>
#import <StoreKit/StoreKit.h>
#import <UIKit/UIKit.h>

Godot3StoreView *Godot3StoreView::instance = NULL;

Godot3StoreView *Godot3StoreView::get_singleton() {
	return instance;
}

void Godot3StoreView::request_review() {
	// Check if the API is available (iOS 10.3+)
	if (@available(iOS 10.3, *)) {
		// SKStoreReviewController.requestReview() should be called on the main thread
		dispatch_async(dispatch_get_main_queue(), ^{
#if defined(__IPHONE_14_0) && __IPHONE_OS_VERSION_MAX_ALLOWED >= __IPHONE_14_0
			// iOS 14+ - Use new scene-based API if available
			if (@available(iOS 14.0, *)) {
				UIWindowScene *windowScene = nil;
				
				// Get the active window scene
				for (UIScene *scene in [UIApplication sharedApplication].connectedScenes) {
					if ([scene isKindOfClass:[UIWindowScene class]] && 
					    scene.activationState == UISceneActivationStateForegroundActive) {
						windowScene = (UIWindowScene *)scene;
						break;
					}
				}
				
				if (windowScene) {
					[SKStoreReviewController requestReviewInScene:windowScene];
				} else {
					NSLog(@"[Godot3StoreView] No active window scene found");
				}
			} else {
				// iOS 10.3-13.x - Use legacy API
				[SKStoreReviewController requestReview];
			}
#else
			// iOS 10.3-13.x - Use legacy API
			[SKStoreReviewController requestReview];
#endif
		});
	} else {
		NSLog(@"[Godot3StoreView] SKStoreReviewController is not available on this iOS version");
	}
}

String Godot3StoreView::get_write_review_url(const String &app_store_id) {
	if (app_store_id.empty()) {
		NSLog(@"[Godot3StoreView] App Store ID is empty");
		return "";
	}
	
	String url = "https://apps.apple.com/app/id" + app_store_id + "?action=write-review";
	return url;
}

void Godot3StoreView::_bind_methods() {
	ClassDB::bind_method(D_METHOD("request_review"), &Godot3StoreView::request_review);
	ClassDB::bind_method(D_METHOD("get_write_review_url", "app_store_id"), &Godot3StoreView::get_write_review_url);
}

Godot3StoreView::Godot3StoreView() {
	ERR_FAIL_COND(instance != NULL);
	instance = this;
}

Godot3StoreView::~Godot3StoreView() {
	if (instance == this) {
		instance = NULL;
	}
}
