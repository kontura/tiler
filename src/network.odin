package tiler

import "core:encoding/endian"
import "core:math"
import "core:mem"
import "core:strings"

MESSAGE_TYPE :: enum u8 {
    ACTIONS       = 1,
    WEBRTC        = 2,
    IMAGE_REQUEST = 3,
    IMAGE_ANSWER  = 4,
    CHUNK         = 5,
    HELLO         = 6,
    SYNC_REQUEST  = 7,
}

WEBRTC_STATE :: enum u8 {
    WAITING,
    OFFERED,
    ANSWERED,
    ICE,
    CONNECTED,
}

PeerState :: struct {
    webrtc:             WEBRTC_STATE,
    last_known_actions: [dynamic]Action,
    chunks:             [dynamic]u8,
}

ImageNeeded :: struct {
    img_name:           string,
    // try to get the image from these peers in this order
    peers_to_try:       [dynamic]u64,
    waiting_for_answer: bool,
}

delete_image_needed :: proc(image_neede: ^ImageNeeded) {
    delete(image_neede.img_name)
    delete(image_neede.peers_to_try)
}

delete_peer_state :: proc(peer_state: ^PeerState) {
    for _, index in peer_state.last_known_actions {
        delete_action(&peer_state.last_known_actions[index])
    }
    delete(peer_state.last_known_actions)
    delete(peer_state.chunks)
}

CHUNK_SIZE :: 32000

chunk_binary_message :: proc(id: u64, target: u64, msg: []u8, allocator: mem.Allocator) -> [dynamic][]u8 {
    result := make([dynamic][]u8, allocator = allocator)
    if len(msg) > CHUNK_SIZE {
        for i := 0; i < len(msg); i += CHUNK_SIZE {
            end := i + CHUNK_SIZE > len(msg) ? len(msg) : i + CHUNK_SIZE
            append(&result, build_binary_message(id, .CHUNK, target, msg[i:end]))
        }
    } else {
        append(&result, msg)
    }

    return result
}

build_binary_message :: proc(id: u64, type: MESSAGE_TYPE, target: u64, payload: []u8) -> []u8 {
    msg := make([dynamic]u8, allocator = context.temp_allocator)
    append(&msg, u8(type))
    append(&msg, u8(size_of(id)))
    id := id
    append(&msg, ..mem.ptr_to_bytes(&id))
    append(&msg, u8(size_of(target)))
    target := target
    append(&msg, ..mem.ptr_to_bytes(&target))
    append(&msg, ..payload[:])
    return msg[:]
}

build_register_msg :: proc(my_id: u64, state: ^GameState) -> []u8 {
    actions_num := math.min(4, len(state.undo_history))
    return build_binary_message(
        my_id,
        .ACTIONS,
        state.room_id,
        serialize_actions(state.undo_history[actions_num:], context.temp_allocator),
    )
}

parse_binary_message :: proc(msg: []u8) -> (type: MESSAGE_TYPE, sender, target: u64, payload: []u8) {
    // 0 1 2 3 4 5 6 7 8 9
    // 1 3 a b c 3 d e f x x x
    type = auto_cast (msg[0])
    sender_len := msg[1]
    sender_bytes := msg[2:2 + sender_len]
    ok: bool
    sender, ok = endian.get_u64(sender_bytes, .Little)
    assert(ok)
    target_len := msg[2 + sender_len]
    target_bytes := msg[3 + sender_len:3 + sender_len + target_len]
    target, ok = endian.get_u64(target_bytes, .Little)
    assert(ok)
    payload = msg[3 + sender_len + target_len:]
    return
}

add_request_image :: proc(state: ^GameState, image_id: string, author_id: u64) {
    if len(image_id) > 0 {
        ind: ImageNeeded
        ind.img_name = strings.clone(image_id)
        if author_id in state.peers {
            append(&ind.peers_to_try, author_id)
        }
        for peer_id, _ in state.peers {
            if peer_id != author_id {
                append(&ind.peers_to_try, peer_id)
            }
        }
        append(&state.needs_images, ind)
    }
}
