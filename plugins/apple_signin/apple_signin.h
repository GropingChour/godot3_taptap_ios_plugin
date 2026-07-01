#ifndef APPLE_SIGN_IN_H
#define APPLE_SIGN_IN_H

#include "core/version.h"

#if VERSION_MAJOR == 4
#include "core/object/class_db.h"
#else
#include "core/object.h"
#endif

#include <mutex>

class AppleSignIn : public Object {

	GDCLASS(AppleSignIn, Object);

	static AppleSignIn *instance;
	static void _bind_methods();

	static std::mutex pending_events_mutex;
	List<Variant> pending_events;

	// In-memory session state — updated when sign_in succeeds/fails and when
	// check_credential_state returns.  Reset to false on destruction.
	bool signed_in;
	String current_user;

public:
	// Initiate Sign In with Apple.
	// request_email: request the user's email address scope
	// request_name:  request the user's full name scope
	// Note: email and name are only returned on the FIRST sign-in; subsequent calls return empty strings.
	Error sign_in(bool request_email, bool request_name);

	// Asynchronously check whether a previously-obtained user identifier is still valid.
	// Result posted as a "credential_state" event; also updates signed_in state.
	void check_credential_state(String user_id);

	// Synchronous in-process sign-in state.  Reflects the result of the most recent
	// sign_in() call or check_credential_state() call in this app session.
	// NOTE: This is NOT persistent across app restarts.  Always call
	// check_credential_state() at launch to re-establish the authoritative state.
	bool is_signed_in();

	// Returns the user identifier from the most recent successful sign-in or
	// authorized credential-state check, or an empty String if not signed in.
	String get_current_user();

	void _post_event(Variant p_event);

	int get_pending_event_count();
	Variant pop_pending_event();

	static AppleSignIn *get_singleton();

	AppleSignIn();
	~AppleSignIn();
};

#endif // APPLE_SIGN_IN_H
