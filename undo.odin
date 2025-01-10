package tiler

Action :: struct {
    tool: Tool,
    // previous tile state
    tile_history: map[[2]u32]Tile,
    // previous token position
    token_history: map[u64]TileMapPosition,
}

delete_action :: proc(action: ^Action) {
    delete(action.tile_history)
    delete(action.token_history)
}

clear_action :: proc(action: ^Action) {
    clear(&action.tile_history)
    clear(&action.token_history)
}

undo_last_action :: proc(state: ^GameState, tile_map:  ^TileMap) {
    if (len(&state.undo_history) > 0) {
        last_action := state.undo_history[len(state.undo_history)-1]
        for abs_tile, &tile in last_action.tile_history {
            set_tile_value(tile_map, abs_tile, {tile.color})
        }
        for token_id, &pos in last_action.token_history {
            for &token in state.tokens {
                if token.id == token_id {
                    token.position = pos
                }
            }
        }
    }
}

clear_last_action :: proc(state: ^GameState, tile_map:  ^TileMap) {
    if (len(&state.undo_history) > 0) {
        clear_action(&state.undo_history[len(state.undo_history)-1])
    }
    state.clear_last_action = false
}

pop_last_action :: proc(state: ^GameState, tile_map:  ^TileMap) {
    if (len(&state.undo_history) > 0) {
        action : Action = pop(&state.undo_history)
        delete_action(&action)
    }
}
