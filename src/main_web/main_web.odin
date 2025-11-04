// These procs are the ones that will be called from `index.html`, which is
// generated from `index_template.html`.

package main_web

import game ".."
import "base:runtime"
import "core:bytes"
import "core:c"
import "core:fmt"
import "core:math"
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

socket_ready: bool = false
my_allocator: mem.Allocator
peers: map[string]PeerState
//TODO(amatej): replace with id in GameState
my_id: [3]u8

PeerState :: struct {
    webrtc:             WEBRTC_STATE,
    last_known_actions: [dynamic]game.Action,
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
    msg := game.build_binary_message(my_id, 2, peer_data[:peer_len], msg_data[:msg_len])
    out_len^ = u32(len(msg))
    out_data^ = &msg[0]
}

@(export)
build_register_msg_c :: proc "c" (out_len: ^u32, out_data: ^rawptr) {
    context = web_context
    register := game.build_register_msg(my_id, game.state)
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
    context = runtime.default_context()
    context.allocator = my_allocator

    type, sender_bytes, target, payload := parse_binary_message(data[:data_len])
    sender := string(sender_bytes)
    sender_already_registered := sender in peers
    if !sender_already_registered {
        peers[strings.clone(sender)] = {.WAITING, {}}
        peer_state := &peers[sender]
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
        bytes: []byte = payload[:len(payload)]
        // context.allocator allocated actions
        actions := game.load_from_serialized(bytes)
        if len(actions) > 0 {
            for _, index in peer_state.last_known_actions {
                game.delete_action(&peer_state.last_known_actions[index])
            }
            clear(&peer_state.last_known_actions)
            for &a in actions {
                append(&peer_state.last_known_actions, game.duplicate_action(&a))
            }
        }
        //TODO(amatej): check if this returns that we have newer then we got, if so we need_to_sync
        game.merge_and_redo_actions(game.state, game.tile_map, actions)
        if len(target) == 0 {
            fmt.println("Registering: ", sender)
            make_webrtc_offer(&sender_bytes[0], u32(len(sender_bytes)))
            peer_state.webrtc = .OFFERED
            game.state.needs_sync = true
        }
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

@(export)
paste_image :: proc "c" (data: [^]u8, width: i32, height: i32) {
    context = runtime.default_context()

    game.add_background(data, width, height)

    fmt.println(data)
    fmt.println(width)
    fmt.println(height)
}

@(export)
main_start :: proc "c" (path_len: u32, path_data: [^]u8, mobile: bool) {
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

    fmt.println("Setting up signaling websocket")
    connect_signaling_websocket()

    //TODO(amatej): load saves
    //mount_idbfs()
    game.init(string(path_data[:path_len]), mobile)
}

@(export)
main_update :: proc "c" () -> bool {
    context = web_context
    game.update()

    if game.state.debug {
        p := make(map[string]bool, allocator = context.temp_allocator)
        for peer, &peer_state in peers {
            p[peer] = peer_state.webrtc == .CONNECTED ? true : false
        }
        game.draw_connections(string(my_id[:]), socket_ready, p)
    }

    if game.state.needs_sync && !game.state.offline {
        if socket_ready {
            for peer, &peer_state in peers {
                peer_bytes := transmute([]u8)peer
                binary: []u8
                _, to_send := game.find_first_not_matching_action(
                    peer_state.last_known_actions[:],
                    game.state.undo_history[:],
                )
                serialized_actions := game.serialize_actions(game.state.undo_history[to_send:], context.temp_allocator)
                binary = game.build_binary_message(my_id, 1, peer_bytes, serialized_actions)
                send_binary_to_peer(&peer_bytes[0], u32(len(peer_bytes)), &binary[0], u32(len(binary)))
                if len(game.state.undo_history[to_send:]) > 0 {
                    for _, index in peer_state.last_known_actions {
                        game.delete_action(&peer_state.last_known_actions[index])
                    }
                    clear(&peer_state.last_known_actions)
                    if len(game.state.undo_history[to_send:]) > 0 {
                        append(
                            &peer_state.last_known_actions,
                            game.duplicate_action(&game.state.undo_history[len(game.state.undo_history) - 1]),
                        )
                    }
                }
            }
        }
        game.state.needs_sync = false
    }

    //if game.state.save == game.SaveStatus.REQUESTED {
    //    game.state.bytes_count = store_save()
    //    game.state.timeout = 60
    //    game.state.save = game.SaveStatus.DONE
    //}

    free_all(context.temp_allocator)
    return true
}

@(export)
main_end :: proc "c" () {
    context = web_context
    game.shutdown()
}

@(export)
web_window_size_changed :: proc "c" (w: c.int, h: c.int) {
    context = web_context
    game.parent_window_size_changed(int(w), int(h))
}

//@(export)
//load_save :: proc "c" () {
//    context = web_context
//    save_name := fmt.aprint("/persist/", game.state.path, sep = "", allocator = context.temp_allocator)
//    data, ok := game.read_entire_file(save_name, context.temp_allocator)
//    if ok {
//        result := am.AMloadIncremental(doc, &data[0], len(data))
//        am.AMresultFree(result)
//        update_game_state_from_doc(doc)
//    }
//}
//
//@(export)
//store_save :: proc "c" () -> uint {
//    context = runtime.default_context()
//    context.allocator = my_allocator
//    count: uint
//    if doc != nil {
//        // We have to use incremental save because normal
//        // AMsave has to wierd memory problem probably
//        // cause by rust.
//        // To simulate always full save clone the doc first.
//        clone_result := am.AMclone(doc)
//        defer am.AMresultFree(clone_result)
//        clone_doc: am.AMdocPtr
//        clone_item, _ := am.result_to_item(clone_result)
//        if !am.AMitemToDoc(clone_item, &clone_doc) {
//            assert(false)
//        }
//
//        result := am.AMsaveIncremental(clone_doc)
//        defer am.AMresultFree(result)
//        am.verify_result(result)
//        item, _ := am.result_to_item(result)
//        if am.AMitemValType(item) == .AM_VAL_TYPE_BYTES {
//            fmt.println("writing incremental bytes")
//            bytes := am.item_to_or_report(item, am.AMbyteSpan)
//            count = bytes.count
//            save_name := fmt.aprint("/persist/", game.state.path, sep = "", allocator = context.temp_allocator)
//            game.write_entire_file(save_name, bytes.src[:bytes.count])
//        }
//    }
//    return count
//}
