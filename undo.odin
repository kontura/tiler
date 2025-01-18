package tiler
import "core:mem"

Action :: struct {
    tool: Tool,
    // previous tile state
    tile_history: map[[2]u32]Tile,
    // previous token position
    token_history: map[u64]Maybe(TileMapPosition),
    token_initiative_history: map[u64]Maybe([2]i32),
}

make_action :: proc(allocator: mem.Allocator) -> Action {
    action : Action
    action.tile_history.allocator = allocator
    action.token_history.allocator = allocator
    action.token_initiative_history.allocator = allocator

    return action
}

delete_action :: proc(action: ^Action) {
    delete(action.tile_history)
    delete(action.token_history)
    delete(action.token_initiative_history)
}

clear_action :: proc(action: ^Action) {
    clear(&action.tile_history)
    clear(&action.token_history)
    clear(&action.token_initiative_history)
}

undo_action :: proc(state: ^GameState, tile_map:  ^TileMap, action: ^Action) {
    for abs_tile, &tile in action.tile_history {
        set_tile_value(tile_map, abs_tile, {tile.color})
    }
    for token_id, &pos in action.token_history {
        token := &state.tokens[token_id]
        if (pos != nil) {
            token.position = pos.?
        } else {
            delete_key(&state.tokens, token_id)
            initiative_list, ok := &state.initiative_to_tokens[token.initiative]
            if ok {
                for val, i in initiative_list {
                    if val == token.id {
                        unordered_remove(initiative_list, i)
                    }
                }
            }
        }
    }
    for token_id, &init_pos in action.token_initiative_history {
        remove_token_by_id_from_initiative(state, token_id)
        tokens := &state.initiative_to_tokens[init_pos.?.x]
        if i32(len(tokens)) > init_pos.?.y {
            inject_at(tokens, init_pos.?.y, token_id)
        } else {
            append(tokens, token_id)
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
