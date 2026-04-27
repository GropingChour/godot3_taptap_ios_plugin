#include "apple_signin.h"

#import <AuthenticationServices/AuthenticationServices.h>

#if VERSION_MAJOR == 4
#import "platform/ios/app_delegate.h"
#else
#import "platform/iphone/app_delegate.h"
#endif

#if VERSION_MAJOR == 4
typedef PackedStringArray GodotStringArray;
#else
typedef PoolStringArray GodotStringArray;
#endif

// ---------------------------------------------------------------------------
// Objective-C delegate — requires iOS 13+
// ---------------------------------------------------------------------------

API_AVAILABLE(ios(13.0))
@interface GodotAppleSignInDelegate : NSObject <ASAuthorizationControllerDelegate,
                                                ASAuthorizationControllerPresentationContextProviding>
@end

API_AVAILABLE(ios(13.0))
@implementation GodotAppleSignInDelegate

// MARK: - ASAuthorizationControllerPresentationContextProviding

- (ASPresentationAnchor)presentationAnchorForAuthorizationController:(ASAuthorizationController *)controller {
	// Return the app's key window as the presentation anchor (no UIViewController needed).
	return [UIApplication sharedApplication].delegate.window;
}

// MARK: - ASAuthorizationControllerDelegate  (success)

- (void)authorizationController:(ASAuthorizationController *)controller
	   didCompleteWithAuthorization:(ASAuthorization *)authorization {

	Dictionary ret;
	ret["type"] = "sign_in";

	if ([authorization.credential isKindOfClass:[ASAuthorizationAppleIDCredential class]]) {
		ASAuthorizationAppleIDCredential *credential =
		    (ASAuthorizationAppleIDCredential *)authorization.credential;

		ret["result"] = "ok";

		// Stable, opaque user identifier — persist this for future credential-state checks.
		const char *user_str = [credential.user UTF8String];
		ret["user"] = user_str ? user_str : "";

		// Update in-process session state.
		if (AppleSignIn::get_singleton()) {
			AppleSignIn::get_singleton()->signed_in = true;
			AppleSignIn::get_singleton()->current_user = String::utf8(user_str ? user_str : "");
		}

		// Email — only populated on the very first sign-in; empty string thereafter.
		ret["email"] = credential.email ? [credential.email UTF8String] : "";

		// Full name components — only populated on the very first sign-in.
		if (credential.fullName) {
			NSPersonNameComponents *n = credential.fullName;
			ret["full_name_given"]    = n.givenName   ? [n.givenName   UTF8String] : "";
			ret["full_name_family"]   = n.familyName  ? [n.familyName  UTF8String] : "";
			ret["full_name_middle"]   = n.middleName  ? [n.middleName  UTF8String] : "";
			ret["full_name_nickname"] = n.nickname    ? [n.nickname    UTF8String] : "";
			ret["full_name_prefix"]   = n.namePrefix  ? [n.namePrefix  UTF8String] : "";
			ret["full_name_suffix"]   = n.nameSuffix  ? [n.nameSuffix  UTF8String] : "";
		} else {
			ret["full_name_given"]    = "";
			ret["full_name_family"]   = "";
			ret["full_name_middle"]   = "";
			ret["full_name_nickname"] = "";
			ret["full_name_prefix"]   = "";
			ret["full_name_suffix"]   = "";
		}

		// JWT identity token — send to your server for verification via Apple's REST API.
		if (credential.identityToken) {
			ret["identity_token"] =
			    [[credential.identityToken base64EncodedStringWithOptions:0] UTF8String];
		} else {
			ret["identity_token"] = "";
		}

		// One-time authorization code — exchange on your server for access/refresh tokens.
		if (credential.authorizationCode) {
			ret["authorization_code"] =
			    [[credential.authorizationCode base64EncodedStringWithOptions:0] UTF8String];
		} else {
			ret["authorization_code"] = "";
		}

		// Real-user indicator: 0 = unsupported, 1 = unknown, 2 = likely real person.
		ret["real_user_status"] = (int64_t)credential.realUserStatus;

		// Optional nonce / state string echoed back from the request.
		ret["state"] = credential.state ? [credential.state UTF8String] : "";

	} else {
		// Unexpected credential type — report as error.
		ret["result"] = "error";
		ret["error_code"] = (int64_t)-1;
		ret["error_description"] = "Unexpected credential type received.";

		if (AppleSignIn::get_singleton()) {
			AppleSignIn::get_singleton()->signed_in = false;
		}
	}

	if (AppleSignIn::get_singleton()) {
		AppleSignIn::get_singleton()->_post_event(ret);
	}
}

// MARK: - ASAuthorizationControllerDelegate  (failure)

- (void)authorizationController:(ASAuthorizationController *)controller
			 didCompleteWithError:(NSError *)error {
	Dictionary ret;
	ret["type"] = "sign_in";

	if (error.code == ASAuthorizationErrorCanceled) {
		ret["result"] = "cancel";
	} else {
		ret["result"] = "error";
		ret["error_code"] = (int64_t)error.code;
		ret["error_description"] = [error.localizedDescription UTF8String];
	}

	// Any non-success outcome clears the in-process session state.
	if (AppleSignIn::get_singleton()) {
		AppleSignIn::get_singleton()->signed_in = false;
		AppleSignIn::get_singleton()->current_user = String();
	}

	if (AppleSignIn::get_singleton()) {
		AppleSignIn::get_singleton()->_post_event(ret);
	}
}

@end

// ---------------------------------------------------------------------------
// C++ singleton
// ---------------------------------------------------------------------------

AppleSignIn *AppleSignIn::instance = NULL;

// Strong reference so the controller lives until the callbacks fire.
static id apple_signin_delegate = nil;
static id auth_controller = nil;

void AppleSignIn::_bind_methods() {
	ClassDB::bind_method(D_METHOD("sign_in", "request_email", "request_name"),
	    &AppleSignIn::sign_in);
	ClassDB::bind_method(D_METHOD("check_credential_state", "user_id"),
	    &AppleSignIn::check_credential_state);
	ClassDB::bind_method(D_METHOD("is_signed_in"),
	    &AppleSignIn::is_signed_in);
	ClassDB::bind_method(D_METHOD("get_current_user"),
	    &AppleSignIn::get_current_user);
	ClassDB::bind_method(D_METHOD("get_pending_event_count"),
	    &AppleSignIn::get_pending_event_count);
	ClassDB::bind_method(D_METHOD("pop_pending_event"),
	    &AppleSignIn::pop_pending_event);
}

Error AppleSignIn::sign_in(bool request_email, bool request_name) {
	if (@available(iOS 13.0, *)) {
		ASAuthorizationAppleIDProvider *provider =
		    [[ASAuthorizationAppleIDProvider alloc] init];
		ASAuthorizationAppleIDRequest *request = [provider createRequest];

		NSMutableArray<ASAuthorizationScope> *scopes = [NSMutableArray array];
		if (request_email) {
			[scopes addObject:ASAuthorizationScopeEmail];
		}
		if (request_name) {
			[scopes addObject:ASAuthorizationScopeFullName];
		}
		request.requestedScopes = scopes;

		ASAuthorizationController *controller =
		    [[ASAuthorizationController alloc]
		        initWithAuthorizationRequests:@[ request ]];
		controller.delegate = apple_signin_delegate;
		controller.presentationContextProvider = apple_signin_delegate;
		auth_controller = controller; // retain strong ref
		[controller performRequests];

		return OK;
	} else {
		Dictionary ret;
		ret["type"] = "sign_in";
		ret["result"] = "error";
		ret["error_code"] = (int64_t)-1;
		ret["error_description"] = "Sign In with Apple requires iOS 13 or later.";
		pending_events.push_back(ret);
		return ERR_UNAVAILABLE;
	}
}

void AppleSignIn::check_credential_state(String user_id) {
	if (@available(iOS 13.0, *)) {
		NSString *uid = [[NSString alloc]
		    initWithUTF8String:user_id.utf8().get_data()];
		ASAuthorizationAppleIDProvider *provider =
		    [[ASAuthorizationAppleIDProvider alloc] init];

		[provider getCredentialStateForUserID:uid
		    completion:^(ASAuthorizationAppleIDProviderCredentialState state,
		                 NSError *error) {
			    Dictionary ret;
			    ret["type"] = "credential_state";
			    ret["user"] = [uid UTF8String];

			    if (error) {
				    ret["result"]            = "error";
				    ret["error_code"]        = (int64_t)error.code;
				    ret["error_description"] = [error.localizedDescription UTF8String];
			    } else {
				    switch (state) {
					    case ASAuthorizationAppleIDProviderCredentialAuthorized:
						    ret["result"] = "authorized";
						    // Confirm signed-in state for this session.
						    if (AppleSignIn::get_singleton()) {
							    AppleSignIn::get_singleton()->signed_in = true;
							    AppleSignIn::get_singleton()->current_user = String::utf8([uid UTF8String]);
						    }
						    break;
					    case ASAuthorizationAppleIDProviderCredentialRevoked:
						    ret["result"] = "revoked";
						    if (AppleSignIn::get_singleton()) {
							    AppleSignIn::get_singleton()->signed_in = false;
							    AppleSignIn::get_singleton()->current_user = String();
						    }
						    break;
					    case ASAuthorizationAppleIDProviderCredentialNotFound:
						    ret["result"] = "not_found";
						    if (AppleSignIn::get_singleton()) {
							    AppleSignIn::get_singleton()->signed_in = false;
							    AppleSignIn::get_singleton()->current_user = String();
						    }
						    break;
					    default:
						    // ASAuthorizationAppleIDProviderCredentialTransferred (iOS 14+)
						    if (@available(iOS 14.0, *)) {
							    if (state == ASAuthorizationAppleIDProviderCredentialTransferred) {
								    ret["result"] = "transferred";
								    break;
							    }
						    }
						    ret["result"] = "unknown";
						    break;
				    }
			    }

			    if (AppleSignIn::get_singleton()) {
				    AppleSignIn::get_singleton()->_post_event(ret);
			    }
		    }];
	} else {
		Dictionary ret;
		ret["type"] = "credential_state";
		ret["user"] = user_id.utf8().get_data();
		ret["result"] = "error";
		ret["error_code"] = (int64_t)-1;
		ret["error_description"] = "Sign In with Apple requires iOS 13 or later.";
		pending_events.push_back(ret);
	}
}

void AppleSignIn::_post_event(Variant p_event) {
	pending_events.push_back(p_event);
}

bool AppleSignIn::is_signed_in() {
	return signed_in;
}

String AppleSignIn::get_current_user() {
	return current_user;
}

int AppleSignIn::get_pending_event_count() {
	return pending_events.size();
}

Variant AppleSignIn::pop_pending_event() {
	Variant front = pending_events.front()->get();
	pending_events.pop_front();
	return front;
}

AppleSignIn *AppleSignIn::get_singleton() {
	return instance;
}

AppleSignIn::AppleSignIn() {
	ERR_FAIL_COND(instance != NULL);
	instance = this;
	signed_in = false;
	current_user = String();

	if (@available(iOS 13.0, *)) {
		apple_signin_delegate = [[GodotAppleSignInDelegate alloc] init];
	}
}

AppleSignIn::~AppleSignIn() {
	apple_signin_delegate = nil;
	auth_controller = nil;
	instance = NULL;
}
