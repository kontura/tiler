package tiler

import "core:math"

Tool :: enum {
    BRUSH,
    RECTANGLE,
    COLOR_PICKER,
    //CIRCLE,
    SPAWN_TOKEN,
    MOVE_TOKEN,
}

rectangle_tool :: proc(state: ^GameState,  tile_map: ^TileMap, end_pos: [2]f32) {
    start_mouse_tile : TileMapPosition = screen_coord_to_tile_map(state.tool_start_position.?, state, tile_map)
    end_mouse_tile : TileMapPosition = screen_coord_to_tile_map(end_pos, state, tile_map)

    start_tile : [2]u32 = {math.min(start_mouse_tile.abs_tile.x, end_mouse_tile.abs_tile.x), math.min(start_mouse_tile.abs_tile.y, end_mouse_tile.abs_tile.y)}
    end_tile : [2]u32 = {math.max(start_mouse_tile.abs_tile.x, end_mouse_tile.abs_tile.x), math.max(start_mouse_tile.abs_tile.y, end_mouse_tile.abs_tile.y)}

    for y : u32 = start_tile.y; y <= end_tile.y; y += 1 {
        for x : u32 = start_tile.x; x <= end_tile.x; x += 1 {
            state.undo_history[len(state.undo_history)-1].tile_history[{x,y}] = {get_tile(tile_map, {x, y}).color}
            set_tile_value(tile_map, {x, y}, {state.selected_color.xyzw})
        }
    }
}

move_token_tool :: proc(state: ^GameState,  tile_map: ^TileMap, end_pos: [2]f32) {
    token_tile_pos : TileMapPosition = screen_coord_to_tile_map(state.tool_start_position.?, state, tile_map)
    token := find_token_at_tile_map(token_tile_pos, state)
    if (token != nil) {
        mouse_tile_pos : TileMapPosition = screen_coord_to_tile_map(end_pos, state, tile_map)
        state.undo_history[len(state.undo_history)-1].token_history[token.id] = token.position
        token.position = mouse_tile_pos
    }

}
