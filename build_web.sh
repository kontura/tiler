#!/bin/bash -eu

# Point this to where you installed emscripten. Optional on systems that already
# have `emcc` in the path.
EMSCRIPTEN_SDK_DIR="$HOME/src/emsdk"
OUT_DIR="build/web"

mkdir -p $OUT_DIR

export EMSDK_QUIET=1
[[ -f "$EMSCRIPTEN_SDK_DIR/emsdk_env.sh" ]] && . "$EMSCRIPTEN_SDK_DIR/emsdk_env.sh"

ODIN_BIN=odin

# Note RAYLIB_WASM_LIB=env.o -- env.o is an internal WASM object file. You can
# see how RAYLIB_WASM_LIB is used inside <odin>/vendor/raylib/raylib.odin.
#
# The emcc call will be fed the actual raylib library file. That stuff will end
# up in env.o
#
# Note that there is a rayGUI equivalent: -define:RAYGUI_WASM_LIB=env.o
$ODIN_BIN build src/main_web -target:js_wasm32 -build-mode:obj -define:RAYLIB_WASM_LIB=env.o -define:RAYGUI_WASM_LIB=env.o -strict-style -out:$OUT_DIR/game

ODIN_PATH=$($ODIN_BIN root)

cp $ODIN_PATH/core/sys/wasm/js/odin.js $OUT_DIR

files="$OUT_DIR/game.wasm.o ${ODIN_PATH}/vendor/raylib/wasm/libraylib.a \
       ${ODIN_PATH}/vendor/raylib/wasm/libraygui.a"

# index_template.html contains the javascript code that calls the procedures in
# src/main_web/main_web.odin
flags="-sUSE_GLFW=3 -sFORCE_FILESYSTEM -sWASM_BIGINT -sWARN_ON_UNDEFINED_SYMBOLS=0 -sASSERTIONS \
      --shell-file src/main_web/index_template.html --preload-file assets -lidbfs.js -DPLATFORM_WEB \
      -sEXIT_RUNTIME=1 -lwebsocket.js -sINITIAL_HEAP=64MB \
      -sEXPORTED_FUNCTIONS=_malloc,_free \
      -sEXPORTED_RUNTIME_METHODS=ccall \
      -sDEFAULT_LIBRARY_FUNCS_TO_INCLUDE=send_to_peer_signaling,pass_msg_to_odin \
      --js-library src/main_web/lib.js"

# For debugging: Add `-g` to `emcc` (gives better error callstack in chrome)
emcc -o $OUT_DIR/index.html $files $flags
echo emcc -o $OUT_DIR/index.html $files $flags

rm $OUT_DIR/game.wasm.o

echo "Web build created in ${OUT_DIR}"
