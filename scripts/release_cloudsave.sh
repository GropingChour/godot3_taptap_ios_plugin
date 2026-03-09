#!/bin/bash
set -e

if [[ "$1" == "3.x" ]];
then
    GODOT_PLUGINS="godot3_cloudsave"
else
    GODOT_PLUGINS="godot3_cloudsave"
fi

# Compile Plugin
for lib in $GODOT_PLUGINS; do
    ./scripts/generate_xcframework.sh $lib release $1
    ./scripts/generate_xcframework.sh $lib release_debug $1
    mv ./bin/${lib}.release_debug.xcframework ./bin/${lib}.debug.xcframework
done

# Ensure release folder exists
if [ ! -d "./bin/release" ]; then
    mkdir ./bin/release
fi

# Move Plugin
for lib in $GODOT_PLUGINS; do
    if [ -d "./bin/release/${lib}" ]; then
        rm -rf ./bin/release/${lib}
    fi
    mkdir ./bin/release/${lib}
    mv ./bin/${lib}.{release,debug}.xcframework ./bin/release/${lib}
    cp ./plugins/${lib}/${lib}.gdip ./bin/release/${lib}
done
