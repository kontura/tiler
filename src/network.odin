package tiler

import "core:math"


build_binary_message :: proc(my_id: [3]u8, type: u8, target: []u8, payload: []u8) -> []u8 {
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

build_register_msg :: proc(my_id: [3]u8, state: ^GameState) -> []u8 {
    actions_num := math.min(4, len(state.undo_history))
    return build_binary_message(my_id, 1, nil, serialize_actions(state.undo_history[actions_num:], context.temp_allocator))
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
