// These procs are the ones that will be called from `index.html`, which is
// generated from `index_template.html`.

package main_web

import "base:runtime"
import "core:c"
import "core:mem"
import "core:time"
import "core:strings"
import "core:fmt"
import game ".."

@(private="file")
web_context: runtime.Context

@(default_calling_convention = "c")
foreign {
	mount_idbfs  :: proc() ---
}

onopen :: proc "c" (eventType: c.int, #by_ptr websocketEvent: EmscriptenWebSocketOpenEvent, userData: rawptr ) -> c.bool {
    context = runtime.default_context()
    ws := cast(^EMSCRIPTEN_WEBSOCKET_T)(userData)
    fmt.println("open")
    emscripten_websocket_send_utf8_text(ws^, "teeest")
    emscripten_websocket_send_utf8_text(ws^, "echoecho")
    fmt.println("sent")
    socket_ready = true
    return true
}
onerror :: proc "c" (eventType: c.int, #by_ptr websocketEvent: EmscriptenWebSocketOpenEvent, userData: rawptr ) -> c.bool {
    context = runtime.default_context()
    fmt.println("error")
    return true
}
onclose :: proc "c" (eventType: c.int, #by_ptr websocketEvent: EmscriptenWebSocketOpenEvent, userData: rawptr ) -> c.bool {
    context = runtime.default_context()
    fmt.println("close")
    return true
}
onmessage :: proc "c" (eventType: c.int, #by_ptr websocketEvent: EmscriptenWebSocketMessageEvent, userData: rawptr ) -> c.bool {
    context = runtime.default_context()
    fmt.println("recieving message, which text == ", websocketEvent.isText)
    if websocketEvent.isText {
        fmt.println(string(websocketEvent.data[:websocketEvent.numBytes]))
    } else {
        decode_and_receive(websocketEvent.data, uint(websocketEvent.numBytes), doc, syncState)
        update_game_state_from_doc(doc)
    }
    return true
}

ws : EMSCRIPTEN_WEBSOCKET_T
doc: AMdocPtr
syncState: AMsyncStatePtr
socket_ready: bool = false

update_doc_from_game_state :: proc(doc: AMdocPtr) {
    token_list_result := AMmapPutObject(doc, AM_ROOT, AMstr("tokens"), .AM_OBJ_TYPE_LIST)
    if (AMresultStatus(token_list_result) != AMstatus.AM_STATUS_OK) {
        fmt.println("error encountered token_list_result")
    }
    token_list := AMitemObjId(AMresultItem(token_list_result))
    fmt.println("actual tokens size when converting to doc: ", len(game.state.tokens))
    for _, &token in game.state.tokens {
        // Insert a map into the list for each token
        token_map_result := AMlistPutObject(doc, token_list, c.SIZE_MAX, true, .AM_OBJ_TYPE_MAP)
        fmt.println("putting token of id: ", token.id, "with pos: ", token.position)
        if (AMresultStatus(token_map_result) != AMstatus.AM_STATUS_OK) {
            fmt.println("error encountered token_map_result")
        }
        token_map := AMitemObjId(AMresultItem(token_map_result))

        id_result := AMmapPutUint(doc, token_map, AMstr("id"), token.id)
        if (AMresultStatus(id_result) != AMstatus.AM_STATUS_OK) {
            fmt.println("error encountered id_result")
        }
        name_result := AMmapPutStr(doc, token_map, AMstr("name"), AMstr(strings.clone_to_cstring(token.name)))
        if (AMresultStatus(name_result) != AMstatus.AM_STATUS_OK) {
            fmt.println("error encountered name_result")
        }
        initiative_result := AMmapPutInt(doc, token_map, AMstr("initiative"), i64(token.initiative))
        if (AMresultStatus(initiative_result) != AMstatus.AM_STATUS_OK) {
            fmt.println("error encountered initiative_result")
        }
        size_result := AMmapPutInt(doc, token_map, AMstr("size"), i64(token.size))
        if (AMresultStatus(size_result) != AMstatus.AM_STATUS_OK) {
            fmt.println("error encountered size_result")
        }

        x_result := AMmapPutUint(doc, token_map, AMstr("x"), u64(token.position.abs_tile.x))
        if (AMresultStatus(x_result) != AMstatus.AM_STATUS_OK) {
            fmt.println("error encountered x_result")
        }
        y_result := AMmapPutUint(doc, token_map, AMstr("y"), u64(token.position.abs_tile.y))
        if (AMresultStatus(y_result) != AMstatus.AM_STATUS_OK) {
            fmt.println("error encountered y_result")
        }
    }
}

update_game_state_from_doc :: proc(doc: AMdocPtr) {
    token_listResult: AMresultPtr = AMmapGet(doc, AM_ROOT, AMstr("tokens"), c.NULL)
    //defer AMresultFree(getResult)
    if (AMresultStatus(token_listResult) != AMstatus.AM_STATUS_OK) {
        fmt.println("error encountered token_listResult")
    }
    token_list := AMitemObjId(AMresultItem(token_listResult))
    token_list_count := AMobjSize(doc, token_list, c.NULL)

    for i: uint= 0; i < token_list_count; i+=1 {
        token_result := AMlistGet(doc, token_list, i, c.NULL)
        if (AMresultStatus(token_result) != AMstatus.AM_STATUS_OK) {
            fmt.println("error encountered token_result")
        }
        token_map := AMitemObjId(AMresultItem(token_result))

        id_result := AMmapGet(doc, token_map, AMstr("id"), c.NULL)
        id: u64
        if (AMitemToUint(AMresultItem(id_result), &id)) {
            fmt.println("read token id from automerge doc: ", id)
        } else {
            fmt.println("failed to convert to u64 (id)")
        }

        x_result := AMmapGet(doc, token_map, AMstr("x"), c.NULL)
        x: u64
        if (AMitemToUint(AMresultItem(x_result), &x)) {
            //fmt.println("read token id from automerge doc: ", id)
        } else {
            fmt.println("failed to convert to u64 (x)")
        }
        y_result := AMmapGet(doc, token_map, AMstr("y"), c.NULL)
        y: u64
        if (AMitemToUint(AMresultItem(y_result), &y)) {
            //fmt.println("read token id from automerge doc: ", id)
        } else {
            fmt.println("failed to convert to u64 (y)")
        }
        token_pos: game.TileMapPosition
        token_pos.abs_tile.x = u32(x)
        token_pos.abs_tile.y = u32(y)

        name_result := AMmapGet(doc, token_map, AMstr("name"), c.NULL)
        if (AMresultStatus(name_result) != AMstatus.AM_STATUS_OK) {
            fmt.println("error encountered name_result")
        }
	got: AMbyteSpan
        name: string
	if (AMitemToStr(AMresultItem(name_result), &got)) {
            name = string(got.src[:got.count])
            fmt.println("read token name from automerge doc: ", name)
	} else {
            fmt.println("expected to read a string")
	}

        size_result := AMmapGet(doc, token_map, AMstr("size"), c.NULL)
        size: i64
        if (AMitemToInt(AMresultItem(size_result), &size)) {
            //fmt.println("read token id from automerge doc: ", id)
        } else {
            fmt.println("failed to convert to u64 (size)")
        }
        initiative_result := AMmapGet(doc, token_map, AMstr("initiative"), c.NULL)
        initiative: i64
        if (AMitemToInt(AMresultItem(initiative_result), &initiative)) {
            //fmt.println("read token id from automerge doc: ", id)
        } else {
            fmt.println("failed to convert to u64 (initiative)")
        }

        new_token: game.Token
        new_token.id = id
        new_token.name = name
        new_token.position = token_pos
        new_token.size = i32(size)
        new_token.initiative = i32(initiative)
        game.state.tokens[id] = new_token
    }


}

@export
main_start :: proc "c" (mobile: bool) {
	context = runtime.default_context()
	// The WASM allocator doesn't seem to work properly in combination with
	// emscripten. There is some kind of conflict with how the manage memory.
	// So this sets up an allocator that uses emscripten's malloc.
	context.allocator = emscripten_allocator()
	runtime.init_global_temporary_allocator(1*mem.Megabyte)

	// Since we now use js_wasm32 we should be able to remove this and use
	// context.logger = log.create_console_logger(). However, that one produces
	// extra newlines on web. So it's a bug in that core lib.
	context.logger = create_emscripten_logger()

	web_context = context

        {
            fmt.println("Setting up automerge doc and sync_state")
            docResult := AMcreate(nil)
            //defer AMresultFree(docResult)
            if (AMresultStatus(docResult) != AMstatus.AM_STATUS_OK) {
                fmt.println("error encountered docResult")
            }
            AMitemToDoc(AMresultItem(docResult), &doc)

            syncStateResult := AMsyncStateInit()
            //defer AMresultFree(syncStateResult)
            if (AMresultStatus(syncStateResult) != AMstatus.AM_STATUS_OK) {
                fmt.println("error encountered syncStateResult")
            }
            AMitemToSyncState(AMresultItem(syncStateResult), &syncState)
        }

        { // add basic testint value to doc
            now := time.now()
            buf: [8]u8
            time_s := time.to_string_hms(now, buf[:])
            fmt.println(time_s)


            putResult: AMresultPtr = AMmapPutStr(doc, AM_ROOT, AMstr("key"), AMstr(strings.clone_to_cstring(time_s)))
            //defer AMresultFree(putResult)
            if (AMresultStatus(putResult) != AMstatus.AM_STATUS_OK) {
                fmt.println("error encountered putResult")
            }
        }

        fmt.println("Setting up websocket")
        if (emscripten_websocket_is_supported() == 1) {
            attrs := EmscriptenWebSocketCreateAttributes{ "http://localhost:9010", nil, true }
            ws = emscripten_websocket_new(&attrs)
            fmt.println("ws: ", ws)
            emscripten_websocket_set_onopen_callback_on_thread(ws, &ws, onopen, EM_CALLBACK_THREAD_CONTEXT_CALLING_THREAD)
            emscripten_websocket_set_onclose_callback_on_thread(ws, nil, onclose, EM_CALLBACK_THREAD_CONTEXT_CALLING_THREAD)
            emscripten_websocket_set_onmessage_callback_on_thread(ws, nil, onmessage, EM_CALLBACK_THREAD_CONTEXT_CALLING_THREAD)
            emscripten_websocket_set_onerror_callback_on_thread(ws, nil, onerror, EM_CALLBACK_THREAD_CONTEXT_CALLING_THREAD)
        }

        mount_idbfs()
	game.init(mobile)
}

@export
main_update :: proc "c" () -> bool {
	context = web_context
	game.update()
        if game.state.needs_sync {
            update_doc_from_game_state(doc)
            if socket_ready {
                finished : bool = false
                msg_bytes : AMbyteSpan
                for !finished {
                    msg_bytes, finished = generate_and_encode(doc, syncState)
                    if msg_bytes.count == 0 {
                        finished = true
                    } else {
                        emscripten_websocket_send_binary(ws, msg_bytes.src, u32(msg_bytes.count))
                    }
                }
                game.state.needs_sync = false
            }
        }

	return game.should_run()
}

@export
main_end :: proc "c" () {
	context = web_context
	game.shutdown()
}

@export
web_window_size_changed :: proc "c" (w: c.int, h: c.int) {
	context = web_context
	game.parent_window_size_changed(int(w), int(h))
}

@export
load_save :: proc "c" () {
	context = web_context
        game.load_save()
}

@export
store_save :: proc "c" () {
	context = web_context
        game.store_save()
}
