package tiler

import "core:fmt"
import "core:testing"

setup :: proc(id: u64 = 1) -> (GameState, TileMap) {
    my_state: GameState
    my_tile_map: TileMap
    game_state_init(&my_state, false, 100, 100, "root")
    my_state.id = id
    tile_map_init(&my_tile_map, false)

    return my_state, my_tile_map
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

duplicate_actions :: proc(orig: []Action) -> [dynamic]Action {
    res: [dynamic]Action

    for &a in orig {
        append(&res, duplicate_action(&a))
    }

    return res
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
    initiative: [2]i32 = {-1, 0},
    allocator := context.allocator,
) -> (
    Action,
    u64,
) {
    action := make_action(.EDIT_TOKEN_LIFE, allocator)
    id := token_spawn(state, &action, pos, [4]u8{0, 0, 0, 0}, "", initiative)
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
    finish_last_undo_history_action(&state)
    spawn_action2, token_id2 := create_spawn_token_action(&state, {{0, 0}, {0, 0}}, {20, 0}, context.temp_allocator)
    append(&state.undo_history, spawn_action2)
    finish_last_undo_history_action(&state)
    spawn_action3, token_id3 := create_spawn_token_action(&state, {{0, 0}, {0, 0}}, {22, 0}, context.temp_allocator)
    append(&state.undo_history, spawn_action3)
    finish_last_undo_history_action(&state)

    temp_action := make_action(.EDIT_TOKEN_INITIATIVE, context.temp_allocator)
    // 260 screen pos targers initiative "18"
    // 40 screen pos targers initiative "3"
    // these numbers are chosen by empirically
    move_initiative_token_tool(&state, 260, 40, &temp_action)
    append(&state.undo_history, temp_action)
    finish_last_undo_history_action(&state)

    testing.expect_value(t, len(state.tokens), 4)
    testing.expect_value(t, len(state.initiative_to_tokens), 4)
    testing.expect_value(t, len(state.initiative_to_tokens[18]), 0)
    testing.expect_value(t, len(state.initiative_to_tokens[20]), 1)
    testing.expect_value(t, len(state.initiative_to_tokens[22]), 1)
    testing.expect_value(t, len(state.initiative_to_tokens[3]), 1)
    testing.expect_value(t, state.initiative_to_tokens[3][0], token_id1)
    testing.expect_value(t, state.initiative_to_tokens[20][0], token_id2)
    testing.expect_value(t, state.initiative_to_tokens[22][0], token_id3)
    testing.expect_value(t, temp_action.token_id, token_id1)
    testing.expect_value(t, temp_action.token_initiative_end, [2]i32{3, 0})

    temp_action = make_action(.EDIT_TOKEN_INITIATIVE, context.temp_allocator)
    // 290 screen pos targers initiative "20"
    // 69 screen pos targers initiative "3", after token_id1
    move_initiative_token_tool(&state, 290, 69, &temp_action)
    append(&state.undo_history, temp_action)
    finish_last_undo_history_action(&state)

    testing.expect_value(t, len(state.tokens), 4)
    testing.expect_value(t, len(state.initiative_to_tokens), 4)
    testing.expect_value(t, len(state.initiative_to_tokens[18]), 0)
    testing.expect_value(t, len(state.initiative_to_tokens[20]), 0)
    testing.expect_value(t, len(state.initiative_to_tokens[22]), 1)
    testing.expect_value(t, len(state.initiative_to_tokens[3]), 2)
    testing.expect_value(t, state.initiative_to_tokens[3][0], token_id1)
    testing.expect_value(t, state.initiative_to_tokens[3][1], token_id2)
    testing.expect_value(t, state.initiative_to_tokens[22][0], token_id3)
    testing.expect_value(t, temp_action.token_id, token_id2)
    testing.expect_value(t, temp_action.token_initiative_end, [2]i32{3, 1})

    temp_action = make_action(.EDIT_TOKEN_INITIATIVE, context.temp_allocator)
    // 345 screen pos targers initiative "22"
    // 103 screen pos targers initiative "3", after token_id2
    move_initiative_token_tool(&state, 345, 103, &temp_action)
    append(&state.undo_history, temp_action)
    finish_last_undo_history_action(&state)

    testing.expect_value(t, len(state.tokens), 4)
    testing.expect_value(t, len(state.initiative_to_tokens), 4)
    testing.expect_value(t, len(state.initiative_to_tokens[18]), 0)
    testing.expect_value(t, len(state.initiative_to_tokens[20]), 0)
    testing.expect_value(t, len(state.initiative_to_tokens[22]), 0)
    testing.expect_value(t, len(state.initiative_to_tokens[3]), 3)
    testing.expect_value(t, state.initiative_to_tokens[3][0], token_id1)
    testing.expect_value(t, state.initiative_to_tokens[3][1], token_id2)
    testing.expect_value(t, state.initiative_to_tokens[3][2], token_id3)
    testing.expect_value(t, temp_action.token_id, token_id3)
    testing.expect_value(t, temp_action.token_initiative_end, [2]i32{3, 2})

    state2, tile_map2 := setup()
    testing.expect_value(
        t,
        merge_and_redo_actions(&state2, &tile_map2, duplicate_actions(state.undo_history[:])),
        false,
    )
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
merge_and_redo_actions_duplicate :: proc(t: ^testing.T) {
    state, tile_map := setup()

    action := make_action(.RECTANGLE)
    start_tile: TileMapPosition = {{0, 0}, {0, 0}}
    end_tile: TileMapPosition = {{2, 2}, {0, 0}}
    rectangle_tool(start_tile, end_tile, [4]u8{255, 0, 0, 155}, &tile_map, &action)

    testing.expect_value(t, get_tile(&tile_map, {0, 0}).color, [4]u8{185, 30, 30, 255})
    testing.expect_value(t, get_tile(&tile_map, {2, 2}).color, [4]u8{185, 30, 30, 255})
    testing.expect_value(t, get_tile(&tile_map, {3, 3}).color, [4]u8{77, 77, 77, 255})

    append(&state.undo_history, action)
    finish_last_undo_history_action(&state)

    new_actions: [dynamic]Action
    append(&new_actions, duplicate_action(&state.undo_history[0]))

    // Don't perfrom because undo history has hash and authors_index and author_id identical action
    testing.expect_value(t, merge_and_redo_actions(&state, &tile_map, new_actions), false)

    testing.expect_value(t, len(state.undo_history), 1)
    testing.expect_value(t, get_tile(&tile_map, {0, 0}).color, [4]u8{185, 30, 30, 255})
    testing.expect_value(t, get_tile(&tile_map, {2, 2}).color, [4]u8{185, 30, 30, 255})
    testing.expect_value(t, get_tile(&tile_map, {3, 3}).color, [4]u8{77, 77, 77, 255})

    teardown(&state, &tile_map)
}

@(test)
merge_and_redo_actions_duplicate_with_different_hash :: proc(t: ^testing.T) {
    state, tile_map := setup()

    action := make_action(.RECTANGLE)
    action.hash = 1
    start_tile: TileMapPosition = {{0, 0}, {0, 0}}
    end_tile: TileMapPosition = {{2, 2}, {0, 0}}
    rectangle_tool(start_tile, end_tile, [4]u8{255, 0, 0, 155}, &tile_map, &action)

    testing.expect_value(t, get_tile(&tile_map, {0, 0}).color, [4]u8{185, 30, 30, 255})
    testing.expect_value(t, get_tile(&tile_map, {2, 2}).color, [4]u8{185, 30, 30, 255})
    testing.expect_value(t, get_tile(&tile_map, {3, 3}).color, [4]u8{77, 77, 77, 255})

    append(&state.undo_history, action)
    finish_last_undo_history_action(&state)

    new_actions: [dynamic]Action
    append(&new_actions, duplicate_action(&state.undo_history[0]))
    new_actions[0].hash = 1

    // don't merge and perfrom because undo history has identical action (same author, same authors_index)
    merge_and_redo_actions(&state, &tile_map, new_actions)

    testing.expect_value(t, len(state.undo_history), 1)
    testing.expect_value(t, get_tile(&tile_map, {0, 0}).color, [4]u8{185, 30, 30, 255})
    testing.expect_value(t, get_tile(&tile_map, {2, 2}).color, [4]u8{185, 30, 30, 255})
    testing.expect_value(t, get_tile(&tile_map, {3, 3}).color, [4]u8{77, 77, 77, 255})

    teardown(&state, &tile_map)
}

@(test)
multiple_tokens_initiative_moves_test :: proc(t: ^testing.T) {
    state, tile_map := setup()

    spawn_action1, token_id1 := create_spawn_token_action(&state, {{0, 0}, {0, 0}}, {3, 0}, context.temp_allocator)
    append(&state.undo_history, spawn_action1)
    finish_last_undo_history_action(&state)
    spawn_action2, token_id2 := create_spawn_token_action(&state, {{0, 0}, {0, 0}}, {3, 0}, context.temp_allocator)
    append(&state.undo_history, spawn_action2)
    finish_last_undo_history_action(&state)

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
    finish_last_undo_history_action(&state)

    testing.expect_value(t, len(state.initiative_to_tokens), 2)
    testing.expect_value(t, len(state.initiative_to_tokens[3]), 1)
    testing.expect_value(t, len(state.initiative_to_tokens[13]), 1)
    testing.expect_value(t, state.initiative_to_tokens[3][0], token_id1)
    testing.expect_value(t, state.initiative_to_tokens[13][0], token_id2)
    testing.expect_value(t, temp_action.token_id, token_id2)
    testing.expect_value(t, temp_action.token_initiative_end, [2]i32{13, 0})

    temp_action = make_action(.EDIT_TOKEN_INITIATIVE, context.temp_allocator)
    // 220 screen pos targers initiative "13"
    move_initiative_token_tool(&state, 40, 220, &temp_action)
    append(&state.undo_history, temp_action)
    finish_last_undo_history_action(&state)

    testing.expect_value(t, len(state.initiative_to_tokens), 2)
    testing.expect_value(t, len(state.initiative_to_tokens[13]), 2)
    testing.expect_value(t, len(state.initiative_to_tokens[3]), 0)
    testing.expect_value(t, state.initiative_to_tokens[13][0], token_id2)
    testing.expect_value(t, state.initiative_to_tokens[13][1], token_id1)
    testing.expect_value(t, temp_action.token_id, token_id1)
    testing.expect_value(t, temp_action.token_initiative_end, [2]i32{13, 1})

    temp_action = make_action(.EDIT_TOKEN_INITIATIVE, context.temp_allocator)
    // 351 screen pos targers initiative "22"
    move_initiative_token_tool(&state, 200, 351, &temp_action)
    append(&state.undo_history, temp_action)
    finish_last_undo_history_action(&state)

    testing.expect_value(t, len(state.initiative_to_tokens), 3)
    testing.expect_value(t, len(state.initiative_to_tokens[3]), 0)
    testing.expect_value(t, len(state.initiative_to_tokens[13]), 1)
    testing.expect_value(t, len(state.initiative_to_tokens[22]), 1)
    testing.expect_value(t, state.initiative_to_tokens[13][0], token_id1)
    testing.expect_value(t, state.initiative_to_tokens[22][0], token_id2)
    testing.expect_value(t, temp_action.token_id, token_id2)
    testing.expect_value(t, temp_action.token_initiative_end, [2]i32{22, 0})

    state2, tile_map2 := setup()
    testing.expect_value(
        t,
        merge_and_redo_actions(&state2, &tile_map2, duplicate_actions(state.undo_history[:])),
        false,
    )
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
find_common_parent_action_test :: proc(t: ^testing.T) {
    a: [dynamic]Action
    temp_action := make_action(.EDIT_TOKEN_POSITION, context.temp_allocator)
    temp_action.hash = 1
    append(&a, temp_action)
    temp_action = make_action(.BRUSH, context.temp_allocator)
    temp_action.hash = 2
    append(&a, temp_action)
    temp_action = make_action(.CIRCLE, context.temp_allocator)
    temp_action.hash = 3
    append(&a, temp_action)

    b: [dynamic]Action
    temp_action = make_action(.EDIT_TOKEN_POSITION, context.temp_allocator)
    temp_action.hash = 1
    append(&b, temp_action)
    temp_action = make_action(.CONE, context.temp_allocator)
    temp_action.hash = 2
    append(&b, temp_action)

    index_a, index_b := find_first_not_matching_action(a[:], b[:])
    testing.expect_value(t, index_a, 2)
    testing.expect_value(t, index_b, 2)

    delete(a)
    delete(b)
}

@(test)
find_common_parent_action_test2 :: proc(t: ^testing.T) {
    a: [dynamic]Action
    temp_action := make_action(.EDIT_TOKEN_POSITION, context.temp_allocator)
    temp_action.hash = 1
    append(&a, temp_action)
    temp_action = make_action(.BRUSH, context.temp_allocator)
    temp_action.hash = 2
    append(&a, temp_action)
    temp_action = make_action(.CIRCLE, context.temp_allocator)
    temp_action.hash = 3
    append(&a, temp_action)
    temp_action = make_action(.CIRCLE, context.temp_allocator)
    temp_action.hash = 4
    append(&a, temp_action)
    temp_action = make_action(.CIRCLE, context.temp_allocator)
    temp_action.hash = 5
    append(&a, temp_action)

    b: [dynamic]Action
    temp_action = make_action(.EDIT_TOKEN_POSITION, context.temp_allocator)
    temp_action.hash = 1
    append(&b, temp_action)
    temp_action = make_action(.BRUSH, context.temp_allocator)
    temp_action.hash = 2
    append(&b, temp_action)
    temp_action = make_action(.CIRCLE, context.temp_allocator)
    temp_action.hash = 3
    append(&b, temp_action)

    index_a, index_b := find_first_not_matching_action(a[:], b[:])
    testing.expect_value(t, index_a, 3)
    testing.expect_value(t, index_b, 3)

    delete(a)
    delete(b)
}

@(test)
inject_action_test :: proc(t: ^testing.T) {
    a: [dynamic]Action
    temp_action := make_action(.EDIT_TOKEN_POSITION, context.temp_allocator)
    temp_action.authors_index = 10
    temp_action.author_id = 1
    append(&a, temp_action)
    temp_action = make_action(.BRUSH, context.temp_allocator)
    temp_action.authors_index = 20
    temp_action.author_id = 1
    append(&a, temp_action)
    temp_action = make_action(.CIRCLE, context.temp_allocator)
    temp_action.authors_index = 30
    temp_action.author_id = 1
    append(&a, temp_action)
    temp_action = make_action(.CIRCLE, context.temp_allocator)
    temp_action.authors_index = 40
    temp_action.author_id = 1
    append(&a, temp_action)
    temp_action = make_action(.CIRCLE, context.temp_allocator)
    temp_action.authors_index = 50
    temp_action.author_id = 1
    append(&a, temp_action)

    temp_action = make_action(.EDIT_TOKEN_POSITION, context.temp_allocator)
    temp_action.authors_index = 23
    temp_action.author_id = 1

    inject_action(&a, 0, &temp_action)
    testing.expect_value(t, len(a), 6)
    testing.expect_value(t, a[2].authors_index, 23)

    temp_action = make_action(.RECTANGLE, context.temp_allocator)
    temp_action.authors_index = 23
    temp_action.author_id = 4

    inject_action(&a, 0, &temp_action)
    testing.expect_value(t, len(a), 7)
    testing.expect_value(t, a[2].authors_index, 23)
    testing.expect_value(t, a[2].author_id, 1)
    testing.expect_value(t, a[3].authors_index, 23)
    testing.expect_value(t, a[3].author_id, 4)

    delete(a)
}

@(test)
merge_and_redo_single_action_test :: proc(t: ^testing.T) {
    state, tile_map := setup()

    spawn_action1, token_id := create_spawn_token_action(&state, {{0, 0}, {0, 0}}, {18, 0}, context.temp_allocator)
    token := &state.tokens[token_id]
    append(&state.undo_history, spawn_action1)
    finish_last_undo_history_action(&state)
    testing.expect_value(t, token.position.abs_tile, [2]u32{0, 0})
    testing.expect_value(t, len(state.initiative_to_tokens), 1)
    testing.expect_value(t, len(state.initiative_to_tokens[token.initiative]), 1)

    actions: [dynamic]Action
    append(&actions, state.undo_history[len(state.undo_history) - 1])
    testing.expect_value(t, merge_and_redo_actions(&state, &tile_map, actions), false)

    testing.expect_value(t, len(state.undo_history), 1)
    testing.expect_value(t, len(state.initiative_to_tokens), 1)
    testing.expect_value(t, len(state.initiative_to_tokens[token.initiative]), 1)

    teardown(&state, &tile_map)
}

@(test)
merge_and_redo_actions_test :: proc(t: ^testing.T) {
    state, tile_map := setup()

    spawn_action1, token_id := create_spawn_token_action(&state, {{0, 0}, {0, 0}}, {18, 0}, context.temp_allocator)
    spawn_action1.hash = 1
    spawn_action1.authors_index = 1
    spawn_action1.author_id = 1
    token := &state.tokens[token_id]
    append(&state.undo_history, spawn_action1)
    testing.expect_value(t, token.position.abs_tile, [2]u32{0, 0})

    append(&state.undo_history, make_action(.EDIT_TOKEN_POSITION))
    action2: ^Action = &state.undo_history[len(state.undo_history) - 1]
    action2.hash = 2
    action2.authors_index = 2
    action2.author_id = 1
    move_token_tool(&state, token, &tile_map, {20, 20}, action2, false)
    testing.expect_value(t, token.position.abs_tile, [2]u32{99, 99})

    append(&state.undo_history, make_action(.EDIT_TOKEN_POSITION))
    action3 := &state.undo_history[len(state.undo_history) - 1]
    action3.hash = 3
    action3.authors_index = 3
    action3.author_id = 1
    move_token_tool(&state, token, &tile_map, {200, 200}, action3, false)
    testing.expect_value(t, token.position.abs_tile, [2]u32{105, 105})

    append(&state.undo_history, make_action(.EDIT_TOKEN_POSITION))
    action4 := &state.undo_history[len(state.undo_history) - 1]
    action4.hash = 4
    action4.authors_index = 4
    action4.author_id = 1
    move_token_tool(&state, token, &tile_map, {300, 300}, action4, false)
    testing.expect_value(t, token.position.abs_tile, [2]u32{108, 108})

    new_actions: [dynamic]Action
    append(&new_actions, duplicate_action(action3))

    action1 := make_action(.EDIT_TOKEN_POSITION)
    action1.hash = 5
    action1.authors_index = 5
    action1.author_id = 2
    action1.token_id = token_id
    action1.start = {{105, 105}, {0, 0}}
    action1.end = {{17, 17}, {0, 0}}
    append(&new_actions, action1)

    testing.expect_value(t, merge_and_redo_actions(&state, &tile_map, new_actions), true)

    testing.expect_value(t, len(state.undo_history), 5)
    testing.expect_value(t, state.undo_history[0].authors_index, 1)
    testing.expect_value(t, state.undo_history[1].authors_index, 2)
    testing.expect_value(t, state.undo_history[2].authors_index, 3)
    testing.expect_value(t, state.undo_history[3].authors_index, 4)
    testing.expect_value(t, state.undo_history[4].authors_index, 5)

    testing.expect_value(t, token.position.abs_tile, [2]u32{17, 17})

    teardown(&state, &tile_map)
}

@(test)
merge_and_redo_actions_test_got_only_newer :: proc(t: ^testing.T) {
    state, tile_map := setup()

    spawn_action1, token_id := create_spawn_token_action(&state, {{0, 0}, {0, 0}}, {18, 0}, context.temp_allocator)
    spawn_action1.hash = 1
    spawn_action1.authors_index = 1
    spawn_action1.author_id = 1
    token := &state.tokens[token_id]
    append(&state.undo_history, spawn_action1)
    testing.expect_value(t, token.position.abs_tile, [2]u32{0, 0})

    append(&state.undo_history, make_action(.EDIT_TOKEN_POSITION))
    action2: ^Action = &state.undo_history[len(state.undo_history) - 1]
    action2.hash = 2
    action2.authors_index = 2
    action2.author_id = 1
    move_token_tool(&state, token, &tile_map, {20, 20}, action2, false)
    testing.expect_value(t, token.position.abs_tile, [2]u32{99, 99})

    append(&state.undo_history, make_action(.EDIT_TOKEN_POSITION))
    action3 := &state.undo_history[len(state.undo_history) - 1]
    action3.hash = 3
    action3.authors_index = 3
    action3.author_id = 1
    move_token_tool(&state, token, &tile_map, {200, 200}, action3, false)
    testing.expect_value(t, token.position.abs_tile, [2]u32{105, 105})

    append(&state.undo_history, make_action(.EDIT_TOKEN_POSITION))
    action4 := &state.undo_history[len(state.undo_history) - 1]
    action4.hash = 4
    action4.authors_index = 4
    action4.author_id = 1
    move_token_tool(&state, token, &tile_map, {300, 300}, action4, false)
    testing.expect_value(t, token.position.abs_tile, [2]u32{108, 108})

    new_actions: [dynamic]Action

    action1 := make_action(.EDIT_TOKEN_POSITION)
    action1.hash = 5
    action1.authors_index = 5
    action1.author_id = 2
    action1.token_id = token_id
    action1.start = {{105, 105}, {0, 0}}
    action1.end = {{17, 17}, {0, 0}}
    append(&new_actions, action1)

    // We don't have a common parent action so we have to redo all
    testing.expect_value(t, merge_and_redo_actions(&state, &tile_map, new_actions), true)

    testing.expect_value(t, len(state.undo_history), 5)
    testing.expect_value(t, state.undo_history[0].authors_index, 1)
    testing.expect_value(t, state.undo_history[1].authors_index, 2)
    testing.expect_value(t, state.undo_history[2].authors_index, 3)
    testing.expect_value(t, state.undo_history[3].authors_index, 4)
    testing.expect_value(t, state.undo_history[4].authors_index, 5)

    testing.expect_value(t, token.position.abs_tile, [2]u32{17, 17})

    teardown(&state, &tile_map)
}

@(test)
merge_and_redo_actions_test_common_parent :: proc(t: ^testing.T) {
    state, tile_map := setup()

    spawn_action1, token_id := create_spawn_token_action(&state, {{0, 0}, {0, 0}}, {18, 0}, context.temp_allocator)
    token := &state.tokens[token_id]
    append(&state.undo_history, spawn_action1)
    finish_last_undo_history_action(&state)
    testing.expect_value(t, token.position.abs_tile, [2]u32{0, 0})

    append(&state.undo_history, make_action(.EDIT_TOKEN_POSITION))
    action2: ^Action = &state.undo_history[len(state.undo_history) - 1]
    finish_last_undo_history_action(&state)
    move_token_tool(&state, token, &tile_map, {20, 20}, action2, false)
    testing.expect_value(t, token.position.abs_tile, [2]u32{99, 99})

    append(&state.undo_history, make_action(.EDIT_TOKEN_POSITION))
    action3 := &state.undo_history[len(state.undo_history) - 1]
    finish_last_undo_history_action(&state)
    move_token_tool(&state, token, &tile_map, {200, 200}, action3, false)
    testing.expect_value(t, token.position.abs_tile, [2]u32{105, 105})

    append(&state.undo_history, make_action(.EDIT_TOKEN_POSITION))
    action4 := &state.undo_history[len(state.undo_history) - 1]
    finish_last_undo_history_action(&state)
    move_token_tool(&state, token, &tile_map, {300, 300}, action4, false)
    testing.expect_value(t, token.position.abs_tile, [2]u32{108, 108})

    new_actions: [dynamic]Action
    append(&new_actions, state.undo_history[len(state.undo_history) - 1])

    action1 := make_action(.EDIT_TOKEN_POSITION)
    action1.hash = 5
    action1.authors_index = 5
    action1.author_id = 2
    action1.token_id = token_id
    action1.start = {{105, 105}, {0, 0}}
    action1.end = {{17, 17}, {0, 0}}
    append(&new_actions, action1)

    // We have a common parent action so no hash update
    testing.expect_value(t, merge_and_redo_actions(&state, &tile_map, new_actions), false)

    testing.expect_value(t, len(state.undo_history), 5)
    testing.expect_value(t, state.undo_history[0].authors_index, 1)
    testing.expect_value(t, state.undo_history[1].authors_index, 2)
    testing.expect_value(t, state.undo_history[2].authors_index, 3)
    testing.expect_value(t, state.undo_history[3].authors_index, 4)
    testing.expect_value(t, state.undo_history[4].authors_index, 5)

    testing.expect_value(t, token.position.abs_tile, [2]u32{17, 17})

    teardown(&state, &tile_map)
}

@(test)
merge_and_redo_actions_test_incomaptible :: proc(t: ^testing.T) {
    state1, tile_map1 := setup(1)

    action11, token_id1 := create_spawn_token_action(&state1, {{0, 0}, {0, 0}}, {18, 0}, context.temp_allocator)
    token1 := &state1.tokens[token_id1]
    append(&state1.undo_history, action11)
    finish_last_undo_history_action(&state1)
    testing.expect_value(t, token1.position.abs_tile, [2]u32{0, 0})

    append(&state1.undo_history, make_action(.EDIT_TOKEN_POSITION))
    action12: ^Action = &state1.undo_history[len(state1.undo_history) - 1]
    move_token_tool(&state1, token1, &tile_map1, {20, 20}, action12, false)
    finish_last_undo_history_action(&state1)
    testing.expect_value(t, token1.position.abs_tile, [2]u32{99, 99})

    append(&state1.undo_history, make_action(.EDIT_TOKEN_POSITION))
    action13 := &state1.undo_history[len(state1.undo_history) - 1]
    move_token_tool(&state1, token1, &tile_map1, {200, 200}, action13, false)
    finish_last_undo_history_action(&state1)
    testing.expect_value(t, token1.position.abs_tile, [2]u32{105, 105})

    state2, tile_map2 := setup(2)

    action21, token_id2 := create_spawn_token_action(&state2, {{2, 2}, {0, 0}}, {18, 0}, context.temp_allocator)
    token2 := &state2.tokens[token_id2]
    append(&state2.undo_history, action21)
    finish_last_undo_history_action(&state2)
    testing.expect_value(t, token2.position.abs_tile, [2]u32{2, 2})

    append(&state2.undo_history, make_action(.EDIT_TOKEN_POSITION))
    action22: ^Action = &state2.undo_history[len(state2.undo_history) - 1]
    move_token_tool(&state2, token2, &tile_map2, {40, 40}, action22, false)
    finish_last_undo_history_action(&state2)
    testing.expect_value(t, token2.position.abs_tile, [2]u32{100, 100})

    append(&state2.undo_history, make_action(.EDIT_TOKEN_POSITION))
    action23 := &state2.undo_history[len(state2.undo_history) - 1]
    move_token_tool(&state2, token2, &tile_map2, {100, 100}, action23, false)
    finish_last_undo_history_action(&state2)
    testing.expect_value(t, token2.position.abs_tile, [2]u32{102, 102})

    state2_actions := duplicate_actions(state2.undo_history[:])

    // We have nothing in common
    testing.expect_value(t, merge_and_redo_actions(&state1, &tile_map1, state2_actions), true)

    testing.expect_value(t, token1.id, token2.id)
    testing.expect_value(t, len(state1.undo_history), 6)
    testing.expect_value(t, len(state1.tokens), 2)
    testing.expect_value(t, 0 in state1.tokens, true)
    testing.expect_value(t, 1 in state1.tokens, true)

    testing.expect_value(t, state1.tokens[1].position.abs_tile, [2]u32{102, 102})

    teardown(&state1, &tile_map1)
    teardown(&state2, &tile_map2)
}

@(test)
action_hash_test :: proc(t: ^testing.T) {
    action1 := make_action(.EDIT_TOKEN_POSITION, context.temp_allocator)
    action1.authors_index = 5
    action1.token_life = true
    action1.token_size = 2
    action1.token_id = 1
    action1.old_name = "test"
    action1.start = {{105, 105}, {0, 0}}
    action1.end = {{17, 17}, {0, 0}}

    action2 := make_action(.EDIT_TOKEN_POSITION, context.temp_allocator)
    action2.authors_index = 5
    action2.token_life = true
    action2.token_size = 2
    action2.token_id = 1
    action2.old_name = "test"
    action2.start = {{105, 105}, {0, 0}}
    action2.end = {{17, 17}, {0, 0}}

    sha2_1 := compute_hash_with_prev(&action1, nil)
    sha2_2 := compute_hash_with_prev(&action2, nil)
    testing.expect_value(t, sha2_1, sha2_2)
}

@(test)
action_hash_test_multiple_spawn :: proc(t: ^testing.T) {
    action1 := make_action(.EDIT_TOKEN_POSITION, context.temp_allocator)
    action1.authors_index = 5
    action1.token_life = true
    action1.token_size = 2
    action1.token_id = 1
    action1.token_initiative_end = {1, 1}
    action1.new_name = "test"
    action1.start = {{105, 105}, {0, 0}}
    action1.end = {{17, 17}, {0, 0}}

    action2 := make_action(.EDIT_TOKEN_POSITION, context.temp_allocator)
    action2.authors_index = 5
    action2.token_life = true
    action2.token_size = 2
    action2.token_id = 1
    action2.token_initiative_end = {1, 1}
    action2.new_name = "test"
    action2.start = {{105, 105}, {0, 0}}
    action2.end = {{17, 17}, {0, 0}}


    s1: Serializer
    serializer_init_writer(&s1, allocator = context.temp_allocator)
    serialize(&s1, &action1)
    b1 := s1.data[:]

    s2: Serializer
    serializer_init_writer(&s2, allocator = context.temp_allocator)
    serialize(&s2, &action2)
    b2 := s2.data[:]

    for i in 0 ..< len(b1) {
        testing.expect_value(t, b1[i], b2[i])
    }


    sha2_1 := compute_hash_with_prev(&action1, nil)
    sha2_2 := compute_hash_with_prev(&action2, nil)

    testing.expect_value(t, sha2_1, sha2_2)
}
