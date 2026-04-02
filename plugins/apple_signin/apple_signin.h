#ifndef APPLE_SIGN_IN_H
#define APPLE_SIGN_IN_H

#include "core/version.h"

#if VERSION_MAJOR == 4
#include "core/object/class_db.h"
#else
#include "core/object.h"
#endif

class AppleSignIn : public Object {

	GDCLASS(AppleSignIn, Object);

	static AppleSignIn *instance;
	static void _bind_methods();

	List<Variant> pending_events;

public:
	// Initiate Sign In with Apple.
	// request_email: request the user's email address scope
	// request_name:  request the user's full name scope
	// Note: email and name are only returned on the FIRST sign-in; subsequent calls return empty strings.
	Error sign_in(bool request_email, bool request_name);

	// Asynchronously check whether a previously-obtained user identifier is still valid.
	// Result posted as a "credential_state" event.
	void check_credential_state(String user_id);

	void _post_event(Variant p_event);

	int get_pending_event_count();
	Variant pop_pending_event();

	static AppleSignIn *get_singleton();

	AppleSignIn();
	~AppleSignIn();
};

#endif // APPLE_SIGN_IN_H
