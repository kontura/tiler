// These procs are the ones that will be called from `index.html`, which is
// generated from `index_template.html`.

package main_web

import "base:runtime"
import "core:c"
import "core:mem"
import "core:fmt"
import "core:bytes"
import "core:math/rand"
import "core:strings"
import "core:time"
import game ".."
import am "../automerge"


@(private="file")
web_context: runtime.Context

@(default_calling_convention = "c")
foreign {
	mount_idbfs  :: proc() ---
}

ws: EMSCRIPTEN_WEBSOCKET_T
doc: am.AMdocPtr
doc_result: am.AMresultPtr
socket_ready: bool = false
my_allocator: mem.Allocator
peers: map[string]am.AMsyncStatePtr
my_id: [3]u8

build_binary_message :: proc(target: []u8, payload: []u8) -> []u8{
    msg:= make([dynamic]u8, allocator=context.temp_allocator)
    append(&msg, 1)
    append(&msg, 3)
    append(&msg, my_id[0])
    append(&msg, my_id[1])
    append(&msg, my_id[2])
    append(&msg, u8(len(target)))
    append(&msg, ..target[:])
    append(&msg, ..payload[:])
    return msg[:]
}

parse_binary_message :: proc(msg: []u8) -> (sender, target, payload: []u8) {
    // 0 1 2 3 4 5 6 7 8 9
    // 1 3 a b c 3 d e f x x x
    sender_len := msg[1]
    sender = msg[2:2+sender_len]
    target_len := msg[2+sender_len]
    target = msg[3+sender_len:3 + sender_len + target_len]
    payload = msg[3 + sender_len + target_len:]
    return
}

onopen :: proc "c" (eventType: c.int, #by_ptr websocketEvent: EmscriptenWebSocketOpenEvent, userData: rawptr ) -> c.bool {
    context = runtime.default_context()
    context.allocator = my_allocator
    fmt.println("open")
    register := build_binary_message(nil, nil)
    emscripten_websocket_send_binary(ws, &register[0], u32(len(register)))
    socket_ready = true
    return true
}
onerror :: proc "c" (eventType: c.int, #by_ptr websocketEvent: EmscriptenWebSocketOpenEvent, userData: rawptr ) -> c.bool {
    context = runtime.default_context()
    context.allocator = my_allocator
    fmt.println("error")
    return true
}
onclose :: proc "c" (eventType: c.int, #by_ptr websocketEvent: EmscriptenWebSocketOpenEvent, userData: rawptr ) -> c.bool {
    context = runtime.default_context()
    context.allocator = my_allocator
    fmt.println("close")
    return true
}
onmessage :: proc "c" (eventType: c.int, #by_ptr websocketEvent: EmscriptenWebSocketMessageEvent, userData: rawptr ) -> c.bool {
    using am
    context = runtime.default_context()
    context.allocator = my_allocator
    if websocketEvent.isText {
        assert(false)
    } else {
        sender_bytes, target, payload := parse_binary_message(websocketEvent.data[:websocketEvent.numBytes])
        sender := string(sender_bytes)
        sender_already_registered := sender in peers
        if !sender_already_registered {
            sync_state_result := AMsyncStateInit()
            //TODO(amatej): they will need to be globally managed
            item, _ := result_to_item(sync_state_result)
            peers[strings.clone(sender)] = AMsyncStatePtr{}
            AMitemToSyncState(item, &peers[sender])
        }

        if !bytes.equal(target, my_id[:]) && len(target) != 0 {
            fmt.println("This message is not for me: ", target, " (target) x ", my_id[:], " (me)")
            assert(false)
        }
        if bytes.equal(sender_bytes, my_id[:]) {
            fmt.println("This message is from me: ", target, " (target) x ", my_id[:], " (me)")
            assert(false)
        }
        if len(payload) != 0 {
            decode_and_receive(&payload[0], uint(len(payload)), doc, peers[sender])
            update_game_state_from_doc(doc)
        } else {
            fmt.println("Registering: ", sender)
        }
        game.state.needs_sync = true
    }
    return true
}

update_doc_from_game_state :: proc(doc: am.AMdocPtr) {
    using am

    result := AMmapGet(doc, AM_ROOT, AMstr("max_entity_id"), c.NULL)
    item, _ := result_to_item(result)
    if AMitemValType(item) == .AM_VAL_TYPE_VOID {
        AMresultFree(result)
        // Insert new
        new_result := AMmapPutCounter(doc, AM_ROOT, AMstr("max_entity_id"), i64(game.state.max_entity_id))
        verify_result(new_result)
    } else {
        max: i64
        if !AMitemToCounter(item, &max) {
            fmt.println("Failed to convert from item to max_entity_id counter")
        }
        for max < i64(game.state.max_entity_id) {
            AMmapIncrement(doc, AM_ROOT, AMstr("max_entity_id"), 1)
            max += 1
        }

    }

    update_doc_actions(doc, game.state.undo_history[:])
}

get_or_insert :: proc(doc: am.AMdocPtr, obj_id: am.AMobjIdPtr, key: cstring, type: am.AMobjType) -> am.AMresultPtr {
    using am
    result := AMmapGet(doc, obj_id, AMstr(key), c.NULL)
    item, _ := result_to_item(result)
    if AMitemValType(item) == .AM_VAL_TYPE_VOID {
        AMresultFree(result)
        // Insert new
        new_result := AMmapPutObject(doc, AM_ROOT, AMstr(key), type)
        verify_result(new_result)
        return new_result
    } else {
        return result
    }
}

update_doc_actions :: proc(doc: am.AMdocPtr, actions: []game.Action) -> bool {
    using am
    actions_result := get_or_insert(doc, AM_ROOT, "actions", .AM_OBJ_TYPE_LIST)
    defer AMresultFree(actions_result)
    actions_id := result_to_objid(actions_result) or_return
    doc_actions_list_count := AMobjSize(doc, actions_id, c.NULL)

    for doc_actions_list_count > len(actions) {
        delete_result := AMlistDelete(doc, actions_id, c.SIZE_MAX)
        defer AMresultFree(delete_result)
        doc_actions_list_count -= 1
    }

    for doc_actions_list_count < len(actions) {
        action := actions[doc_actions_list_count]
        put_result := AMlistPutObject(doc, actions_id, c.SIZE_MAX, true, .AM_OBJ_TYPE_MAP)
        defer AMresultFree(put_result)
        action_map := result_to_objid(put_result) or_return

        put_into_map(doc, action_map, "action", &action)

        doc_actions_list_count += 1
    }

    return true
}

get_undo_history_from_doc :: proc(doc: am.AMdocPtr) -> []game.Action {
    using am
    undo_history := make([dynamic]game.Action, allocator=context.temp_allocator)

    undo_history_result: AMresultPtr = AMmapGet(doc, AM_ROOT, AMstr("actions"), c.NULL)
    defer AMresultFree(undo_history_result)
    undo_history_id, _ := result_to_objid(undo_history_result)

    //TODO(amatej): technically I could get only those action I don't already have
    range_result := AMlistRange(doc, undo_history_id, 0, c.SIZE_MAX, c.NULL)
    defer AMresultFree(range_result)
    verify_result(range_result)
    items: AMitems = AMresultItems(range_result)
    action_item : AMitemPtr = AMitemsNext(&items, 1)
    for action_item != c.NULL {
        game_action: game.Action
        action_map := AMitemObjId(action_item)

        game_action = get_from_map(doc, action_map, "action", game.Action)

        append(&undo_history, game_action)

        action_item = AMitemsNext(&items, 1)
    }

    return undo_history[:]
}

update_game_state_from_doc :: proc(doc: am.AMdocPtr) {
    using am

    result := AMmapGet(doc, AM_ROOT, AMstr("max_entity_id"), c.NULL)
    item, _ := result_to_item(result)
    if AMitemValType(item) != .AM_VAL_TYPE_VOID {
        max: i64
        if !AMitemToCounter(item, &max) {
            fmt.println("Failed to convert from item to max_entity_id counter")
        }
        game.state.max_entity_id = u64(max)
    }

    doc_actions := get_undo_history_from_doc(doc)
    game_undo_len := len(game.state.undo_history)

    for len(doc_actions) > game_undo_len {
        action := doc_actions[game_undo_len]
        game.redo_action(game.state, game.tile_map, &action)
        //TODO(amatej): I guess this could cause problems
        //              because the action is only temp_allocated
        action.performed = true
        append(&game.state.undo_history, action)

        game_undo_len += 1
    }

    for len(doc_actions) < game_undo_len {
        action := &game.state.undo_history[len(game.state.undo_history)-1]
        game.undo_action(game.state, game.tile_map, action)
        game.pop_last_action(game.state, game.tile_map, &game.state.undo_history)

        game_undo_len -= 1
    }

}

@export
main_start :: proc "c" (mobile: bool) {
        using am
	context = runtime.default_context()
	// The WASM allocator doesn't seem to work properly in combination with
	// emscripten. There is some kind of conflict with how the manage memory.
	// So this sets up an allocator that uses emscripten's malloc.
        my_allocator = emscripten_allocator()
	context.allocator = my_allocator
	runtime.init_global_temporary_allocator(1*mem.Megabyte)

        rand.reset(u64(time.time_to_unix(time.now())))
        my_id[0] = u8(rand.int_max(9)+48)
        my_id[1] = u8(rand.int_max(9)+48)
        my_id[2] = u8(rand.int_max(9)+48)
        fmt.println("my id: ", string(my_id[:]))

	// Since we now use js_wasm32 we should be able to remove this and use
	// context.logger = log.create_console_logger(). However, that one produces
	// extra newlines on web. So it's a bug in that core lib.
	context.logger = create_emscripten_logger()

	web_context = context

        doc_result = AMcreate(nil)
        item, _ := result_to_item(doc_result)
        if !AMitemToDoc(item, &doc) {
            assert(false)
        }

        fmt.println("Setting up websocket")
        if (emscripten_websocket_is_supported() == 1) {
            attrs := EmscriptenWebSocketCreateAttributes{"http://socket.kontura.cc:80", nil, true}
            ws = emscripten_websocket_new(&attrs)
            fmt.println("ws: ", ws)
            emscripten_websocket_set_onopen_callback_on_thread(ws, nil, onopen, EM_CALLBACK_THREAD_CONTEXT_CALLING_THREAD)
            emscripten_websocket_set_onclose_callback_on_thread(ws, nil, onclose, EM_CALLBACK_THREAD_CONTEXT_CALLING_THREAD)
            emscripten_websocket_set_onmessage_callback_on_thread(ws, nil, onmessage, EM_CALLBACK_THREAD_CONTEXT_CALLING_THREAD)
            emscripten_websocket_set_onerror_callback_on_thread(ws, nil, onerror, EM_CALLBACK_THREAD_CONTEXT_CALLING_THREAD)
        }

        mount_idbfs()
	game.init(mobile)
}

@export
main_update :: proc "c" () -> bool {
        using am
	context = web_context
	game.update()
        if game.state.needs_sync {
            update_doc_from_game_state(doc)
            if socket_ready {
                for peer, &sync_state in peers {
                    finished : bool = false
                    for !finished {
                        msg_result := AMgenerateSyncMessage(doc, sync_state)
                        defer AMresultFree(msg_result)
                        msg_item := result_to_item(msg_result) or_return

                        #partial switch AMitemValType(msg_item) {
                        case .AM_VAL_TYPE_SYNC_MESSAGE:
                                msg: AMsyncMessagePtr
                                AMitemToSyncMessage(msg_item, &msg)
                                encode_result := AMsyncMessageEncode(msg)
                                defer AMresultFree(encode_result)
                                encode_item := result_to_item(encode_result) or_return
                                msg_bytes : AMbyteSpan
                                if !AMitemToBytes(encode_item, &msg_bytes) {
                                    assert(false)
                                }
                                binary := build_binary_message(transmute([]u8)peer, msg_bytes.src[:msg_bytes.count])
                                emscripten_websocket_send_binary(ws, &binary[0], u32(len(binary)))

                        case .AM_VAL_TYPE_VOID:
                            finished = true
                        case:
                            assert(false)
                        }

                    }
                }
            }
            game.state.needs_sync = false
        }

        if game.state.save == game.SaveStatus.REQUESTED{
            game.state.bytes_count = store_save()
            game.state.timeout = 60
            game.state.save = game.SaveStatus.DONE
        }

        free_all(context.temp_allocator)
	return game.should_run()
}

@export
main_end :: proc "c" () {
        am.AMresultFree(doc_result)
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
        data, ok := game.read_entire_file("/persist/tiler_save", context.temp_allocator)
        if ok {
            result := am.AMloadIncremental(doc, &data[0], len(data))
            am.AMresultFree(result)
            update_game_state_from_doc(doc)
        }
}

@export
store_save :: proc "c" () -> uint {
    context = runtime.default_context()
    context.allocator = my_allocator
    count: uint
    if doc != nil {
        // We have to use incremental save because normal
        // AMsave has to wierd memory problem probably
        // cause by rust.
        // To simulate always full save clone the doc first.
        clone_result := am.AMclone(doc)
        defer am.AMresultFree(clone_result)
        clone_doc: am.AMdocPtr
        clone_item, _ := am.result_to_item(clone_result)
        if !am.AMitemToDoc(clone_item, &clone_doc) {
            assert(false)
        }

        result := am.AMsaveIncremental(clone_doc)
        defer am.AMresultFree(result)
        am.verify_result(result)
        item, _ := am.result_to_item(result)
        if am.AMitemValType(item) == .AM_VAL_TYPE_BYTES {
            fmt.println("writing incremental bytes")
            bytes := am.item_to_or_report(item, am.AMbyteSpan)
            count = bytes.count
            game.write_entire_file("/persist/tiler_save", bytes.src[:bytes.count])
        }
    }
    return count
}
