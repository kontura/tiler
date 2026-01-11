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

init_sync_requested: bool = false
my_allocator: mem.Allocator
when ODIN_DEBUG {
    track: mem.Tracking_Allocator
}

@(export)
build_binary_webrtc_msg_c :: proc "c" (peer_id: u64, msg_len: u32, msg_data: [^]u8, out_len: ^u32, out_data: ^rawptr) {
    context = web_context
    msg := game.build_binary_message(game.state.id, .WEBRTC, peer_id, msg_data[:msg_len])
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
set_socket_ready :: proc "c" (socket_state: u64) {
    game.state.socket_ready = bool(socket_state)
}

@(export)
set_peer_rtc_connected :: proc "c" (peer_id: u64) {
    peer_state := &game.state.peers[peer_id]
    peer_state.webrtc = .CONNECTED
}

@(export)
process_binary_msg :: proc "c" (data_len: u32, data: [^]u8) {
    context = web_context

    type, sender_id, target_id, payload := game.parse_binary_message(data[:data_len])
    sender_already_registered := sender_id in game.state.peers
    if !sender_already_registered {
        game.state.peers[sender_id] = {.WAITING, {}, {}}
        peer_state := &game.state.peers[sender_id]

        if target_id == game.state.room_id {
            fmt.println("Registering: ", sender_id)
            make_webrtc_offer(sender_id)
            peer_state.webrtc = .OFFERED
            binary := game.build_binary_message(game.state.id, .HELLO, sender_id, nil)
            send_binary_to_peer(sender_id, &binary[0], u32(len(binary)))
        }
    }

    if game.state.id != target_id && target_id != game.state.room_id {
        fmt.println("This message is not for me: ", target_id, " (target) x ", game.state.id, " (me)")
        assert(false)
    }
    if sender_id == game.state.id {
        fmt.println("This message is from me: ", target_id, " (target) x ", game.state.id, " (me)")
        assert(false)
    }

    peer_state := &game.state.peers[sender_id]

    if type == .ACTIONS {
        bytes: []byte = payload[:len(payload)]
        // context.allocator allocated actions
        actions := game.load_serialized_actions(bytes, context.allocator)
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
    } else if type == .WEBRTC {
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
    } else if type == .IMAGE_REQUEST {
        requested_img_id := string(payload)
        img, ok := game.state.images[requested_img_id]
        if ok {
            fmt.println("Sending back requested id: ", requested_img_id)
            image_data := game.serialize_image(game.state, requested_img_id, context.temp_allocator)

            s: game.Serializer
            game.serializer_init_writer(&s, allocator = context.temp_allocator)
            game.serialize(&s, &requested_img_id)
            game.serialize(&s, &image_data)

            binary := game.build_binary_message(game.state.id, .IMAGE_ANSWER, sender_id, s.data[:])
            for &msg in game.chunk_binary_message(game.state.id, sender_id, binary, context.temp_allocator) {
                send_binary_to_peer(sender_id, &msg[0], u32(len(msg)))
            }

        } else {
            //TODO(amatej): handle if I don't have the image
        }
    } else if type == .IMAGE_ANSWER {
        s: game.Serializer
        game.serializer_init_reader(&s, payload)
        img_id: string
        game.serialize(&s, &img_id)
        image_data := make([dynamic]u8, allocator = context.temp_allocator)
        game.serialize(&s, &image_data)
        game.save_image(game.state, img_id, image_data[:])

        // If we have a token with matching name, set its texture
        for _, &token in game.state.tokens {
            n := strings.to_lower(token.name, context.temp_allocator)
            fmt.println("Comparing: ", n, " - ", img_id)
            if strings.has_prefix(n, img_id) {
                game.set_texture_based_on_name(game.state, &token)
            }
        }

        delete(img_id)
        delete(image_data)
    } else if type == .CHUNK {
        for byte in payload {
            append(&peer_state.chunks, byte)
        }
        // This is the last chunk
        if len(payload) != game.CHUNK_SIZE {
            process_binary_msg(u32(len(peer_state.chunks)), raw_data(peer_state.chunks))
            clear(&peer_state.chunks)
        }
    } else if type == .HELLO {
        if !init_sync_requested {
            binary := game.build_binary_message(game.state.id, .SYNC_REQUEST, sender_id, nil)
            send_binary_to_peer(sender_id, &binary[0], u32(len(binary)))
            init_sync_requested = true
        }
    } else if type == .SYNC_REQUEST {
        game.state.needs_sync = true
    }
}

@(export)
paste_image :: proc "c" (data: [^]u8, data_len: i32, width: i32, height: i32) {
    context = web_context
    #partial switch game.state.active_tool {
    case .EDIT_TOKEN:
        {
            game.set_selected_token_texture(data, data_len, width, height)
        }
    case:
        {
            game.add_background(data, data_len, width, height)
        }
    }
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

    if !game.state.offline && game.state.socket_ready {
        for author_id, &img_id in game.state.needs_images {
            target_peer := author_id
            if !(author_id in game.state.peers) {
                // Randomly get first peer
                for peer_id, _ in game.state.peers {
                    target_peer = peer_id
                }
            }
            n := strings.to_lower(img_id, context.temp_allocator)

            binary := game.build_binary_message(game.state.id, .IMAGE_REQUEST, target_peer, raw_data(n)[:len(n)])
            send_binary_to_peer(target_peer, &binary[0], u32(len(binary)))
            fmt.println("requesting: ", n , " from: ", target_peer)
            delete(img_id)
        }
        clear(&game.state.needs_images)

        if game.state.needs_sync {
            for peer_id, &peer_state in game.state.peers {
                binary: []u8
                _, to_send := game.find_first_not_matching_action(
                    peer_state.last_known_actions[:],
                    game.state.undo_history[:],
                )
                // send one more action if there is one, so that we can find common parent action (by hash)
                to_send = math.max(0, to_send - 1)
                serialized_actions := game.serialize_actions(game.state.undo_history[to_send:], context.temp_allocator)
                binary = game.build_binary_message(game.state.id, .ACTIONS, peer_id, serialized_actions)
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
            game.state.needs_sync = false
        }
    }

    free_all(context.temp_allocator)
    return game.state.should_run
}

@(export)
main_end :: proc "c" () {
    context = web_context
    game.shutdown()

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
