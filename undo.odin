package tiler
import "core:mem"

Action :: struct {
    tool: Tool,
    // previous tile state
    tile_history: map[[2]u32]Tile,
    // previous token position
    token_history: map[u64]TileMapPosition,
}

make_action :: proc(allocator: mem.Allocator) -> Action {
    action : Action
    action.tile_history.allocator = allocator
    action.token_history.allocator = allocator

    return action
}

delete_action :: proc(action: ^Action) {
    delete(action.tile_history)
    delete(action.token_history)
}

clear_action :: proc(action: ^Action) {
    clear(&action.tile_history)
    clear(&action.token_history)
}

undo_action :: proc(state: ^GameState, tile_map:  ^TileMap, action: ^Action) {
    for abs_tile, &tile in action.tile_history {
        set_tile_value(tile_map, abs_tile, {tile.color})
    }
    for token_id, &pos in action.token_history {
        for &token in state.tokens {
            if token.id == token_id {
                token.position = pos
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
