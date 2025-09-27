package tiler

import "core:fmt"
import "core:testing"

setup :: proc() -> (GameState, TileMap) {
    state: GameState
    tile_map: TileMap
    game_state_init(&state, false, 100, 100, "root")
    tile_map_init(&tile_map, false)

    return state, tile_map
}

teardown :: proc(state: ^GameState, tile_map: ^TileMap) {
    tokens_reset(state)
    delete(state.initiative_to_tokens)
    for id, _ in state.tokens {
        delete_token(&state.tokens[id])
    }
    delete(state.tokens)

    for _, index in state.undo_history {
        delete_action(&state.undo_history[index])
    }
    delete(state.undo_history)

    tilemap_clear(tile_map)
    delete(tile_map.tile_chunks)
}

@(test)
basic_rectangle_test :: proc(t: ^testing.T) {
    state, tile_map := setup()

    temp_action := make_action(.RECTANGLE, context.temp_allocator)
    start_tile: TileMapPosition = {{0, 0}, {0, 0}}
    end_tile: TileMapPosition = {{2, 2}, {0, 0}}
    tooltip := rectangle_tool(start_tile, end_tile, [4]u8{255, 0, 0, 255}, &tile_map, &temp_action)

    testing.expect_value(t, tooltip, "15x15 feet (4.6x4.6 meters)")
    testing.expect_value(t, get_tile(&tile_map, {0, 0}).color, [4]u8{255, 0, 0, 255})
    testing.expect_value(t, get_tile(&tile_map, {2, 2}).color, [4]u8{255, 0, 0, 255})
    testing.expect_value(t, get_tile(&tile_map, {3, 3}).color, [4]u8{77, 77, 77, 255})

    undo_action(&state, &tile_map, &temp_action)

    testing.expect_value(t, get_tile(&tile_map, {0, 0}).color, [4]u8{77, 77, 77, 255})
    testing.expect_value(t, get_tile(&tile_map, {2, 2}).color, [4]u8{77, 77, 77, 255})
    testing.expect_value(t, get_tile(&tile_map, {3, 3}).color, [4]u8{77, 77, 77, 255})

    redo_action(&state, &tile_map, &temp_action)

    testing.expect_value(t, get_tile(&tile_map, {0, 0}).color, [4]u8{255, 0, 0, 255})
    testing.expect_value(t, get_tile(&tile_map, {2, 2}).color, [4]u8{255, 0, 0, 255})
    testing.expect_value(t, get_tile(&tile_map, {3, 3}).color, [4]u8{77, 77, 77, 255})

    // redo on empty state and tile_map to simulate syncing peer
    state2, tile_map2 := setup()
    redo_action(&state2, &tile_map2, &temp_action)
    testing.expect_value(t, get_tile(&tile_map2, {0, 0}).color, [4]u8{255, 0, 0, 255})
    testing.expect_value(t, get_tile(&tile_map2, {2, 2}).color, [4]u8{255, 0, 0, 255})
    testing.expect_value(t, get_tile(&tile_map2, {3, 3}).color, [4]u8{77, 77, 77, 255})
    teardown(&state2, &tile_map2)

    teardown(&state, &tile_map)
}

create_spawn_token_action :: proc(
    state: ^GameState,
    pos: TileMapPosition,
    initiative: [2]i32 = {-1,0},
    allocator := context.allocator,
) -> (
    Action,
    u64,
) {
    action := make_action(.EDIT_TOKEN, allocator)
    id := token_spawn(state, &action, pos, [4]u8{0,0,0,0}, "", initiative)
    return action, id
}

@(test)
basic_token_spawn_test :: proc(t: ^testing.T) {
    state, tile_map := setup()

    pos: TileMapPosition = {{2, 2}, {0, 0}}
    temp_action, token_id := create_spawn_token_action(&state, pos, {-1, 0}, context.temp_allocator)

    testing.expect_value(t, len(state.tokens), 2)
    token := state.tokens[1]
    testing.expect_value(t, token.id, 1)
    testing.expect_value(t, token.position, pos)
    init := token.initiative
    testing.expect_value(t, len(state.initiative_to_tokens), 1)
    testing.expect_value(t, len(state.initiative_to_tokens[init]), 1)
    testing.expect_value(t, state.initiative_to_tokens[init][0], token.id)

    undo_action(&state, &tile_map, &temp_action)

    testing.expect_value(t, len(state.tokens), 2)
    token = state.tokens[1]
    testing.expect_value(t, token.id, 1)
    testing.expect_value(t, token.position, pos)
    testing.expect_value(t, token.alive, false)
    testing.expect_value(t, len(state.initiative_to_tokens), 1)
    testing.expect_value(t, len(state.initiative_to_tokens[init]), 0)

    redo_action(&state, &tile_map, &temp_action)

    testing.expect_value(t, len(state.tokens), 2)
    token = state.tokens[1]
    testing.expect_value(t, token.id, 1)
    testing.expect_value(t, token.position, pos)
    testing.expect_value(t, len(state.initiative_to_tokens), 1)
    testing.expect_value(t, len(state.initiative_to_tokens[init]), 1)
    testing.expect_value(t, state.initiative_to_tokens[init][0], token.id)

    // redo on empty state and tile_map to simulate syncing peer
    state2, tile_map2 := setup()
    redo_action(&state2, &tile_map2, &temp_action)
    testing.expect_value(t, len(state2.tokens), 2)
    token = state2.tokens[1]
    testing.expect_value(t, token.id, 1)
    testing.expect_value(t, token.position, pos)
    testing.expect_value(t, len(state2.initiative_to_tokens), 1)
    testing.expect_value(t, len(state2.initiative_to_tokens[init]), 1)
    testing.expect_value(t, state2.initiative_to_tokens[init][0], token.id)
    teardown(&state2, &tile_map2)

    teardown(&state, &tile_map)
}

@(test)
basic_token_initiative_move_test :: proc(t: ^testing.T) {
    state, tile_map := setup()

    _, token_id := create_spawn_token_action(&state, {{0, 0}, {0, 0}}, {20, 0}, context.temp_allocator)
    token := &(state.tokens[token_id])

    temp_action := make_action(.EDIT_TOKEN_INITIATIVE, context.temp_allocator)
    // 275 ~ init 20, 40 screen pos targers initiative "3"
    move_initiative_token_tool(&state, 275, 40, &temp_action)

    testing.expect_value(t, len(state.tokens), 2)
    testing.expect_value(t, len(state.initiative_to_tokens), 2)
    testing.expect_value(t, token.initiative, 3)
    testing.expect_value(t, len(state.initiative_to_tokens[20]), 0)
    testing.expect_value(t, len(state.initiative_to_tokens[3]), 1)
    testing.expect_value(t, state.initiative_to_tokens[3][0], token.id)

    undo_action(&state, &tile_map, &temp_action)

    testing.expect_value(t, len(state.tokens), 2)
    testing.expect_value(t, len(state.initiative_to_tokens), 2)
    testing.expect_value(t, token.initiative, 20)
    testing.expect_value(t, len(state.initiative_to_tokens[3]), 0)
    testing.expect_value(t, len(state.initiative_to_tokens[20]), 1)
    testing.expect_value(t, state.initiative_to_tokens[20][0], token.id)

    redo_action(&state, &tile_map, &temp_action)

    testing.expect_value(t, len(state.tokens), 2)
    testing.expect_value(t, len(state.initiative_to_tokens), 2)
    testing.expect_value(t, token.initiative, 3)
    testing.expect_value(t, len(state.initiative_to_tokens[20]), 0)
    testing.expect_value(t, len(state.initiative_to_tokens[3]), 1)
    testing.expect_value(t, state.initiative_to_tokens[3][0], token.id)

    // redo on empty state and tile_map to simulate syncing peer
    state2, tile_map2 := setup()
    // this only works because we spawn the tokens in both states with the same id
    _, token_id = create_spawn_token_action(&state2, {{0, 0}, {0, 0}}, {20, 0}, context.temp_allocator)
    token = &(state2.tokens[token_id])
    redo_action(&state2, &tile_map2, &temp_action)
    testing.expect_value(t, len(state2.tokens), 2)
    testing.expect_value(t, len(state2.initiative_to_tokens), 2)
    testing.expect_value(t, token.initiative, 3)
    testing.expect_value(t, len(state2.initiative_to_tokens[20]), 0)
    testing.expect_value(t, len(state2.initiative_to_tokens[3]), 1)
    testing.expect_value(t, state2.initiative_to_tokens[3][0], token.id)
    teardown(&state2, &tile_map2)

    teardown(&state, &tile_map)
}

@(test)
multiple_tokens_initiative_move_test :: proc(t: ^testing.T) {
    state, tile_map := setup()

    spawn_action1, token_id1 := create_spawn_token_action(&state, {{0, 0}, {0, 0}}, {18, 0}, context.temp_allocator)
    append(&state.undo_history, spawn_action1)
    spawn_action2, token_id2 := create_spawn_token_action(&state, {{0, 0}, {0, 0}}, {20, 0}, context.temp_allocator)
    append(&state.undo_history, spawn_action2)
    spawn_action3, token_id3 := create_spawn_token_action(&state, {{0, 0}, {0, 0}}, {22, 0}, context.temp_allocator)
    append(&state.undo_history, spawn_action3)

    temp_action := make_action(.EDIT_TOKEN_INITIATIVE, context.temp_allocator)
    // 260 screen pos targers initiative "18"
    // 40 screen pos targers initiative "3"
    // these numbers are chosen by empirically
    move_initiative_token_tool(&state, 260, 40, &temp_action)
    append(&state.undo_history, temp_action)

    testing.expect_value(t, len(state.tokens), 4)
    testing.expect_value(t, len(state.initiative_to_tokens), 4)
    testing.expect_value(t, len(state.initiative_to_tokens[18]), 0)
    testing.expect_value(t, len(state.initiative_to_tokens[20]), 1)
    testing.expect_value(t, len(state.initiative_to_tokens[22]), 1)
    testing.expect_value(t, len(state.initiative_to_tokens[3]), 1)
    testing.expect_value(t, state.initiative_to_tokens[3][0], token_id1)
    testing.expect_value(t, state.initiative_to_tokens[20][0], token_id2)
    testing.expect_value(t, state.initiative_to_tokens[22][0], token_id3)
    testing.expect_value(t, len(temp_action.token_initiative_history), 1)
    testing.expect_value(t, temp_action.token_initiative_history[token_id1], [2]i32{15, 0})

    temp_action = make_action(.EDIT_TOKEN_INITIATIVE, context.temp_allocator)
    // 290 screen pos targers initiative "20"
    // 69 screen pos targers initiative "3", after token_id1
    move_initiative_token_tool(&state, 290, 69, &temp_action)
    append(&state.undo_history, temp_action)

    testing.expect_value(t, len(state.tokens), 4)
    testing.expect_value(t, len(state.initiative_to_tokens), 4)
    testing.expect_value(t, len(state.initiative_to_tokens[18]), 0)
    testing.expect_value(t, len(state.initiative_to_tokens[20]), 0)
    testing.expect_value(t, len(state.initiative_to_tokens[22]), 1)
    testing.expect_value(t, len(state.initiative_to_tokens[3]), 2)
    testing.expect_value(t, state.initiative_to_tokens[3][0], token_id1)
    testing.expect_value(t, state.initiative_to_tokens[3][1], token_id2)
    testing.expect_value(t, state.initiative_to_tokens[22][0], token_id3)
    testing.expect_value(t, len(temp_action.token_initiative_history), 1)
    testing.expect_value(t, temp_action.token_initiative_history[token_id2], [2]i32{17, -1})

    temp_action = make_action(.EDIT_TOKEN_INITIATIVE, context.temp_allocator)
    // 345 screen pos targers initiative "22"
    // 103 screen pos targers initiative "3", after token_id2
    move_initiative_token_tool(&state, 345, 103, &temp_action)
    append(&state.undo_history, temp_action)

    testing.expect_value(t, len(state.tokens), 4)
    testing.expect_value(t, len(state.initiative_to_tokens), 4)
    testing.expect_value(t, len(state.initiative_to_tokens[18]), 0)
    testing.expect_value(t, len(state.initiative_to_tokens[20]), 0)
    testing.expect_value(t, len(state.initiative_to_tokens[22]), 0)
    testing.expect_value(t, len(state.initiative_to_tokens[3]), 3)
    testing.expect_value(t, state.initiative_to_tokens[3][0], token_id1)
    testing.expect_value(t, state.initiative_to_tokens[3][1], token_id2)
    testing.expect_value(t, state.initiative_to_tokens[3][2], token_id3)
    testing.expect_value(t, len(temp_action.token_initiative_history), 1)
    testing.expect_value(t, temp_action.token_initiative_history[token_id3], [2]i32{19, -2})

    state2, tile_map2 := setup()
    redo_unmatched_actions(&state2, &tile_map2, state.undo_history[:])
    testing.expect_value(t, len(state2.tokens), 4)
    testing.expect_value(t, len(state2.initiative_to_tokens), 4)
    testing.expect_value(t, len(state2.initiative_to_tokens[18]), 0)
    testing.expect_value(t, len(state2.initiative_to_tokens[20]), 0)
    testing.expect_value(t, len(state2.initiative_to_tokens[22]), 0)
    testing.expect_value(t, len(state2.initiative_to_tokens[3]), 3)
    testing.expect_value(t, state2.initiative_to_tokens[3][0], token_id1)
    testing.expect_value(t, state2.initiative_to_tokens[3][1], token_id2)
    testing.expect_value(t, state2.initiative_to_tokens[3][2], token_id3)
    teardown(&state2, &tile_map2)

    teardown(&state, &tile_map)
}

@(test)
redo_unmatched_actions_test :: proc(t: ^testing.T) {
    state, tile_map := setup()

    action := make_action(.RECTANGLE)
    action.hash[0] = 1
    start_tile: TileMapPosition = {{0, 0}, {0, 0}}
    end_tile: TileMapPosition = {{2, 2}, {0, 0}}
    // perform for the first time
    rectangle_tool(start_tile, end_tile, [4]u8{255, 0, 0, 155}, &tile_map, &action)

    // perform for the second time since state.undo_history is empty
    redo_unmatched_actions(&state, &tile_map, {action})

    testing.expect_value(t, get_tile(&tile_map, {0, 0}).color, [4]u8{227, 11, 11, 255})
    testing.expect_value(t, get_tile(&tile_map, {2, 2}).color, [4]u8{227, 11, 11, 255})
    testing.expect_value(t, get_tile(&tile_map, {3, 3}).color, [4]u8{77, 77, 77, 255})

    append(&state.undo_history, action)
    // don't perfrom because undo history has the action
    redo_unmatched_actions(&state, &tile_map, {action})

    testing.expect_value(t, get_tile(&tile_map, {0, 0}).color, [4]u8{227, 11, 11, 255})
    testing.expect_value(t, get_tile(&tile_map, {2, 2}).color, [4]u8{227, 11, 11, 255})
    testing.expect_value(t, get_tile(&tile_map, {3, 3}).color, [4]u8{77, 77, 77, 255})

    action2 := action
    action2.hash[0] = 2
    redo_action(&state, &tile_map, &action2)
    // do the one extra unmatching action2
    redo_unmatched_actions(&state, &tile_map, {action, action2})

    testing.expect_value(t, get_tile(&tile_map, {0, 0}).color, [4]u8{250, 1, 1, 255})
    testing.expect_value(t, get_tile(&tile_map, {2, 2}).color, [4]u8{250, 1, 1, 255})
    testing.expect_value(t, get_tile(&tile_map, {3, 3}).color, [4]u8{77, 77, 77, 255})

    append(&state.undo_history, action2)
    // don't perfrom because undo history has both actions
    redo_unmatched_actions(&state, &tile_map, {action, action2})

    testing.expect_value(t, get_tile(&tile_map, {0, 0}).color, [4]u8{250, 1, 1, 255})
    testing.expect_value(t, get_tile(&tile_map, {2, 2}).color, [4]u8{250, 1, 1, 255})
    testing.expect_value(t, get_tile(&tile_map, {3, 3}).color, [4]u8{77, 77, 77, 255})

    // redo on empty state and tile_map to simulate syncing peer (does the action twice)
    state2, tile_map2 := setup()
    redo_unmatched_actions(&state2, &tile_map2, {action, action2})
    testing.expect_value(t, get_tile(&tile_map2, {0, 0}).color, [4]u8{227, 11, 11, 255})
    testing.expect_value(t, get_tile(&tile_map2, {2, 2}).color, [4]u8{227, 11, 11, 255})
    testing.expect_value(t, get_tile(&tile_map2, {3, 3}).color, [4]u8{77, 77, 77, 255})
    teardown(&state2, &tile_map2)

    // pop the action2 because it is a shallow clone of action1, this avoids double free
    pop(&state.undo_history)
    teardown(&state, &tile_map)
}

@(test)
multiple_tokens_initiative_moves_test :: proc(t: ^testing.T) {
    state, tile_map := setup()

    spawn_action1, token_id1 := create_spawn_token_action(&state, {{0, 0}, {0, 0}}, {3, 0}, context.temp_allocator)
    append(&state.undo_history, spawn_action1)
    spawn_action2, token_id2 := create_spawn_token_action(&state, {{0, 0}, {0, 0}}, {3, 0}, context.temp_allocator)
    append(&state.undo_history, spawn_action2)

    testing.expect_value(t, len(state.initiative_to_tokens), 1)
    testing.expect_value(t, len(state.initiative_to_tokens[3]), 2)
    testing.expect_value(t, state.initiative_to_tokens[3][0], token_id2)
    testing.expect_value(t, state.initiative_to_tokens[3][1], token_id1)

    temp_action := make_action(.EDIT_TOKEN_INITIATIVE, context.temp_allocator)
    // 40 screen pos targers initiative "3"
    // 230 screen pos targers initiative "13"
    // these numbers are chosen by empirically
    move_initiative_token_tool(&state, 40, 230, &temp_action)
    append(&state.undo_history, temp_action)

    testing.expect_value(t, len(state.initiative_to_tokens), 2)
    testing.expect_value(t, len(state.initiative_to_tokens[3]), 1)
    testing.expect_value(t, len(state.initiative_to_tokens[13]), 1)
    testing.expect_value(t, state.initiative_to_tokens[3][0], token_id1)
    testing.expect_value(t, state.initiative_to_tokens[13][0], token_id2)
    testing.expect_value(t, len(temp_action.token_initiative_history), 1)
    testing.expect_value(t, temp_action.token_initiative_history[token_id2], [2]i32{-10, 0})

    temp_action = make_action(.EDIT_TOKEN_INITIATIVE, context.temp_allocator)
    // 220 screen pos targers initiative "13"
    move_initiative_token_tool(&state, 40, 220, &temp_action)
    append(&state.undo_history, temp_action)

    testing.expect_value(t, len(state.initiative_to_tokens), 2)
    testing.expect_value(t, len(state.initiative_to_tokens[13]), 2)
    testing.expect_value(t, len(state.initiative_to_tokens[3]), 0)
    testing.expect_value(t, state.initiative_to_tokens[13][0], token_id2)
    testing.expect_value(t, state.initiative_to_tokens[13][1], token_id1)
    testing.expect_value(t, len(temp_action.token_initiative_history), 1)
    testing.expect_value(t, temp_action.token_initiative_history[token_id1], [2]i32{-10, -1})

    temp_action = make_action(.EDIT_TOKEN_INITIATIVE, context.temp_allocator)
    // 351 screen pos targers initiative "22"
    move_initiative_token_tool(&state, 200, 351, &temp_action)
    append(&state.undo_history, temp_action)

    testing.expect_value(t, len(state.initiative_to_tokens), 3)
    testing.expect_value(t, len(state.initiative_to_tokens[3]), 0)
    testing.expect_value(t, len(state.initiative_to_tokens[13]), 1)
    testing.expect_value(t, len(state.initiative_to_tokens[22]), 1)
    testing.expect_value(t, state.initiative_to_tokens[13][0], token_id1)
    testing.expect_value(t, state.initiative_to_tokens[22][0], token_id2)
    testing.expect_value(t, len(temp_action.token_initiative_history), 1)
    testing.expect_value(t, temp_action.token_initiative_history[token_id2], [2]i32{-9, 0})

    state2, tile_map2 := setup()
    redo_unmatched_actions(&state2, &tile_map2, state.undo_history[:])
    testing.expect_value(t, len(state2.initiative_to_tokens), 3)
    testing.expect_value(t, len(state2.initiative_to_tokens[3]), 0)
    testing.expect_value(t, len(state2.initiative_to_tokens[13]), 1)
    testing.expect_value(t, len(state2.initiative_to_tokens[22]), 1)
    testing.expect_value(t, state2.initiative_to_tokens[13][0], token_id1)
    testing.expect_value(t, state2.initiative_to_tokens[22][0], token_id2)
    teardown(&state2, &tile_map2)

    teardown(&state, &tile_map)
}

@(test)
splice_dynamic_arrays_of_actions_test :: proc(t: ^testing.T) {
    a: [dynamic]Action
    temp_action := make_action(.EDIT_TOKEN_INITIATIVE, context.temp_allocator)
    append(&a, temp_action)
    temp_action = make_action(.EDIT_TOKEN_INITIATIVE, context.temp_allocator)
    append(&a, temp_action)

    b: [dynamic]Action
    temp_action = make_action(.MOVE_TOKEN, context.temp_allocator)
    append(&b, temp_action)
    temp_action = make_action(.MOVE_TOKEN, context.temp_allocator)
    append(&b, temp_action)

    splice_dynamic_arrays_of_actions(&a, &b, 1, 1)
    testing.expect_value(t, len(a), 2)
    testing.expect_value(t, a[0].tool, Tool.EDIT_TOKEN_INITIATIVE)
    testing.expect_value(t, a[1].tool, Tool.MOVE_TOKEN)

    for _, i in a {
        delete_action(&a[i])
    }
    delete(a)
}

@(test)
splice_dynamic_arrays_of_actions_test2 :: proc(t: ^testing.T) {
    a: [dynamic]Action
    temp_action := make_action(.EDIT_TOKEN_INITIATIVE, context.temp_allocator)
    append(&a, temp_action)
    temp_action = make_action(.EDIT_TOKEN_INITIATIVE, context.temp_allocator)
    append(&a, temp_action)

    b: [dynamic]Action
    temp_action = make_action(.MOVE_TOKEN, context.temp_allocator)
    append(&b, temp_action)
    temp_action = make_action(.MOVE_TOKEN, context.temp_allocator)
    append(&b, temp_action)

    splice_dynamic_arrays_of_actions(&a, &b, 0, 2)
    testing.expect_value(t, len(a), 4)
    testing.expect_value(t, a[0].tool, Tool.EDIT_TOKEN_INITIATIVE)
    testing.expect_value(t, a[1].tool, Tool.EDIT_TOKEN_INITIATIVE)
    testing.expect_value(t, a[2].tool, Tool.MOVE_TOKEN)
    testing.expect_value(t, a[3].tool, Tool.MOVE_TOKEN)

    for _, i in a {
        delete_action(&a[i])
    }
    delete(a)
}

@(test)
splice_dynamic_arrays_of_actions_test3 :: proc(t: ^testing.T) {
    a: [dynamic]Action
    temp_action := make_action(.EDIT_TOKEN_INITIATIVE, context.temp_allocator)
    append(&a, temp_action)
    temp_action = make_action(.BRUSH, context.temp_allocator)
    append(&a, temp_action)
    temp_action = make_action(.CIRCLE, context.temp_allocator)
    append(&a, temp_action)

    b: [dynamic]Action
    temp_action = make_action(.MOVE_TOKEN, context.temp_allocator)
    append(&b, temp_action)
    temp_action = make_action(.CONE, context.temp_allocator)
    append(&b, temp_action)

    splice_dynamic_arrays_of_actions(&a, &b, 3, 1)
    testing.expect_value(t, len(a), 1)
    testing.expect_value(t, a[0].tool, Tool.CONE)

    for _, i in a {
        delete_action(&a[i])
    }
    delete(a)
}

@(test)
splice_dynamic_arrays_of_actions_test4 :: proc(t: ^testing.T) {
    a: [dynamic]Action
    temp_action := make_action(.EDIT_TOKEN_INITIATIVE, context.temp_allocator)
    append(&a, temp_action)
    temp_action = make_action(.BRUSH, context.temp_allocator)
    append(&a, temp_action)
    temp_action = make_action(.CIRCLE, context.temp_allocator)
    append(&a, temp_action)

    b: [dynamic]Action
    temp_action = make_action(.MOVE_TOKEN, context.temp_allocator)
    append(&b, temp_action)
    temp_action = make_action(.CONE, context.temp_allocator)
    append(&b, temp_action)

    splice_dynamic_arrays_of_actions(&a, &b, 0, 2)
    testing.expect_value(t, len(a), 5)
    testing.expect_value(t, a[0].tool, Tool.EDIT_TOKEN_INITIATIVE)
    testing.expect_value(t, a[1].tool, Tool.BRUSH)
    testing.expect_value(t, a[2].tool, Tool.CIRCLE)
    testing.expect_value(t, a[3].tool, Tool.MOVE_TOKEN)
    testing.expect_value(t, a[4].tool, Tool.CONE)

    for _, i in a {
        delete_action(&a[i])
    }
    delete(a)
}
