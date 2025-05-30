package tiler
import "core:mem"

Action :: struct {
    tool: Tool,
    start: TileMapPosition,
    end: TileMapPosition,
    color: [4]u8,

    // tile delta old_tile - new_tile (this could be a nice cache? because unding an action
    // stored in input format would require to redo all actions from the start, but once done
    // we could store more state in this so we don't have to always redo) Although undo is typically
    // done just once? But the starting actions we get re-done many times..
    tile_history: map[[2]u32]Tile,
    token_history: map[u64][2]i32,
    token_initiative_history: map[u64][2]i32,
    token_life: map[u64]bool,
}

make_action :: proc(allocator: mem.Allocator) -> Action {
    action : Action
    action.tile_history.allocator = allocator
    action.token_history.allocator = allocator
    action.token_initiative_history.allocator = allocator
    action.token_life.allocator = allocator

    return action
}

delete_action :: proc(action: ^Action) {
    delete(action.tile_history)
    delete(action.token_history)
    delete(action.token_life)
    delete(action.token_initiative_history)
}

clear_action :: proc(action: ^Action) {
    clear(&action.tile_history)
    clear(&action.token_history)
    clear(&action.token_life)
    clear(&action.token_initiative_history)
}

undo_action :: proc(state: ^GameState, tile_map:  ^TileMap, action: ^Action) {
    for abs_tile, &tile in action.tile_history {
        old_tile := get_tile(tile_map, abs_tile)
        set_tile(tile_map, abs_tile, tile_add(&old_tile, &tile))
    }
    for token_id, &pos_delta in action.token_history {
        token := &state.tokens[token_id]
        add_tile_pos_delta(&token.position, pos_delta*-1)
    }

    for token_id, &delta_init_pos in action.token_initiative_history {
        old_init, old_init_index := remove_token_by_id_from_initiative(state, token_id)
        new_init_pos := [2]i32{old_init, old_init_index} + delta_init_pos
        add_at_initiative(state, token_id, new_init_pos.x, new_init_pos.y)
    }
    for token_id, life in action.token_life {
        if life {
            // life is true == token was created (undo is deleteing it)
            remove_token_by_id_from_initiative(state, token_id)
            token, ok := &state.tokens[token_id]
            if ok {
                token.alive = false
            }
        } else {
            // life is false == token was deleted (undo is creating it)
            token, ok := &state.tokens[token_id]
            if ok {
                token.alive = true
            }
            append(&state.initiative_to_tokens[token.initiative], token_id)
        }
    }
}

redo_action :: proc(state: ^GameState, tile_map:  ^TileMap, action: ^Action) {
    // Optimization for redo
    // It cant work for undo because we woudn't know what was under the tiles,
    // we would have to redo from the start up to the undo action
    if action.tool == .RECTANGLE {
        rectangle_tool(action.start, action.end, action.color, tile_map, nil)
    } else {
        for abs_tile, &tile in action.tile_history {
            old_tile := get_tile(tile_map, abs_tile)
            set_tile(tile_map, abs_tile, tile_subtract(&old_tile, &tile))
        }
    }
    for token_id, &pos_delta in action.token_history {
        token := &state.tokens[token_id]
        add_tile_pos_delta(&token.position, pos_delta)
    }
    for token_id, &delta_init_pos in action.token_initiative_history {
        old_init, old_init_index := remove_token_by_id_from_initiative(state, token_id)
        new_init_pos := [2]i32{old_init, old_init_index} - delta_init_pos
        add_at_initiative(state, token_id, new_init_pos.x, new_init_pos.y)
    }
    for token_id, life in action.token_life {
        if life {
            // life is true == token was created
            token, ok := &state.tokens[token_id]
            if ok {
                token.alive = true
            }
            append(&state.initiative_to_tokens[token.initiative], token_id)
        } else {
            // life is false == token was deleted
            remove_token_by_id_from_initiative(state, token_id)
            token, ok := &state.tokens[token_id]
            if ok {
                token.alive = false
            }
        }
    }
}

clear_last_action :: proc(state: ^GameState, tile_map:  ^TileMap) {
    if (len(&state.undo_history) > 0) {
        clear_action(&state.undo_history[len(state.undo_history)-1])
    }
}

pop_last_action :: proc(state: ^GameState, tile_map:  ^TileMap, actions: ^[dynamic]Action) {
    if (len(actions) > 0) {
        action : Action = pop(actions)
        delete_action(&action)
    }
}
