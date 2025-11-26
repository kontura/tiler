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
    make_webrtc_offer :: proc(peer_id: u64) ---
    accept_webrtc_offer :: proc(peer_id: u64, sdp_data: rawptr, sdp_len: u32) ---
    accept_webrtc_answer :: proc(peer_id: u64, answer_data: rawptr, answer_len: u32) ---
    add_peer_ice :: proc(peer_id: u64, msg_data: rawptr, msg_len: u32) ---
    connect_signaling_websocket :: proc() ---
    send_binary_to_peer :: proc(peer_id: u64, data: rawptr, len: u32) ---
}

socket_ready: bool = false
my_allocator: mem.Allocator
when ODIN_DEBUG {
    track: mem.Tracking_Allocator
}
peers: map[u64]PeerState

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
    peer_id: u64,
    msg_len: u32,
    msg_data: [^]u8,
    out_len: ^u32,
    out_data: ^rawptr,
) {
    context = web_context
    msg := game.build_binary_message(game.state.id, 2, peer_id, msg_data[:msg_len])
    out_len^ = u32(len(msg))
    out_data^ = &msg[0]
}

@(export)
build_register_msg_c :: proc "c" (out_len: ^u32, out_data: ^rawptr) {
    context = web_context
    register := game.build_register_msg(game.state.id, game.state)
    out_len^ = u32(len(register))
    out_data^ = &register[0]
}

@(export)
set_socket_ready :: proc "c" () {
    socket_ready = true
}

@(export)
set_peer_rtc_connected :: proc "c" (peer_id: u64) {
    peer_state := &peers[peer_id]
    peer_state.webrtc = .CONNECTED
}

@(export)
process_binary_msg :: proc "c" (data_len: u32, data: [^]u8) {
    context = web_context

    type, sender_id, target_id, payload := game.parse_binary_message(data[:data_len])
    sender_already_registered := sender_id in peers
    if !sender_already_registered {
        peers[sender_id] = {.WAITING, {}}
        peer_state := &peers[sender_id]
    }

    if game.state.id != target_id && target_id != 0 {
        fmt.println("This message is not for me: ", target_id, " (target) x ", game.state.id, " (me)")
        assert(false)
    }
    if sender_id == game.state.id {
        fmt.println("This message is from me: ", target_id, " (target) x ", game.state.id, " (me)")
        assert(false)
    }

    peer_state := &peers[sender_id]

    if type == 1 {
        bytes: []byte = payload[:len(payload)]
        // context.allocator allocated actions
        actions := game.load_from_serialized(bytes, context.allocator)
        if len(actions) > 0 {
            for _, index in peer_state.last_known_actions {
                game.delete_action(&peer_state.last_known_actions[index])
            }
            clear(&peer_state.last_known_actions)
            for &a in actions {
                append(&peer_state.last_known_actions, game.duplicate_action(&a))
            }
            if game.merge_and_redo_actions(game.state, game.tile_map, actions) {
                game.state.needs_sync = true
            }
        }
        if target_id == 0 {
            //TODO(amatej): Only the peer with the highest id should sync,
            //              otherwise when a new peer joins state with a lot
            //              of peers and actions it will get a lot of big messages
            //              with mostly duplicate information.
            fmt.println("Registering: ", sender_id)
            make_webrtc_offer(sender_id)
            peer_state.webrtc = .OFFERED
            game.state.needs_sync = true
        }
    } else if type == 2 {
        if peer_state.webrtc == .WAITING {
            accept_webrtc_offer(sender_id, &payload[0], u32(len(payload)))
            peer_state.webrtc = .ICE
        } else if peer_state.webrtc == .OFFERED {
            accept_webrtc_answer(sender_id, &payload[0], u32(len(payload)))
            peer_state.webrtc = .ICE
        } else if peer_state.webrtc == .ICE {
            add_peer_ice(sender_id, &payload[0], u32(len(payload)))
        }
        return
    }
}

@(export)
paste_image :: proc "c" (data: [^]u8, data_len: i32, width: i32, height: i32) {
    context = web_context
    game.add_background(data, data_len, width, height)
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

    when ODIN_DEBUG {
        mem.tracking_allocator_init(&track, my_allocator)
        context.allocator = mem.tracking_allocator(&track)
    }

    // Since we now use js_wasm32 we should be able to remove this and use
    // context.logger = log.create_console_logger(). However, that one produces
    // extra newlines on web. So it's a bug in that core lib.
    context.logger = create_emscripten_logger()

    web_context = context

    fmt.println("Setting up signaling websocket")
    connect_signaling_websocket()

    //TODO(amatej): load saves
    mount_idbfs()
    game.init(string(path_data[:path_len]), mobile)
}

//TODO(amatej): would it be possible to dump all actions on panic?

@(export)
main_update :: proc "c" () -> bool {
    context = web_context
    game.update()

    if game.state.debug != .OFF {
        p := make(map[u64]bool, allocator = context.temp_allocator)
        for peer, &peer_state in peers {
            p[peer] = peer_state.webrtc == .CONNECTED ? true : false
        }
        game.draw_connections(socket_ready, p)
    }

    if game.state.needs_sync && !game.state.offline {
        if socket_ready {
            for peer_id, &peer_state in peers {
                binary: []u8
                _, to_send := game.find_first_not_matching_action(
                    peer_state.last_known_actions[:],
                    game.state.undo_history[:],
                )
                // send one more action if there is one, so that we can find common parent action (by hash)
                to_send = math.max(0, to_send - 1)
                serialized_actions := game.serialize_actions(game.state.undo_history[to_send:], context.temp_allocator)
                binary = game.build_binary_message(game.state.id, 1, peer_id, serialized_actions)
                send_binary_to_peer(peer_id, &binary[0], u32(len(binary)))
                if len(game.state.undo_history[to_send:]) > 0 {
                    for _, index in peer_state.last_known_actions {
                        game.delete_action(&peer_state.last_known_actions[index])
                    }
                    clear(&peer_state.last_known_actions)
                    append(
                        &peer_state.last_known_actions,
                        game.duplicate_action(&game.state.undo_history[len(game.state.undo_history) - 1]),
                    )
                }
            }
        }
        game.state.needs_sync = false
    }

    free_all(context.temp_allocator)
    return game.state.should_run
}

@(export)
main_end :: proc "c" () {
    context = web_context
    game.shutdown()
    for peer, &peer_state in peers {
        for _, index in peer_state.last_known_actions {
            game.delete_action(&peer_state.last_known_actions[index])
        }
        delete(peer_state.last_known_actions)
    }
    delete(peers)

    when ODIN_DEBUG {
        if len(track.allocation_map) > 0 {
            fmt.eprintf("=== %v allocations not freed: ===\n", len(track.allocation_map))
            for _, entry in track.allocation_map {
                fmt.eprintf("- %v bytes @ %v\n", entry.size, entry.location)
            }
        }
        if len(track.bad_free_array) > 0 {
            fmt.eprintf("=== %v incorrect frees: ===\n", len(track.bad_free_array))
            for entry in track.bad_free_array {
                fmt.eprintf("- %p @ %v\n", entry.memory, entry.location)
            }
        }
        mem.tracking_allocator_destroy(&track)
    }
}

@(export)
web_window_size_changed :: proc "c" (w: c.int, h: c.int) {
    context = web_context
    game.parent_window_size_changed(int(w), int(h))
}
