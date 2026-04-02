#include "apple_signin_module.h"

#include "core/version.h"

#if VERSION_MAJOR == 4
#include "core/config/engine.h"
#else
#include "core/engine.h"
#endif

#include "apple_signin.h"

AppleSignIn *apple_signin;

void register_apple_signin_types() {
	apple_signin = memnew(AppleSignIn);
	Engine::get_singleton()->add_singleton(
	    Engine::Singleton("AppleSignIn", apple_signin));
}

void unregister_apple_signin_types() {
	if (apple_signin) {
		memdelete(apple_signin);
	}
}
