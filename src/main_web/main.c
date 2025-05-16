#include <emscripten/emscripten.h>

extern void load_save();

EMSCRIPTEN_KEEPALIVE void load() {
    load_save();
}

void mount_idbfs() {
    EM_ASM({
            console.log("mounting idbfs");
            if (typeof FS === 'undefined' || typeof IDBFS === 'undefined') {
                console.error("FS or IDBFS is not available");
                return;
            }
            FS.mkdir('/persist');
            FS.mount(IDBFS, {autoPersist: true}, '/persist');
            FS.syncfs(true, function(err) {
                    if (err) {
                        console.error("error syncing", err);
                    } else {
                        console.log("fs sync to great succ.");
                        _load();
                    }
                });
    });
}

