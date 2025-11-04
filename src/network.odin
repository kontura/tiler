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
    return build_binary_message(my_id, 1, nil, serialize_actions(state.undo_history[actions_num:]))
}
