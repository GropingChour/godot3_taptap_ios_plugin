#!/bin/bash
set -e

PLUGIN="apple_signin"

# Build release and release_debug (used as "debug") XCFrameworks
./scripts/generate_xcframework.sh $PLUGIN release $1
./scripts/generate_xcframework.sh $PLUGIN release_debug $1
mv ./bin/${PLUGIN}.release_debug.xcframework ./bin/${PLUGIN}.debug.xcframework

# Ensure release output folder exists
if [ ! -d "./bin/release" ]; then
    mkdir ./bin/release
fi

# Move artefacts to release folder
if [ -d "./bin/release/${PLUGIN}" ]; then
    rm -rf ./bin/release/${PLUGIN}
fi
mkdir ./bin/release/${PLUGIN}
mv ./bin/${PLUGIN}.{release,debug}.xcframework ./bin/release/${PLUGIN}
cp ./plugins/${PLUGIN}/${PLUGIN}.gdip ./bin/release/${PLUGIN}

echo "Done. Release artefacts are in ./bin/release/${PLUGIN}/"
