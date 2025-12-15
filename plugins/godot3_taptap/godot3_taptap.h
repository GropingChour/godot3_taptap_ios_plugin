/*************************************************************************/
/*  taptap_login.h                                                       */
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

#ifndef GODOT3_TAPTAP_H
#define GODOT3_TAPTAP_H

#include "core/version.h"

#if VERSION_MAJOR == 4
#include "core/object/class_db.h"
#else
#include "core/object.h"
#endif

class Godot3TapTap : public Object {

	GDCLASS(Godot3TapTap, Object);

	static Godot3TapTap *instance;
	static void _bind_methods();

	List<Variant> pending_events;

	String client_id;
	String client_token;
	bool sdk_initialized;

	void add_pending_event(const String &type, const String &result, const Dictionary &data = Dictionary());

public:
	void _post_event(Variant p_event);

	// SDK Initialization
	void initSdk(const String &p_client_id, const String &p_client_token, bool p_enable_log, bool p_with_iap);
	void initSdkWithEncryptedToken(const String &p_client_id, const String &p_encrypted_token, bool p_enable_log, bool p_with_iap);
	
	// Login
	void login(bool p_use_profile, bool p_use_friends);
	bool isLogin();
	String getUserProfile();
	void logout();
	void logoutThenRestart();
	
	// Compliance (Anti-addiction)
	void compliance();
	
	// License Verification
	void checkLicense(bool p_force_check);
	
	// DLC
	void queryDLC(const Array &p_sku_ids);
	void purchaseDLC(const String &p_sku_id);
	
	// IAP (In-App Purchase)
	void queryProductDetailsAsync(const Array &p_products);
	void launchBillingFlow(const String &p_product_id, const String &p_obfuscated_account_id);
	void finishPurchaseAsync(const String &p_order_id, const String &p_purchase_token);
	void queryUnfinishedPurchaseAsync();
	
	// Utility
	void showTip(const String &p_text);
	void restartApp();

	// Event handling
	int get_pending_event_count();
	Variant pop_pending_event();

	static Godot3TapTap *get_singleton();

	Godot3TapTap();
	~Godot3TapTap();
};

#endif
