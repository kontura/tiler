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

update_only_on_change :: proc(obj: am.AMobjIdPtr, key: cstring, new: $T, loc := #caller_location) -> bool {
    using am
    result := AMmapGet(doc, obj, AMstr(key), c.NULL)
    item := result_to_item(result) or_return
    defer AMresultFree(result)
    insert: bool = false
    if AMitemValType(item) == .AM_VAL_TYPE_VOID {
        insert = true
    } else {
        value: T
        if (!AMitemTo(item, &value)) {
            fmt.println("Failed to convert from item at: ", loc)
        }
        if value != new {
            insert = true
        }
    }
    if insert {
        insert_result := AMmapPut(doc, obj, AMstr(key), new)
        defer AMresultFree(insert_result)
        verify_result(insert_result)
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

    update_doc_tokens(doc, &game.state.tokens)
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
        //TODO(amatej): pop doc_actions_list_count - len(actions) actions
        doc_actions_list_count -= 1
    }

    for doc_actions_list_count < len(actions) {
        action := actions[doc_actions_list_count]
        put_result := AMlistPutObject(doc, actions_id, c.SIZE_MAX, true, .AM_OBJ_TYPE_MAP)
        defer AMresultFree(put_result)
        action_map := result_to_objid(put_result) or_return

        if action.tool == .RECTANGLE {
            put_map_value(doc, action_map, "start_x", u64(action.start.abs_tile.x)) or_return
            put_map_value(doc, action_map, "start_y", u64(action.start.abs_tile.y)) or_return

            put_map_value(doc, action_map, "end_x", u64(action.end.abs_tile.x)) or_return
            put_map_value(doc, action_map, "end_y", u64(action.end.abs_tile.y)) or_return

            color_bytes: AMbyteSpan
            color_bytes.count = 4
            color_bytes.src = &action.color[0]
            put_map_value(doc, action_map, "color", color_bytes) or_return
            tool_str, ok := fmt.enum_value_to_string(action.tool)
            if ok {
                put_map_value(doc, action_map, "tool", tool_str) or_return
            } else {
                assert(false)
            }
        } else {
            tile_history_result := AMmapPutObject(doc, action_map, AMstr("tile_history"), .AM_OBJ_TYPE_LIST)
            defer AMresultFree(tile_history_result)
            tile_history := result_to_objid(tile_history_result) or_return
            for pos, &tile in action.tile_history {
                tile_result := AMlistPutObject(doc, tile_history, c.SIZE_MAX, true, .AM_OBJ_TYPE_MAP)
                defer AMresultFree(tile_result)
                tile_map := result_to_objid(tile_result) or_return


                x_result := AMmapPutUint(doc, tile_map, AMstr("x"), u64(pos.x))
                defer AMresultFree(x_result)
                verify_result(x_result) or_return

                y_result := AMmapPutUint(doc, tile_map, AMstr("y"), u64(pos.y))
                defer AMresultFree(y_result)
                verify_result(y_result) or_return

                color_bytes: AMbyteSpan
                color_bytes.count = 4
                color_bytes.src = &tile.color[0]
                color_result := AMmapPutBytes(doc, tile_map, AMstr("color"), color_bytes)
                defer AMresultFree(color_result)
                verify_result(color_result)

                for wall in tile.walls {
                    wall_str, ok := fmt.enum_value_to_string(wall)
                    if ok {
                        wall_color_bytes: AMbyteSpan
                        wall_color_bytes.count = 4
                        wall_color_bytes.src = &tile.wall_colors[wall][0]
                        wall_color_result := AMmapPutBytes(doc, tile_map, AMstr(strings.clone_to_cstring(wall_str, allocator=context.temp_allocator)), wall_color_bytes)
                        defer AMresultFree(wall_color_result)
                        verify_result(wall_color_result) or_return
                    }
                }
            }
        }

        doc_actions_list_count += 1
    }

    return true
}

update_doc_tokens :: proc(doc: am.AMdocPtr, tokens: ^map[u64]game.Token) -> bool {
    using am
    tokens_result := get_or_insert(doc, AM_ROOT, "tokens", .AM_OBJ_TYPE_MAP)
    defer AMresultFree(tokens_result)
    tokens_id := result_to_objid(tokens_result) or_return

    for _, &token in tokens {
        id := fmt.caprint(token.id, allocator=context.temp_allocator)
        token_result := AMmapGet(doc, tokens_id, AMstr(id), c.NULL)
        defer AMresultFree(token_result)
        token_item := result_to_item(token_result) or_return
        token_id: AMobjIdPtr
        if AMitemValType(token_item) == .AM_VAL_TYPE_VOID {
            AMresultFree(token_result)
            // Insert a map into the map for each token
            token_result = AMmapPutObject(doc, tokens_id, AMstr(fmt.caprint(token.id)), .AM_OBJ_TYPE_MAP)
            token_id = result_to_objid(token_result) or_return
            put_map_value(doc, token_id, "id", token.id) or_return
            color_bytes: AMbyteSpan
            color_bytes.count = 4
            color_bytes.src = &token.color[0]
            put_map_value(doc, token_id, "color", color_bytes) or_return
        } else {
            token_id = AMitemObjId(token_item)
        }

        update_only_on_change(token_id, "name", token.name) or_return
        update_only_on_change(token_id, "initiative", i64(token.initiative)) or_return
        update_only_on_change(token_id, "size", i64(token.size)) or_return
        update_only_on_change(token_id, "x", u64(token.position.abs_tile.x)) or_return
        update_only_on_change(token_id, "y", u64(token.position.abs_tile.y)) or_return

    }

    for id, _ in get_tokens_from_doc(doc) {
        _, ok := tokens[id]
        if !ok {
            result := AMmapDelete(doc, tokens_id, AMstr(fmt.caprint(id, allocator=context.temp_allocator)))
            verify_result(result)
            AMresultFree(result)
        }
    }

    return true
}

get_undo_history_from_doc :: proc(doc: am.AMdocPtr) -> []game.Action {
    using am
    undo_history := make([dynamic]game.Action, allocator=context.temp_allocator)

    undo_history_result: AMresultPtr = AMmapGet(doc, AM_ROOT, AMstr("actions"), c.NULL)
    defer AMresultFree(undo_history_result)
    undo_history_id, _ := result_to_objid(undo_history_result)

    range_result := AMlistRange(doc, undo_history_id, 0, c.SIZE_MAX, c.NULL)
    defer AMresultFree(range_result)
    verify_result(range_result)
    items: AMitems = AMresultItems(range_result)
    action_item : AMitemPtr = AMitemsNext(&items, 1)
    for action_item != c.NULL {
        game_action: game.Action
        action_map := AMitemObjId(action_item)
        tool_result: AMresultPtr = AMmapGet(doc, action_map, AMstr("tool"), c.NULL)
        defer AMresultFree(tool_result)
        tool_item, _ := result_to_item(tool_result)
        if AMitemValType(tool_item) != .AM_VAL_TYPE_VOID {
            start: game.TileMapPosition
            end: game.TileMapPosition
            start.abs_tile.x = u32(get_map_value(doc, action_map, "start_x", u64))
            start.abs_tile.y = u32(get_map_value(doc, action_map, "start_y", u64))
            end.abs_tile.x = u32(get_map_value(doc, action_map, "end_x", u64))
            end.abs_tile.y = u32(get_map_value(doc, action_map, "end_y", u64))

            game_action.start = start
            game_action.end = end
            color := get_map_value(doc, action_map, "color", AMbyteSpan)
            game_action.color[0] = color.src[0]
            game_action.color[1] = color.src[1]
            game_action.color[2] = color.src[2]
            game_action.color[3] = color.src[3]

            tool_str := item_to_or_report(tool_item, string)
            tool, ok := fmt.string_to_enum_value(game.Tool, tool_str)
            if ok {
                game_action.tool = tool
            } else {
                assert(false)
            }
        }

        tile_history_result: AMresultPtr = AMmapGet(doc, action_map, AMstr("tile_history"), c.NULL)
        defer AMresultFree(tile_history_result)
        tile_history_item, _ := result_to_item(tile_history_result)

        if AMitemValType(tile_history_item) != .AM_VAL_TYPE_VOID {
            tile_history_list := AMitemObjId(tile_history_item)

            range_tiles_result := AMlistRange(doc, tile_history_list, 0, c.SIZE_MAX, c.NULL)
            defer AMresultFree(range_tiles_result)
            verify_result(range_tiles_result)
            tile_items: AMitems = AMresultItems(range_tiles_result)
            tile_item : AMitemPtr = AMitemsNext(&tile_items, 1)
            for tile_item != c.NULL {
                tile_map := AMitemObjId(tile_item)

                x := get_map_value(doc, tile_map, "x", u64)

                y_result := AMmapGet(doc, tile_map, AMstr("y"), c.NULL)
                defer AMresultFree(y_result)
                y_item, _ := result_to_item(y_result)
                y := item_to_or_report(y_item, u64)

                color_result := AMmapGet(doc, tile_map, AMstr("color"), c.NULL)
                defer AMresultFree(color_result)
                color_item, _ := result_to_item(color_result)
                color := item_to_or_report(color_item, AMbyteSpan)

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

get_tokens_from_doc :: proc(doc: am.AMdocPtr) -> map[u64]game.Token {
    using am
    tokens_result: AMresultPtr = AMmapGet(doc, AM_ROOT, AMstr("tokens"), c.NULL)
    defer AMresultFree(tokens_result)
    tokens_id, _ := result_to_objid(tokens_result)

    tokens := make(map[u64]game.Token, allocator=context.temp_allocator)

    range_result := AMmapRange(doc, tokens_id, AMstr(nil), AMstr(nil), c.NULL)
    defer AMresultFree(range_result)
    verify_result(range_result)
    items: AMitems = AMresultItems(range_result)
    token_item : AMitemPtr = AMitemsNext(&items, 1)
    for token_item != c.NULL {
        token_map := AMitemObjId(token_item)

        id := get_map_value(doc, token_map, "id", u64)
        x := get_map_value(doc, token_map, "x", u64)
        y := get_map_value(doc, token_map, "y", u64)
        name := get_map_value(doc, token_map, "name", string)
        size := get_map_value(doc, token_map, "size", i64)
        initiative := get_map_value(doc, token_map, "initiative", i64)
        color := get_map_value(doc, token_map, "color", AMbyteSpan)

        token_pos: game.TileMapPosition
        token_pos.abs_tile.x = u32(x)
        token_pos.abs_tile.y = u32(y)

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
        game.load_save()
}

@export
store_save :: proc "c" () {
	context = web_context
        game.store_save()
}
