// These procs are the ones that will be called from `index.html`, which is
// generated from `index_template.html`.

package main_web

import game ".."
import am "../automerge"
import "base:runtime"
import "core:bytes"
import "core:c"
import "core:fmt"
import "core:math/rand"
import "core:mem"
import "core:strings"
import "core:time"


@(private = "file")
web_context: runtime.Context

@(default_calling_convention = "c")
foreign _ {
    mount_idbfs :: proc() ---
    make_webrtc_offer :: proc(peer_ptr: rawptr, peer_len: u32) ---
    accept_webrtc_offer :: proc(peer_ptr: rawptr, peer_len: u32, sdp_data: rawptr, sdp_len: u32) ---
    accept_webrtc_answer :: proc(peer_ptr: rawptr, peer_len: u32, answer_data: rawptr, answer_len: u32) ---
    add_peer_ice :: proc(peer_ptr: rawptr, peer_len: u32, msg_data: rawptr, msg_len: u32) ---
    connect_signaling_websocket :: proc() ---
    send_binary_to_peer :: proc(peer_ptr: rawptr, peer_len: u32, data: rawptr, len: u32) ---
}

doc: am.AMdocPtr
doc_result: am.AMresultPtr
socket_ready: bool = false
my_allocator: mem.Allocator
peers: map[string]PeerState
my_id: [3]u8

PeerState :: struct {
    am_sync_state: am.AMsyncStatePtr,
    webrtc:        WEBRTC_STATE,
}

WEBRTC_STATE :: enum u8 {
    WAITING,
    OFFERED,
    ANSWERED,
    ICE,
    CONNECTED,
}

@(export)
build_binary_msg_c :: proc "c" (
    peer_len: u32,
    peer_data: [^]u8,
    msg_len: u32,
    msg_data: [^]u8,
    out_len: ^u32,
    out_data: ^rawptr,
) {
    context = web_context
    msg := build_binary_message(2, peer_data[:peer_len], msg_data[:msg_len])
    out_len^ = u32(len(msg))
    out_data^ = &msg[0]
}

@(export)
build_register_msg_c :: proc "c" (out_len: ^u32, out_data: ^rawptr) {
    context = web_context
    register := build_binary_message(1, nil, nil)
    out_len^ = u32(len(register))
    out_data^ = &register[0]
}

@(export)
set_socket_ready :: proc "c" () {
    socket_ready = true
}

@(export)
set_peer_rtc_connected :: proc "c" (peer_len: u32, peer_data: [^]u8) {
    peer := string(peer_data[:peer_len])
    peer_state := &peers[peer]
    peer_state.webrtc = .CONNECTED
}

build_binary_message :: proc(type: u8, target: []u8, payload: []u8) -> []u8 {
    msg := make([dynamic]u8, allocator = context.temp_allocator)
    append(&msg, type)
    append(&msg, 3)
    append(&msg, my_id[0])
    append(&msg, my_id[1])
    append(&msg, my_id[2])
    append(&msg, u8(len(target)))
    append(&msg, ..target[:])
    append(&msg, ..payload[:])
    return msg[:]
}

parse_binary_message :: proc(msg: []u8) -> (type: u8, sender, target, payload: []u8) {
    // 0 1 2 3 4 5 6 7 8 9
    // 1 3 a b c 3 d e f x x x
    type = msg[0]
    sender_len := msg[1]
    sender = msg[2:2 + sender_len]
    target_len := msg[2 + sender_len]
    target = msg[3 + sender_len:3 + sender_len + target_len]
    payload = msg[3 + sender_len + target_len:]
    return
}

@(export)
process_binary_msg :: proc "c" (data_len: u32, data: [^]u8) {
    using am
    context = runtime.default_context()
    context.allocator = my_allocator

    type, sender_bytes, target, payload := parse_binary_message(data[:data_len])
    sender := string(sender_bytes)
    sender_already_registered := sender in peers
    if !sender_already_registered {
        sync_state_result := AMsyncStateInit()
        //TODO(amatej): they will need to be globally managed
        item, _ := result_to_item(sync_state_result)
        peers[strings.clone(sender)] = {AMsyncStatePtr{}, .WAITING}
        peer_state := &peers[sender]
        AMitemToSyncState(item, &peer_state.am_sync_state)
    }

    if !bytes.equal(target, my_id[:]) && len(target) != 0 {
        fmt.println("This message is not for me: ", target, " (target) x ", my_id[:], " (me)")
        assert(false)
    }
    if bytes.equal(sender_bytes, my_id[:]) {
        fmt.println("This message is from me: ", target, " (target) x ", my_id[:], " (me)")
        assert(false)
    }

    peer_state := &peers[sender]

    if type == 1 {
        if len(payload) != 0 {
            decode_and_receive(&payload[0], uint(len(payload)), doc, peer_state.am_sync_state)
        } else {
            fmt.println("Registering: ", sender)
            make_webrtc_offer(&sender_bytes[0], u32(len(sender_bytes)))
            peer_state.webrtc = .OFFERED
        }
        game.state.needs_sync = true
    } else if type == 2 {
        if peer_state.webrtc == .WAITING {
            accept_webrtc_offer(&sender_bytes[0], u32(len(sender_bytes)), &payload[0], u32(len(payload)))
            peer_state.webrtc = .ICE
        } else if peer_state.webrtc == .OFFERED {
            accept_webrtc_answer(&sender_bytes[0], u32(len(sender_bytes)), &payload[0], u32(len(payload)))
            peer_state.webrtc = .ICE
        } else if peer_state.webrtc == .ICE {
            add_peer_ice(&sender_bytes[0], u32(len(sender_bytes)), &payload[0], u32(len(payload)))
        }
        return
    }
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

    if doc_actions_list_count > len(actions) {
        game.state.needs_sync = true
    }

    for doc_actions_list_count < len(actions) {
        action := &actions[doc_actions_list_count]
        put_result := AMlistPutObject(doc, actions_id, c.SIZE_MAX, true, .AM_OBJ_TYPE_MAP)
        defer AMresultFree(put_result)
        action_map := result_to_objid(put_result) or_return

        put_into_map(doc, action_map, "action", action)

        doc_actions_list_count += 1

        commit_result := AMcommit(doc, AMstr("Update"), (^i64)(c.NULL))
        item := result_to_item(commit_result) or_return
        if AMitemValType(item) != .AM_VAL_TYPE_VOID {
            bytes: am.AMbyteSpan
            if !AMitemToChangeHash(item, &bytes) {
                fmt.println("Failed to convert from item to change hash")
            }
            for i := 0; i < 32; i += 1 {
                action.hash[i] = bytes.src[i]
            }
        }

        AMresultFree(commit_result)
    }

    return true
}

get_undo_history_from_doc :: proc(doc: am.AMdocPtr) -> [dynamic]game.Action {
    using am
    undo_history := make([dynamic]game.Action)

    undo_history_result: AMresultPtr = AMmapGet(doc, AM_ROOT, AMstr("actions"), c.NULL)
    defer AMresultFree(undo_history_result)
    undo_history_id, _ := result_to_objid(undo_history_result)

    //TODO(amatej): technically I could get only those action I don't already have
    range_result := AMlistRange(doc, undo_history_id, 0, c.SIZE_MAX, c.NULL)
    defer AMresultFree(range_result)
    verify_result(range_result)
    items: AMitems = AMresultItems(range_result)
    action_item: AMitemPtr = AMitemsNext(&items, 1)

    changes_result := AMgetChanges(doc, c.NULL)
    verify_result(changes_result)
    defer AMresultFree(changes_result)
    change_items: AMitems = AMresultItems(changes_result)
    change_item: AMitemPtr = AMitemsNext(&change_items, 1)

    for action_item != c.NULL {
        game_action: game.Action
        action_map := AMitemObjId(action_item)

        game_action = get_from_map(doc, action_map, "action", game.Action)
        game_action.mine = false


        change: AMchangePtr

        AMitemToChange(change_item, &change)
        msg := AMchangeMessage(change)
        // TODO(amatej): verify our message is "Update", we know its 6 long
        // This is needed because automerge adds at least one its own commit at the start of a client/doc
        // Pair commits to actions, we should always have one action per commit
        for msg.count != 6 {
            change_item = AMitemsNext(&change_items, 1)
            AMitemToChange(change_item, &change)
            msg = AMchangeMessage(change)
            fmt.println("looping")
        }

        bytes := AMchangeHash(change)
        for i := 0; i < 32; i += 1 {
            game_action.hash[i] = bytes.src[i]
        }
        fmt.println("got hash: ", game_action.hash)

        append(&undo_history, game_action)
        action_item = AMitemsNext(&items, 1)
        change_item = AMitemsNext(&change_items, 1)
    }

    return undo_history
}

update_game_state_from_doc :: proc(doc: am.AMdocPtr) {
    using am

    result := AMmapGet(doc, AM_ROOT, AMstr("max_entity_id"), c.NULL)
    defer AMresultFree(result)
    item, _ := result_to_item(result)
    if AMitemValType(item) != .AM_VAL_TYPE_VOID {
        max: i64
        if !AMitemToCounter(item, &max) {
            fmt.println("Failed to convert from item to max_entity_id counter")
        }
        game.state.max_entity_id = u64(max)
    }

    new_undo_hist := get_undo_history_from_doc(doc)
    game.redo_unmatched_actions(game.state, game.tile_map, new_undo_hist[:])
    for _, index in game.state.undo_history {
        game.delete_action(&game.state.undo_history[index])
    }
    delete(game.state.undo_history)
    game.state.undo_history = new_undo_hist
}

@(export)
paste_image :: proc "c" (data: [^]u8, width: i32, height: i32) {
    context = runtime.default_context()

    game.add_background(data, width, height)

    fmt.println(data)
    fmt.println(width)
    fmt.println(height)
}

@(export)
main_start :: proc "c" (mobile: bool) {
    using am
    context = runtime.default_context()
    // The WASM allocator doesn't seem to work properly in combination with
    // emscripten. There is some kind of conflict with how the manage memory.
    // So this sets up an allocator that uses emscripten's malloc.
    my_allocator = emscripten_allocator()
    context.allocator = my_allocator
    runtime.init_global_temporary_allocator(1 * mem.Megabyte)

    rand.reset(u64(time.time_to_unix(time.now())))
    my_id[0] = u8(rand.int_max(9) + 48)
    my_id[1] = u8(rand.int_max(9) + 48)
    my_id[2] = u8(rand.int_max(9) + 48)
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

    fmt.println("Setting up signaling websocket")
    connect_signaling_websocket()

    mount_idbfs()
    game.init(mobile)
}

@(export)
main_update :: proc "c" () -> bool {
    using am
    context = web_context
    game.update()

    if game.state.debug {
        p := make(map[string]bool, allocator = context.temp_allocator)
        for peer, &peer_state in peers {
            p[peer] = peer_state.webrtc == .CONNECTED ? true : false
        }
        game.draw_connections(string(my_id[:]), socket_ready, p)
    }

    if game.state.needs_sync {
        update_doc_from_game_state(doc)
        if socket_ready {
            for peer, &peer_state in peers {
                finished: bool = false
                for !finished {
                    msg_result := AMgenerateSyncMessage(doc, peer_state.am_sync_state)
                    defer AMresultFree(msg_result)
                    msg_item := result_to_item(msg_result) or_return

                    #partial switch AMitemValType(msg_item) {
                    case .AM_VAL_TYPE_SYNC_MESSAGE:
                        msg: AMsyncMessagePtr
                        AMitemToSyncMessage(msg_item, &msg)
                        encode_result := AMsyncMessageEncode(msg)
                        defer AMresultFree(encode_result)
                        encode_item := result_to_item(encode_result) or_return
                        msg_bytes: AMbyteSpan
                        if !AMitemToBytes(encode_item, &msg_bytes) {
                            assert(false)
                        }
                        peer_bytes := transmute([]u8)peer
                        binary := build_binary_message(1, peer_bytes, msg_bytes.src[:msg_bytes.count])
                        send_binary_to_peer(&peer_bytes[0], u32(len(peer_bytes)), &binary[0], u32(len(binary)))

                    case .AM_VAL_TYPE_VOID:
                        finished = true
                        update_game_state_from_doc(doc)
                    case:
                        assert(false)
                    }

                }
            }
        }
        game.state.needs_sync = false
    }

    if game.state.save == game.SaveStatus.REQUESTED {
        game.state.bytes_count = store_save()
        game.state.timeout = 60
        game.state.save = game.SaveStatus.DONE
    }

    free_all(context.temp_allocator)
    return game.should_run()
}

@(export)
main_end :: proc "c" () {
    am.AMresultFree(doc_result)
    context = web_context
    game.shutdown()
}

@(export)
web_window_size_changed :: proc "c" (w: c.int, h: c.int) {
    context = web_context
    game.parent_window_size_changed(int(w), int(h))
}

@(export)
load_save :: proc "c" () {
    context = web_context
    data, ok := game.read_entire_file("/persist/tiler_save", context.temp_allocator)
    if ok {
        result := am.AMloadIncremental(doc, &data[0], len(data))
        am.AMresultFree(result)
        update_game_state_from_doc(doc)
    }
}

@(export)
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
