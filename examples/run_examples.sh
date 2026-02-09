cd examples

# Set library path for slang
export DYLD_LIBRARY_PATH="../modules/slang/mac:${DYLD_LIBRARY_PATH}"

jai -quiet build.jai - -run_tests

# run metal + sdl example
# cd ../modules/Metal/examples && jai -quiet sdl_metal.jai +Autorun -singleframe || exit 1
