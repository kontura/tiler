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

rectangle_tool :: proc(state: ^GameState,  tile_map: ^TileMap, end_pos: [2]f32, action: ^Action) {
    start_mouse_tile : TileMapPosition = screen_coord_to_tile_map(state.tool_start_position.?, state, tile_map)
    end_mouse_tile : TileMapPosition = screen_coord_to_tile_map(end_pos, state, tile_map)

    start_tile : [2]u32 = {math.min(start_mouse_tile.abs_tile.x, end_mouse_tile.abs_tile.x), math.min(start_mouse_tile.abs_tile.y, end_mouse_tile.abs_tile.y)}
    end_tile : [2]u32 = {math.max(start_mouse_tile.abs_tile.x, end_mouse_tile.abs_tile.x), math.max(start_mouse_tile.abs_tile.y, end_mouse_tile.abs_tile.y)}

    for y : u32 = start_tile.y; y <= end_tile.y; y += 1 {
        for x : u32 = start_tile.x; x <= end_tile.x; x += 1 {
            action.tile_history[{x,y}] = get_tile(tile_map, {x, y})
            set_tile_value(tile_map, {x, y}, {state.selected_color.xyzw})
        }
    }
}

move_token_tool :: proc(state: ^GameState,  tile_map: ^TileMap, end_pos: [2]f32, action: ^Action, feedback: bool) {
    token := find_token_at_screen(tile_map, state, state.tool_start_position.?)
    if (token != nil) {
        mouse_tile_pos : TileMapPosition = screen_coord_to_tile_map(end_pos, state, tile_map)
        action.token_history[token.id] = token.position
        set_token_position(token, mouse_tile_pos)
        if feedback {
            token_tile_pos : TileMapPosition = screen_coord_to_tile_map(state.tool_start_position.?, state, tile_map)
            token.moved = DDA(state, tile_map, mouse_tile_pos.abs_tile, token_tile_pos.abs_tile)
        } else {
            token.moved = 0
        }
    }

}

DDA :: proc(state: ^GameState,  tile_map: ^TileMap, p0: [2]u32, p1: [2]u32) -> u32 {
    temp_action : ^Action = &state.temp_actions[len(state.temp_actions)-1]

    // calculate dx & dy
    dx : i32 = i32(p1.x - p0.x)
    dy : i32 = i32(p1.y - p0.y)

    // calculate steps required for generating pixels
    steps := abs(dx) > abs(dy) ? abs(dx) : abs(dy)

    Xinc := f32(dx) / f32(steps)
    Yinc := f32(dy) / f32(steps)

    last_diagonal_doubled : bool = true
    walked : u32 = 0

    // Put pixel for each step
    X : f32 = f32(p0.x)
    Y : f32 = f32(p0.y)
    last_pos: [2]u32 = {u32(math.round_f32(X)), u32(math.round_f32(Y))}
    for i: i32 = 0; i <= steps; i += 1 {
        pos: [2]u32 = {u32(math.round_f32(X)), u32(math.round_f32(Y))}
        temp_action.tile_history[pos] = get_tile(tile_map, pos)
        tile := get_tile(tile_map, pos)
        tile.color.g += 30
        set_tile_value(tile_map, pos, tile)
        X += Xinc // increment in x at each step
        Y += Yinc // increment in y at each step

        if (last_pos.x != pos.x && last_pos.y != pos.y) {
            if last_diagonal_doubled {
                walked += 1
                last_diagonal_doubled = false
            } else {
                walked += 2
                last_diagonal_doubled = true
            }
        } else if (last_pos.x != pos.x || last_pos.y != pos.y) {
            walked += 1
        }
        last_pos = pos
    }

    return walked
}
