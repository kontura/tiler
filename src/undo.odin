package tiler
import "core:mem"

Action :: struct {
    //TODO(amatej): I could store these more reasonably, like start, end, tool
    // tile delta old_tile - new_tile
    tile_history: map[[2]u32]Tile,
    // previous token position (#TODO(amatej): convert to deltas)
    token_history: map[u64]TileMapPosition,
    token_initiative_history: map[u64][2]i32,
    token_created: [dynamic]u64,
    token_deleted: [dynamic]Token,
}

make_action :: proc(allocator: mem.Allocator) -> Action {
    action : Action
    action.tile_history.allocator = allocator
    action.token_history.allocator = allocator
    action.token_initiative_history.allocator = allocator
    action.token_created.allocator = allocator
    action.token_deleted.allocator = allocator

    return action
}

delete_action :: proc(action: ^Action) {
    delete(action.tile_history)
    delete(action.token_history)
    delete(action.token_created)
    delete(action.token_initiative_history)
    delete(action.token_deleted)
}

clear_action :: proc(action: ^Action) {
    clear(&action.tile_history)
    clear(&action.token_history)
    clear(&action.token_created)
    clear(&action.token_initiative_history)
    clear(&action.token_deleted)
}

undo_action :: proc(state: ^GameState, tile_map:  ^TileMap, action: ^Action) {
    for abs_tile, &tile in action.tile_history {
        old_tile := get_tile(tile_map, abs_tile)
        set_tile(tile_map, abs_tile, tile_add(&old_tile, &tile))
    }
    for token_id, &pos in action.token_history {
        token := &state.tokens[token_id]
        token.position = pos
    }
    for token_id, &init_pos in action.token_initiative_history {
        remove_token_by_id_from_initiative(state, token_id)
        tokens := &state.initiative_to_tokens[init_pos.x]
        if i32(len(tokens)) > init_pos.y {
            inject_at(tokens, init_pos.y, token_id)
        } else {
            append(tokens, token_id)
        }
    }
    for token_id in action.token_created {
        remove_token_by_id_from_initiative(state, token_id)
        delete_key(&state.tokens, token_id)
    }
    for &token in action.token_deleted {
        state.tokens[token.id] =  token
        append(&state.initiative_to_tokens[token.initiative], token.id)
    }
}

redo_action :: proc(state: ^GameState, tile_map:  ^TileMap, action: ^Action) {
    for abs_tile, &tile in action.tile_history {
        old_tile := get_tile(tile_map, abs_tile)
        set_tile(tile_map, abs_tile, tile_subtract(&old_tile, &tile))
    }
    //TODO(amatej): possibly add token actions once they do deltas
   // for token_id, &pos in action.token_history {
   //     token := &state.tokens[token_id]
   //     token.position = pos
   // }
   // for token_id, &init_pos in action.token_initiative_history {
   //     remove_token_by_id_from_initiative(state, token_id)
   //     tokens := &state.initiative_to_tokens[init_pos.x]
   //     if i32(len(tokens)) > init_pos.y {
   //         inject_at(tokens, init_pos.y, token_id)
   //     } else {
   //         append(tokens, token_id)
   //     }
   // }
   // for token_id in action.token_created {
   //     remove_token_by_id_from_initiative(state, token_id)
   //     delete_key(&state.tokens, token_id)
   // }
   // for &token in action.token_deleted {
   //     state.tokens[token.id] =  token
   //     append(&state.initiative_to_tokens[token.initiative], token.id)
   // }
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
