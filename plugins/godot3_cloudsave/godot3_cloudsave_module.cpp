
#include "godot3_cloudsave_module.h"
#include "godot3_cloudsave.h"
#include "core/engine.h"

Godot3CloudSave *godot3_cloudsave;

void register_godot3_cloudsave_types() {
    godot3_cloudsave = memnew(Godot3CloudSave);
    Engine::get_singleton()->add_singleton(Engine::Singleton("Godot3CloudSave", godot3_cloudsave));
}

void unregister_godot3_cloudsave_types() {
    if (godot3_cloudsave) {
        memdelete(godot3_cloudsave);
    }
}
