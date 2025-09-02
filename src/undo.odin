package tiler
import "core:mem"
import "core:fmt"
import "core:strings"

Action :: struct {
    // SYNCED
    tool: Tool,
    start: TileMapPosition,
    end: TileMapPosition,
    color: [4]u8,
    radius: f64,

    // Whether this action should be undone (this is an undo action)
    undo: bool,
    token_history: map[u64][2]i32,
    token_initiative_history: map[u64][2]i32,
    token_life: map[u64]bool,
    token_size: map[u64]i64,

    // This can work for only one token
    // But will we ever rename more tokens at once>
    old_names: map[u64]string,
    new_names: map[u64]string,

    // NOT SYNCED

    // Whether this action can be reverted.
    // Actions that have already been reverted or are reverting
    // actions cannot be reverted again.
    reverted: bool,

    // Whether this action was made by me, not other peers
    mine: bool,

    // This is not synchronized, its local to each peer.
    // Determines if this action was already perfomed.
    performed: bool,
    // tile delta old_tile - new_tile (this could be a nice cache? because unding an action
    // stored in input format would require to redo all actions from the start, but once done
    // we could store more state in this so we don't have to always redo) Although undo is typically
    // done just once? But the starting actions we get re-done many times..
    tile_history: map[[2]u32]Tile,
}

make_action :: proc(allocator := context.allocator) -> Action {
    action : Action
    action.tile_history.allocator = allocator
    action.token_history.allocator = allocator
    action.token_initiative_history.allocator = allocator
    action.token_life.allocator = allocator
    action.mine = true

    return action
}

delete_action :: proc(action: ^Action) {
    delete(action.tile_history)
    delete(action.token_history)
    delete(action.token_life)
    delete(action.token_initiative_history)
    delete(action.old_names)
    delete(action.new_names)
}

undo_action :: proc(state: ^GameState, tile_map:  ^TileMap, action: ^Action) {
    //make this into a revert, the way git does it, so add a new action with oposite values
    for abs_tile, &tile in action.tile_history {
        old_tile := get_tile(tile_map, abs_tile)
        set_tile(tile_map, abs_tile, tile_add(&old_tile, &tile))
    }
    for token_id, &pos_delta in action.token_history {
        token := &state.tokens[token_id]
        add_tile_pos_delta(&token.position, pos_delta*-1)
     }

    for token_id, &delta_init_pos in action.token_initiative_history {
        old_init, old_init_index, ok := remove_token_by_id_from_initiative(state, token_id)
        if ok {
            new_init_pos := [2]i32{old_init, old_init_index} + delta_init_pos
            add_at_initiative(state, token_id, new_init_pos.x, new_init_pos.y)
        }
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
    for token_id, delta_size in action.token_size {
        token, ok := &state.tokens[token_id]
        if ok {
            token.size -= i32(delta_size)
        }
    }
    for token_id, &old_name in action.old_names {
        token, ok := &state.tokens[token_id]
        if action.new_names[token_id] != old_name {
            delete(token.name)
            token.name = strings.clone(old_name)
            set_texture_based_on_name(state, token)
        }
    }
}

redo_action :: proc(state: ^GameState, tile_map:  ^TileMap, action: ^Action) {
    // Optimization for redo
    // It cant work for undo because we woudn't know what was under the tiles,
    // we would have to redo from the start up to the undo action
    if action.tool == .RECTANGLE {
        rectangle_tool(action.start, action.end, action.color, tile_map, action)
    } else if action.tool == .CIRCLE {
        draw_tile_circle(tile_map, action.start, auto_cast action.radius, action.color, action)
    } else if action.tool == .CONE {
        draw_cone_tiles(tile_map, action.start, action.end, action.color, action)
    } else {
        for abs_tile, &tile in action.tile_history {
            old_tile := get_tile(tile_map, abs_tile)
            set_tile(tile_map, abs_tile, tile_subtract(&old_tile, &tile))
        }
    }
    fmt.println("redoing action: ", action)
    for token_id, &pos_delta in action.token_history {
        token := &state.tokens[token_id]
        if token.position == action.start {
            add_tile_pos_delta(&token.position, pos_delta)
        }
    }
    for token_id, &delta_init_pos in action.token_initiative_history {
        old_init, old_init_index, ok := remove_token_by_id_from_initiative(state, token_id)
        if ok {
            new_init_pos := [2]i32{old_init, old_init_index} - delta_init_pos
            add_at_initiative(state, token_id, new_init_pos.x, new_init_pos.y)
        }
    }
    for token_id, life in action.token_life {
        if life {
            // life is true == token was created
            token, ok := &state.tokens[token_id]
            if ok {
                token.alive = true
            } else {
                t := make_token(token_id, {{u32(action.token_history[token_id].x), u32(action.token_history[token_id].y)}, {0, 0}}, action.color)
                add_at_initiative(state, t.id, action.token_initiative_history[token_id].x, action.token_initiative_history[token_id].y)
                state.tokens[t.id] =  t
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
    for token_id, delta_size in action.token_size {
        token, ok := &state.tokens[token_id]
        if ok {
            token.size += i32(delta_size)
        }
    }
    for token_id, &new_name in action.new_names {
        token, ok := &state.tokens[token_id]
        if action.old_names[token_id] != new_name {
            delete(token.name)
            token.name = strings.clone(new_name)
            set_texture_based_on_name(state, token)
        }
    }
}
