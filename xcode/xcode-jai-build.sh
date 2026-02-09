#!/usr/bin/env bash

#
# Build script run by Xcode's "external build system" to compile our Jai executables.
#
# Note that we use PRODUCT_NAME, which is the name of the target, to assume the Jai file name.
#

# Set strict variable mode, fail on any error
set -euo pipefail

# Assume the Jai compiler lives in ~/jai if not specified via $JAI_COMPILER
JAI_COMPILER=${JAI_COMPILER:-~/jai/bin/jai-macos}


EXAMPLES_DIR=$(realpath "$SRCROOT/../examples")
LOCAL_MODULES_DIR=$(realpath "$SRCROOT/../modules")

if [ ! -d "$EXAMPLES_DIR" ]; then
    echo "Error: Examples directory not found at $EXAMPLES_DIR"
    exit 1
fi

if [ ! -d "$LOCAL_MODULES_DIR" ]; then
    echo "Error: Local modules directory not found at $LOCAL_MODULES_DIR"
    exit 1
fi

if [ "$PRODUCT_NAME" == "jai_window" ]; then
    EXAMPLES_DIR=$(realpath "$SRCROOT/../modules/Metal/examples")
fi

# Build the executable
cd $EXAMPLES_DIR
$JAI_COMPILER -import_dir $LOCAL_MODULES_DIR -very_debug -quiet $PRODUCT_NAME.jai
