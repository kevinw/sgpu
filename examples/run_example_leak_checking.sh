name="$*"

if [ -z "$name" ]; then
    echo "Usage: $0 <name>"
    exit 1
fi

# some mac-specific extra Metal debug environment variables
if [ "$(uname)" = "Darwin" ]; then
    # export MallocStackLogging=1
    # export MallocStackLoggingNoCompact=1
    # export NSZombieEnabled=YES
    # export NSAutoreleaseFreedObjectCheckEnabled=YES
    # export OBJC_DEBUG_MISSING_POOLS=YES
    # export OBJC_DEBUG_POOL_DEPTH=10

    export METAL_DEVICE_WRAPPER_TYPE=1
    export MTL_LOG_TO_STDERR=1
    export MTL_DEBUG_LAYER=1
    export MTL_LOG_LEVEL=MTLLogLevelDebug
    export MTL_LOG_BUFFER_SIZE=2048

    jai -quiet build.jai - $name && cd bin && leaks --quiet --atExit -- ./$name
else
    jai -quiet build.jai - $name && cd bin && ./name
fi
