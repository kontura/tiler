package gridimpro

import "core:math"

Tool :: enum {
    BRUSH,
    RECTANGLE,
    COLOR_PICKER,
    //CIRCLE,
}

rectangle_tool :: proc(state: ^GameState,  tile_map: ^TileMap, end_pos: [2]f32, revert: bool) {
    start_mouse_tile : TileMapPosition = screen_coord_to_tile_map(state.tool_start_position.?, state, tile_map)
    end_mouse_tile : TileMapPosition = screen_coord_to_tile_map(end_pos, state, tile_map)

    start_tile : [2]u32 = {math.min(start_mouse_tile.abs_tile.x, end_mouse_tile.abs_tile.x), math.min(start_mouse_tile.abs_tile.y, end_mouse_tile.abs_tile.y)}
    end_tile : [2]u32 = {math.max(start_mouse_tile.abs_tile.x, end_mouse_tile.abs_tile.x), math.max(start_mouse_tile.abs_tile.y, end_mouse_tile.abs_tile.y)}

    for y : u32 = start_tile.y; y <= end_tile.y; y += 1 {
        for x : u32 = start_tile.x; x <= end_tile.x; x += 1 {
            if revert {
                state.revert_temp_tile_color[{x,y}] = get_tile_value(tile_map, {x, y}).color
            }
            set_tile_value(tile_map, {x, y}, {state.selected_color.xyzw})
        }
    }
}

