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

@(private="file")
web_context: runtime.Context

@(default_calling_convention = "c")
foreign {
	mount_idbfs  :: proc() ---
}

ws : EMSCRIPTEN_WEBSOCKET_T
doc: AMdocPtr
socket_ready: bool = false
my_allocator: mem.Allocator
peers: map[string]AMsyncStatePtr
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
    context = runtime.default_context()
    context.allocator = my_allocator
    if websocketEvent.isText {
        assert(false)
    } else {
        sender_bytes, target, payload := parse_binary_message(websocketEvent.data[:websocketEvent.numBytes])
        sender := string(sender_bytes)
        fmt.println("sender bytes: ", sender_bytes)
        fmt.println("sender str: ", sender)
        sender_already_registered := sender in peers
        if !sender_already_registered {
            syncStateResult := AMsyncStateInit()
            //defer AMresultFree(syncStateResult)
            if (AMresultStatus(syncStateResult) != AMstatus.AM_STATUS_OK) {
                fmt.println("error encountered syncStateResult")
            }
            peers[strings.clone(sender)] = AMsyncStatePtr{}
            AMitemToSyncState(AMresultItem(syncStateResult), &peers[sender])
        }

        if !bytes.equal(target, my_id[:]) && len(target) != 0 {
            fmt.println("This message is not for me: ", target, " (target) x ", my_id[:], " (me)")
            assert(false)
        }
        if bytes.equal(sender_bytes, my_id[:]) {
            fmt.println("This message from me: ", target, " (target) x ", my_id[:], " (me)")
            assert(false)
        }
        if len(payload) != 0 {
            decode_and_receive(&payload[0], uint(len(payload)), doc, peers[sender])
            fmt.println("doc tokens after receive: ", get_tokens_from_doc(doc))
            fmt.println("doc actions after receive: ", get_undo_history_from_doc(doc))
            update_game_state_from_doc(doc)
        }
        game.state.needs_sync = true
    }
    return true
}

update_only_on_change :: proc(obj: AMobjIdPtr, key: cstring, $T: typeid, new: T) {
    get_result := AMmapGet(doc, obj, AMstr(key), c.NULL)
    if (AMresultStatus(get_result) != AMstatus.AM_STATUS_OK) {
        fmt.println("error encountered get_", key, "result")
    }
    insert: bool = false
    if AMitemValType(AMresultItem(get_result)) == .AM_VAL_TYPE_VOID {
        insert = true
    } else {
        value: T
        item := AMresultItem(get_result)
        if (!AMitemTo(item, &value)) {
            fmt.println("failed to convert to: ", value)
        }
        if value != new {
            insert = true
        }
    }
    if insert {
        insert_result: AMresultPtr
        insert_result = AMmapPut(doc, obj, AMstr(key), new)
        if (AMresultStatus(insert_result) != AMstatus.AM_STATUS_OK) {
            fmt.println("error encountered insert_result")
        }
    }
}

update_doc_from_game_state :: proc(doc: AMdocPtr) {
    update_doc_tokens(doc, &game.state.tokens)
    update_doc_actions(doc, game.state.undo_history[:])
}

get_or_insert :: proc(doc: AMdocPtr, obj_id: AMobjIdPtr, key: cstring, type: AMobjType) -> AMobjIdPtr {
    result := AMmapGet(doc, obj_id, AMstr(key), c.NULL)
    if (AMresultStatus(result) != AMstatus.AM_STATUS_OK) {
        fmt.println("error encountered while getting: ", key, " result: ", am_byte_span_to_string(AMresultError(result)))
    }
    id: AMobjIdPtr
    if AMitemValType(AMresultItem(result)) == .AM_VAL_TYPE_VOID {
        // Insert new
        new_result := AMmapPutObject(doc, AM_ROOT, AMstr(key), type)
        if (AMresultStatus(new_result) != AMstatus.AM_STATUS_OK) {
            fmt.println("error encountered while inserting: ", key, " result: ", am_byte_span_to_string(AMresultError(result)))
        }
        id = AMitemObjId(AMresultItem(new_result))
    } else {
        id = AMitemObjId(AMresultItem(result))
    }

    return id
}

update_doc_actions :: proc(doc: AMdocPtr, actions: []game.Action) {
    actions_list := get_or_insert(doc, AM_ROOT, "actions", .AM_OBJ_TYPE_LIST)
    doc_actions_list_count := AMobjSize(doc, actions_list, c.NULL)

    for doc_actions_list_count > len(actions) {
        //TODO(amatej): pop doc_actions_list_count - len(actions) actions
        doc_actions_list_count -= 1
    }

    for doc_actions_list_count < len(actions) {
        action := actions[doc_actions_list_count]
        put_result := AMlistPutObject(doc, actions_list, c.SIZE_MAX, true, .AM_OBJ_TYPE_MAP)
        if (AMresultStatus(put_result) != AMstatus.AM_STATUS_OK) {
            fmt.println("error encountered put_result: ", am_byte_span_to_string(AMresultError(put_result)))
        }
        action_map := AMitemObjId(AMresultItem(put_result))

        tile_history_result := AMmapPutObject(doc, action_map, AMstr("tile_history"), .AM_OBJ_TYPE_LIST)
        if (AMresultStatus(tile_history_result) != AMstatus.AM_STATUS_OK) {
            fmt.println("error encountered tile_history_result: ", am_byte_span_to_string(AMresultError(tile_history_result)))
        }
        tile_history := AMitemObjId(AMresultItem(tile_history_result))

        for pos, &tile in action.tile_history {
            tile_result := AMlistPutObject(doc, tile_history, c.SIZE_MAX, true, .AM_OBJ_TYPE_MAP)
            if (AMresultStatus(tile_result) != AMstatus.AM_STATUS_OK) {
                fmt.println("error encountered tile_result: ", am_byte_span_to_string(AMresultError(tile_result)))
            }
            tile_map := AMitemObjId(AMresultItem(tile_result))

            x_result := AMmapPutUint(doc, tile_map, AMstr("x"), u64(pos.x))
            if (AMresultStatus(x_result) != AMstatus.AM_STATUS_OK) {
                fmt.println("error encountered x_result")
            }
            y_result := AMmapPutUint(doc, tile_map, AMstr("y"), u64(pos.y))
            if (AMresultStatus(y_result) != AMstatus.AM_STATUS_OK) {
                fmt.println("error encountered y_result")
            }
            color_bytes: AMbyteSpan
            color_bytes.count = 4
            color_bytes.src = &tile.color[0]
            color_result := AMmapPutBytes(doc, tile_map, AMstr("color"), color_bytes)
            if (AMresultStatus(color_result) != AMstatus.AM_STATUS_OK) {
                fmt.println("error encountered color_result")
            }
            for wall in tile.walls {
                wall_str, ok := fmt.enum_value_to_string(wall)
                if ok {
                    wall_color_bytes: AMbyteSpan
                    wall_color_bytes.count = 4
                    wall_color_bytes.src = &tile.wall_colors[wall][0]
                    wall_color_result := AMmapPutBytes(doc, tile_map, AMstr(strings.clone_to_cstring(wall_str)), wall_color_bytes)
                    if (AMresultStatus(wall_color_result) != AMstatus.AM_STATUS_OK) {
                        fmt.println("error encountered wall_color_result")
                    }
                }
            }
        }

        doc_actions_list_count += 1
    }
}

update_doc_tokens :: proc(doc: AMdocPtr, tokens: ^map[u64]game.Token) {
    id_to_token := get_or_insert(doc, AM_ROOT, "tokens", .AM_OBJ_TYPE_MAP)

    for _, &token in tokens {
        id := fmt.caprint(token.id)
        get_result := AMmapGet(doc, id_to_token, AMstr(id), c.NULL)
        if (AMresultStatus(get_result) != AMstatus.AM_STATUS_OK) {
            fmt.println("error encountered get_result: ", am_byte_span_to_string(AMresultError(get_result)))
        }
        token_map: AMobjIdPtr
        if AMitemValType(AMresultItem(get_result)) == .AM_VAL_TYPE_VOID {
            // Insert a map into the map for each token
            token_map_result := AMmapPutObject(doc, id_to_token, AMstr(fmt.caprint(token.id)), .AM_OBJ_TYPE_MAP)
            if (AMresultStatus(token_map_result) != AMstatus.AM_STATUS_OK) {
                fmt.println("error encountered token_map_result: ", am_byte_span_to_string(AMresultError(token_map_result)))
            }
            token_map = AMitemObjId(AMresultItem(token_map_result))
            id_result := AMmapPutUint(doc, token_map, AMstr("id"), token.id)
            if (AMresultStatus(id_result) != AMstatus.AM_STATUS_OK) {
                fmt.println("error encountered id_result")
            }
            color_bytes: AMbyteSpan
            color_bytes.count = 4
            color_bytes.src = &token.color[0]
            color_result := AMmapPutBytes(doc, token_map, AMstr("color"), color_bytes)
            if (AMresultStatus(color_result) != AMstatus.AM_STATUS_OK) {
                fmt.println("error encountered color_result")
            }
        } else {
            token_map = AMitemObjId(AMresultItem(get_result))
        }

        update_only_on_change(token_map, "name", string, token.name)
        update_only_on_change(token_map, "initiative", i64, i64(token.initiative))
        update_only_on_change(token_map, "size", i64, i64(token.size))
        update_only_on_change(token_map, "x", u64, u64(token.position.abs_tile.x))
        update_only_on_change(token_map, "y", u64, u64(token.position.abs_tile.y))
    }

    for id, _ in get_tokens_from_doc(doc) {
        _, ok := tokens[id]
        if !ok {
            AMmapDelete(doc, id_to_token, AMstr(fmt.caprint(id, allocator=context.temp_allocator)))
        }

    }
}

get_undo_history_from_doc :: proc(doc: AMdocPtr) -> []game.Action {
    //TODO(amatej): this should use temp allocator
    undo_history := make([dynamic]game.Action, allocator=context.temp_allocator)

    undo_history_result: AMresultPtr = AMmapGet(doc, AM_ROOT, AMstr("actions"), c.NULL)
    if (AMresultStatus(undo_history_result) != AMstatus.AM_STATUS_OK) {
        fmt.println("error encountered undo_history_result")
    }

    if AMitemValType(AMresultItem(undo_history_result)) == .AM_VAL_TYPE_VOID {
        return undo_history[:]
    }

    undo_history_list := AMitemObjId(AMresultItem(undo_history_result))

    range_result := AMlistRange(doc, undo_history_list, 0, c.SIZE_MAX, c.NULL)
    if (AMresultStatus(range_result) != AMstatus.AM_STATUS_OK) {
        fmt.println("error encountered range_result")
    }
    items: AMitems = AMresultItems(range_result)
    action_item : AMitemPtr = AMitemsNext(&items, 1)
    for action_item != c.NULL {
        game_action: game.Action

        action_map := AMitemObjId(action_item)

        tile_history_result: AMresultPtr = AMmapGet(doc, action_map, AMstr("tile_history"), c.NULL)
        if (AMresultStatus(tile_history_result) != AMstatus.AM_STATUS_OK) {
            fmt.println("error encountered tile_history_result")
        }

        if AMitemValType(AMresultItem(tile_history_result)) != .AM_VAL_TYPE_VOID {
            tile_history_list := AMitemObjId(AMresultItem(tile_history_result))

            range_tiles_result := AMlistRange(doc, tile_history_list, 0, c.SIZE_MAX, c.NULL)
            if (AMresultStatus(range_tiles_result) != AMstatus.AM_STATUS_OK) {
                fmt.println("error encountered range_tiles_result")
            }
            tile_items: AMitems = AMresultItems(range_tiles_result)
            tile_item : AMitemPtr = AMitemsNext(&tile_items, 1)
            for tile_item != c.NULL {
                tile_map := AMitemObjId(tile_item)
                x_result := AMmapGet(doc, tile_map, AMstr("x"), c.NULL)
                x: u64
                if !(AMitemToUint(AMresultItem(x_result), &x)) {
                    fmt.println("failed to convert to u64 (x)")
                }
                y_result := AMmapGet(doc, tile_map, AMstr("y"), c.NULL)
                y: u64
                if !(AMitemToUint(AMresultItem(y_result), &y)) {
                    fmt.println("failed to convert to u64 (y)")
                }

                color_result := AMmapGet(doc, tile_map, AMstr("color"), c.NULL)
                color: AMbyteSpan
                if !(AMitemToBytes(AMresultItem(color_result), &color)) {
                    fmt.println("failed to convert to u64 (initiative)")
                }

                //TODO(amatej): do walls

                tile: game.Tile
                tile.color[0] = color.src[0]
                tile.color[1] = color.src[1]
                tile.color[2] = color.src[2]
                tile.color[3] = color.src[3]
                game_action.tile_history[{u32(x),u32(y)}] = tile

                tile_item = AMitemsNext(&tile_items, 1)
            }


        }

        append(&undo_history, game_action)

        action_item = AMitemsNext(&items, 1)
    }

    return undo_history[:]
}

get_tokens_from_doc :: proc(doc: AMdocPtr) -> map[u64]game.Token {
    id_to_tokenResult: AMresultPtr = AMmapGet(doc, AM_ROOT, AMstr("tokens"), c.NULL)
    if (AMresultStatus(id_to_tokenResult) != AMstatus.AM_STATUS_OK) {
        fmt.println("error encountered id_to_tokenResult")
    }

    tokens := make(map[u64]game.Token, allocator=context.temp_allocator)

    if AMitemValType(AMresultItem(id_to_tokenResult)) == .AM_VAL_TYPE_VOID {
        return tokens
    }

    id_to_token := AMitemObjId(AMresultItem(id_to_tokenResult))

    range_result := AMmapRange(doc, id_to_token, AMstr(nil), AMstr(nil), c.NULL)
    if (AMresultStatus(range_result) != AMstatus.AM_STATUS_OK) {
        fmt.println("error encountered range_result")
    }
    items: AMitems = AMresultItems(range_result)
    token_item : AMitemPtr = AMitemsNext(&items, 1)
    for token_item != c.NULL {
        token_map := AMitemObjId(token_item)

        id_result := AMmapGet(doc, token_map, AMstr("id"), c.NULL)
        id: u64
        if (AMitemToUint(AMresultItem(id_result), &id)) {
            //fmt.println("read token id from automerge doc: ", id)
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
        name: string
	if (AMitemTo(AMresultItem(name_result), &name)) {
            //fmt.println("read token name from automerge doc: ", name)
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

        color_result := AMmapGet(doc, token_map, AMstr("color"), c.NULL)
        color: AMbyteSpan
        if (AMitemToBytes(AMresultItem(color_result), &color)) {
            //fmt.println("read token id from automerge doc: ", id)
        } else {
            fmt.println("failed to convert to u64 (initiative)")
        }

        t: game.Token
        t.name = name
        t.position = token_pos
        t.size = i32(size)
        t.id = id
        t.initiative = i32(initiative)
        t.color[0] = color.src[0]
        t.color[1] = color.src[1]
        t.color[2] = color.src[2]
        t.color[3] = color.src[3]

        tokens[t.id] = t

        token_item = AMitemsNext(&items, 1)
    }
    return tokens
}

update_game_state_from_doc :: proc(doc: AMdocPtr) {
    //TODO(amatej): I need to sync:
    // - max_entity_id (needs to be a counter)

    doc_tokens := get_tokens_from_doc(doc)

    for _, doc_token in doc_tokens {
        game.state.tokens[doc_token.id] = doc_token
        game.remove_token_by_id_from_initiative(game.state, doc_token.id)
        if game.state.initiative_to_tokens[i32(doc_token.initiative)] == nil {
            game.state.initiative_to_tokens[i32(doc_token.initiative)] = make([dynamic]u64)
        }
        append(&game.state.initiative_to_tokens[i32(doc_token.initiative)], doc_token.id)
    }
    for id, _ in game.state.tokens {
        _, ok := &doc_tokens[id]
        if !ok {
            delete_key(&game.state.tokens, id)
        }

    }

    doc_actions := get_undo_history_from_doc(doc)
    game_undo_len := len(game.state.undo_history)

    for len(doc_actions) > game_undo_len {
        action := doc_actions[game_undo_len]
        game.redo_action(game.state, game.tile_map, &action)
        append(&game.state.undo_history, action)

        game_undo_len += 1
    }

    //for len(doc_actions) < len(game.state.undo_history) {
    //    //TODO(amatej): undo the extra actions
    //}

}

@export
main_start :: proc "c" (mobile: bool) {
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

        {
            fmt.println("Setting up automerge doc and sync_state")
            docResult := AMcreate(nil)
            //defer AMresultFree(docResult)
            if (AMresultStatus(docResult) != AMstatus.AM_STATUS_OK) {
                fmt.println("error encountered docResult")
            }
            AMitemToDoc(AMresultItem(docResult), &doc)

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
	context = web_context
	game.update()
        if game.state.needs_sync {
            update_doc_from_game_state(doc)
            if socket_ready {
                for peer, &syncState in peers {
                    finished : bool = false
                    for !finished {
                        msg_bytes : AMbyteSpan
                        msg_bytes, finished = generate_and_encode(doc, syncState)
                        fmt.println("peer target: ", peer)
                        fmt.println("byte target: ", transmute([]u8)peer)
                        binary := build_binary_message(transmute([]u8)peer, msg_bytes.src[:msg_bytes.count])
                        fmt.println("binary msg: ", binary)
                        if (!finished) {
                            emscripten_websocket_send_binary(ws, &binary[0], u32(len(binary)))
                        }
                    }
                    game.state.needs_sync = false
                }
            }
        }

        free_all(context.temp_allocator)
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
