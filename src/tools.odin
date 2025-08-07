package tiler

import "core:math"
import "core:fmt"
import "core:strings"
import rl "vendor:raylib"

GREEN_HIGHLIGH : [4]u8 : {0, 255, 0, 30}
GREEN_HIGHLIGH_PATH : [4]u8 : {30, 105, 30, 230}

Tool :: enum {
    BRUSH,
    RECTANGLE,
    COLOR_PICKER,
    CIRCLE,
    EDIT_TOKEN,
    MOVE_TOKEN,
    WALL,
    HELP,
    TOUCH_MOVE,
    TOUCH_ZOOM,
    EDIT_BG,
    LIGHT_SOURCE,
    CONE,
}

dist :: proc(p1: [2]$T, p2: [2]T) -> f32 {
    dx := f32(p2.x) - f32(p1.x)
    dx *= dx
    dy := f32(p2.y) - f32(p1.y)
    dy *= dy

    return math.sqrt_f32(dx + dy)
}

// Porter-Duff
color_over :: proc(c1: [4]u8, c2: [4]u8) -> [4]u8 {
    c1f := rl.ColorNormalize(c1.xyzw)
    c2f := rl.ColorNormalize(c2.xyzw)
    res: [4]f32
    res.w = c1f.w + c2f.w * (1 - c1f.w)
    res.x = (c1f.x * c1f.w + c2f.x * c2f.w * (1 - c1f.w)) / res.w
    res.y = (c1f.y * c1f.w + c2f.y * c2f.w * (1 - c1f.w)) / res.w
    res.z = (c1f.z * c1f.w + c2f.z * c2f.w * (1 - c1f.w)) / res.w
    return rl.ColorFromNormalized(res).xyzw
}

wall_tool :: proc(state: ^GameState,  tile_map: ^TileMap, current_pos: [2]f32, action: ^Action) -> cstring {
    drawn : f32 = 0
    start_mouse_tile : TileMapPosition = screen_coord_to_tile_map(state.tool_start_position.?, state, tile_map)
    // convert to crossing possition:
    // The very top left (first) crossing i 0,0
    // 0,0, +---+---+--+
    //      |   |   |  |
    //      +---+---+--+
    //      |   |   |  |
    //      +---+---+--+
    start_crossing_pos : [2]u32 = tile_pos_to_crossing_pos(start_mouse_tile)

    end_mouse_tile : TileMapPosition = screen_coord_to_tile_map(current_pos, state, tile_map)
    end_crossing_pos : [2]u32 = tile_pos_to_crossing_pos(end_mouse_tile)

    start: [2]u32 = {math.min(start_crossing_pos.x, end_crossing_pos.x), math.min(start_crossing_pos.y, end_crossing_pos.y)}
    end: [2]u32 = {math.max(start_crossing_pos.x, end_crossing_pos.x), math.max(start_crossing_pos.y, end_crossing_pos.y)}

    if abs(i32(start_crossing_pos.x) - i32(end_crossing_pos.x)) > abs(i32(start_crossing_pos.y) - i32(end_crossing_pos.y)) {
        y : u32 = start_crossing_pos.y
        drawn = f32(end.x - start.x)
        for x : u32 = start.x; x < end.x; x += 1 {
            old_tile := get_tile(tile_map, {x, y})
            new_tile := old_tile
            new_tile.walls += {Direction.TOP}
            new_tile.wall_colors[Direction.TOP] = state.selected_color
            action.tile_history[{x,y}] = tile_subtract(&old_tile, &new_tile)
            set_tile(tile_map, {x, y}, new_tile)
        }
    } else {
        x : u32 = start_crossing_pos.x
        drawn = f32(end.y - start.y)
        for y : u32 = start.y; y < end.y; y += 1 {
            old_tile := get_tile(tile_map, {x, y})
            new_tile := old_tile
            new_tile.walls += {Direction.LEFT}
            new_tile.wall_colors[Direction.LEFT] = state.selected_color
            action.tile_history[{x,y}] = tile_subtract(&old_tile, &new_tile)
            set_tile(tile_map, {x, y}, new_tile)
        }
    }

    builder := strings.builder_make(context.temp_allocator)
    strings.write_string(&builder, fmt.aprintf("%.1f", drawn * 5, allocator=context.temp_allocator))
    return strings.to_cstring(&builder) or_else BUILDER_FAILED
}

//TODO(amatej): circle tool doesn't work after looping tile_chunks
circle_tool :: proc(state: ^GameState,  tile_map: ^TileMap, current_pos: [2]f32, action: ^Action) -> cstring {
    start_mouse_tile : TileMapPosition = screen_coord_to_tile_map(state.tool_start_position.?, state, tile_map)

    half := tile_map.tile_side_in_feet/2
    start_mouse_tile.rel_tile.x = start_mouse_tile.rel_tile.x >= 0 ? half : -half
    start_mouse_tile.rel_tile.y = start_mouse_tile.rel_tile.y >= 0 ? half : -half
    start_snapped_screen := tile_map_to_screen_coord_full(start_mouse_tile, state, tile_map)

    // Snapping per 5 feet
    unit_vec := rl.Vector2Normalize(current_pos - start_snapped_screen)
    max_dist := dist(start_snapped_screen, current_pos) * tile_map.pixels_to_feet
    rounded_dist_in_feet := math.round_f32(max_dist / 5) * 5
    current_pos := start_snapped_screen + unit_vec * (rounded_dist_in_feet * tile_map.feet_to_pixels)

    current_mouse_tile : TileMapPosition = screen_coord_to_tile_map(current_pos, state, tile_map)

    max_dist_in_feet := tile_distance(tile_map, start_mouse_tile, current_mouse_tile)

    action.tool = .CIRCLE
    action.start = start_mouse_tile
    action.color = state.selected_color
    action.radius = auto_cast max_dist_in_feet
    action.performed = true

    draw_tile_circle(tile_map, start_mouse_tile, max_dist_in_feet, state.selected_color, action)

    builder := strings.builder_make(context.temp_allocator)
    strings.write_string(&builder, fmt.aprintf("%.1f", max_dist_in_feet, allocator=context.temp_allocator))
    return strings.to_cstring(&builder) or_else BUILDER_FAILED
}

// radius is in feet
draw_tile_circle :: proc(tile_map: ^TileMap, center: TileMapPosition, radius: f32, color: [4]u8, action: ^Action) {
    max_dist_up := u32(math.ceil_f32(radius/tile_map.tile_side_in_feet)) + 2

    start_tile : [2]u32 = {center.abs_tile.x - max_dist_up, center.abs_tile.y - max_dist_up}
    end_tile : [2]u32 = {center.abs_tile.x + max_dist_up, center.abs_tile.y + max_dist_up}

    for y : u32 = start_tile.y; y <= end_tile.y; y += 1 {
        for x : u32 = start_tile.x; x <= end_tile.x; x += 1 {
            temp_tile_pos: TileMapPosition = {{x,y}, {0,0}}

            dist := tile_distance(tile_map, temp_tile_pos, center)
            if (radius > dist) {
                old_tile := get_tile(tile_map, {x, y})
                new_tile := tile_make_color_walls_colors(color_over(color.xyzw, old_tile.color.xyzw), old_tile.walls, old_tile.wall_colors)
                action.tile_history[{x,y}] = tile_subtract(&old_tile, &new_tile)
                set_tile(tile_map, {x, y}, new_tile)
            }
        }
    }

}

rectangle_tool :: proc(start_mouse_tile: TileMapPosition, end_mouse_tile: TileMapPosition, selected_color: [4]u8, tile_map: ^TileMap, action: ^Action) -> cstring {
    start_tile : [2]u32 = {math.min(start_mouse_tile.abs_tile.x, end_mouse_tile.abs_tile.x), math.min(start_mouse_tile.abs_tile.y, end_mouse_tile.abs_tile.y)}
    end_tile : [2]u32 = {math.max(start_mouse_tile.abs_tile.x, end_mouse_tile.abs_tile.x), math.max(start_mouse_tile.abs_tile.y, end_mouse_tile.abs_tile.y)}

    for y : u32 = start_tile.y; y <= end_tile.y; y += 1 {
        for x : u32 = start_tile.x; x <= end_tile.x; x += 1 {
            old_tile := get_tile(tile_map, {x, y})
            new_tile := tile_make_color_walls_colors(color_over(selected_color.xyzw, old_tile.color.xyzw), old_tile.walls, old_tile.wall_colors)
            if action != nil{
                action.tile_history[{x,y}] = tile_subtract(&old_tile, &new_tile)
            }
            set_tile(tile_map, {x, y}, new_tile)
        }
    }

    builder := strings.builder_make(context.temp_allocator)
    strings.write_string(&builder, fmt.aprintf("%.0fx%.0f",
                                               abs(f32(start_tile.x) - f32(end_tile.x) - 1) * 5,
                                               abs(f32(start_tile.y) - f32(end_tile.y) - 1) * 5,
                                               allocator=context.temp_allocator))
    return strings.to_cstring(&builder) or_else BUILDER_FAILED
}

find_at_initiative :: proc(state: ^GameState, pos: f32) -> (i32, i32, u64) {
    row_offset : i32 = 10
    for i : i32 = 1; i < INITIATIVE_COUNT; i += 1 {
        tokens := state.initiative_to_tokens[i]
        row_offset += 3
        if (tokens == nil || len(tokens) == 0) {
            row_offset += 10
            if f32(row_offset) >= pos {
                return i, 0, 0
            }
        } else {
            for token_id, index in tokens {
                token := state.tokens[token_id]
                token_size :=  f32(token.size) * 4 + 10
                half_of_this_row := i32(token_size + 3)
                row_offset += 2*half_of_this_row
                if f32(row_offset) >= pos {
                    // Given that the initiative tracker moves when the token is moved
                    // (because of different sizes of empty row vs row with tokens) compare
                    // not with half but with 1/3 of a half -> 1/6.
                    // It is not exact but it seems to work alright.
                    if f32(row_offset) - pos > f32(half_of_this_row)/3 {
                        return i, i32(index), token.id
                    } else {
                        return i, i32(index)+1, token.id
                    }
                }
            }
        }
    }

    return 0, 0, 0
}

add_at_initiative :: proc(state: ^GameState, token_id: u64, initiative: i32, init_index: i32) {
    if state.initiative_to_tokens[initiative] == nil {
        state.initiative_to_tokens[initiative] = make([dynamic]u64)
    }
    tokens := &state.initiative_to_tokens[initiative]
    if i32(len(tokens)) >= init_index {
        inject_at(tokens, init_index, token_id)
    } else {
        append(tokens, state.selected_token)
    }
}

move_initiative_token_tool :: proc(state: ^GameState, end_pos: [2]f32, action: ^Action) {
    if state.selected_token == 0 {
        state.initiative_tool_start.x, state.initiative_tool_start.y, state.selected_token = find_at_initiative(state, state.tool_start_position.?.y)
    } else {
        end_initiative, end_index, _ := find_at_initiative(state, end_pos.y)
        init, i := remove_token_by_id_from_initiative(state, state.selected_token)
        add_at_initiative(state, state.selected_token, end_initiative, end_index)
        if action != nil {
            action.token_initiative_history[state.selected_token] = [2]i32{state.initiative_tool_start.x - end_initiative, math.max(state.initiative_tool_start.y - end_index, 0)}
            fmt.println("end delta: ", action.token_initiative_history[state.selected_token], " from: ", state.initiative_tool_start, " - ", end_initiative, ", ", end_index)
        }
    }
}

move_token_tool :: proc(state: ^GameState, token: ^Token,  tile_map: ^TileMap, end_pos: [2]f32, action: ^Action, feedback: bool) {
    mouse_tile_pos : TileMapPosition = screen_coord_to_tile_map(end_pos, state, tile_map)
    token_pos_delta : [2]i32 = {i32(token.position.abs_tile.x) - i32(mouse_tile_pos.abs_tile.x), i32(token.position.abs_tile.y) - i32(mouse_tile_pos.abs_tile.y)}
    action.token_history[token.id] = token_pos_delta
    if feedback {
        temp_action : ^Action = &state.temp_actions[len(state.temp_actions)-1]
        assert(token.position.rel_tile == {0,0})
        pos := token.position
        //TODO(amatej): This breaks down for bigger tokens (size > 2)
        // We start with 31 because it works emirically
        radius : f32 = 31
        if token.size > 1 {
            half := tile_map.tile_side_in_feet/2
            // If the token size is even shift the center of the token
            // to the Tile corners
            if token.size % 2 == 0 {
                pos.rel_tile = {-half, -half}
            }
            // Grow the raidus by the size of the token (-1 because size 1 is the default)
            radius += (f32(token.size - 1) * half)
        }
        draw_tile_circle(tile_map, pos, radius, GREEN_HIGHLIGH, temp_action)
        token.moved = DDA(state, tile_map, mouse_tile_pos.abs_tile, token.position.abs_tile, action)
    } else {
        token.moved = 0
    }
    add_tile_pos_delta(&token.position, token_pos_delta)
}

//TODO(amatej): this doesn't work when we loop to previous tile_chunk
DDA :: proc(state: ^GameState,  tile_map: ^TileMap, p0: [2]u32, p1: [2]u32, temp_action: ^Action) -> u32 {
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
        old_tile := get_tile(tile_map, pos)
        new_tile := old_tile
        new_tile.color = color_over(GREEN_HIGHLIGH_PATH, old_tile.color)
        tile_delta := tile_subtract(&old_tile, &new_tile)
        if (pos in temp_action.tile_history) {
            temp_action.tile_history[pos] = tile_add(&temp_action.tile_history[pos], &tile_delta)
        } else {
            temp_action.tile_history[pos] = tile_delta
        }
        set_tile(tile_map, pos, new_tile)
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

cone_tool :: proc(state: ^GameState,  tile_map: ^TileMap, current_pos: [2]f32, action: ^Action) -> cstring {
    // First snap starting point to grid
    start_mouse_tile : TileMapPosition = screen_coord_to_tile_map(state.tool_start_position.?, state, tile_map)
    half := tile_map.tile_side_in_feet/2
    start_mouse_tile.rel_tile.x = start_mouse_tile.rel_tile.x >= 0 ? half : -half
    start_mouse_tile.rel_tile.y = start_mouse_tile.rel_tile.y >= 0 ? half : -half
    start_snapped_screen := tile_map_to_screen_coord_full(start_mouse_tile, state, tile_map)

    unit_vec := rl.Vector2Normalize(current_pos - start_snapped_screen)
    max_dist := dist(start_snapped_screen, current_pos) * tile_map.pixels_to_feet
    rounded_dist_in_feet := math.round_f32(max_dist / 5) * 5
    current_pos := start_snapped_screen + unit_vec * (rounded_dist_in_feet * tile_map.feet_to_pixels)

    end_pos_tile : TileMapPosition = screen_coord_to_tile_map(current_pos, state, tile_map)

    max_dist_in_feet := tile_distance(tile_map, start_mouse_tile, end_pos_tile)

    draw_cone_tiles(tile_map, start_mouse_tile, end_pos_tile, state.selected_color, action)

    action.tool = .CONE
    action.start = start_mouse_tile
    action.end = end_pos_tile
    action.color = state.selected_color
    action.performed = true


    builder := strings.builder_make(context.temp_allocator)
    strings.write_string(&builder, fmt.aprintf("%.1f", max_dist_in_feet, allocator=context.temp_allocator))
    return strings.to_cstring(&builder) or_else BUILDER_FAILED
}


draw_cone_tiles :: proc(tile_map: ^TileMap, start: TileMapPosition, end: TileMapPosition, color: [4]u8, action: ^Action) {
    screen_start_snapped := tile_map_to_screen_coord_full(start, state, tile_map)
    end_screen := tile_map_to_screen_coord_full(end, state, tile_map)

    axis_vec := screen_start_snapped - end_screen
    left_vec : [2]f32 = {-axis_vec.y, axis_vec.x}
    right_vec : [2]f32 = {axis_vec.y, -axis_vec.x}
    left_vec = rl.Vector2Normalize(left_vec)
    right_vec = rl.Vector2Normalize(right_vec)
    half_dist := dist(screen_start_snapped, end_screen)/2

    left_vec = left_vec * half_dist
    right_vec = right_vec * half_dist

    left_point := left_vec + end_screen
    right_point := right_vec + end_screen

    // Draw line outline
    //rl.DrawLineV(screen_start_snapped, left_point, {0, 0, 0, 255})
    //rl.DrawLineV(screen_start_snapped, right_point, {0, 0, 0, 255})
    //rl.DrawLineV(right_point, left_point, {0, 0, 0, 255})

    p1 := screen_start_snapped
    p2 := left_point
    p3 := right_point

    // Compute bounding box
    min_x := math.floor_f32(math.min(p1.x, p2.x, p3.x))
    max_x := math.ceil_f32(math.max(p1.x, p2.x, p3.x))
    min_y := math.floor_f32(math.min(p1.y, p2.y, p3.y))
    max_y := math.ceil_f32(math.max(p1.y, p2.y, p3.y))


    seen: map[[2]u32] bool
    seen.allocator = context.temp_allocator

    //TODO(amatej): this iterates over pixels, its not great
    for y : f32 = min_y; y <= max_y; y += f32(tile_map.tile_side_in_pixels - 1) {
        for x : f32 = min_x; x <= max_x; x += f32(tile_map.tile_side_in_pixels - 1) {
            tile_pos : TileMapPosition = screen_coord_to_tile_map({x, y}, state, tile_map)
            pos_snapped := tile_map_to_screen_coord(tile_pos, state, tile_map)
            _, ok := &seen[tile_pos.abs_tile]
            if ok {
                continue
            }

            seen[tile_pos.abs_tile] = true
            // Compute barycentric coordinates
            denom := ((p2.y - p3.y)*(p1.x - p3.x) + (p3.x - p2.x)*(p1.y - p3.y))
            if denom == 0 {
                continue  // degenerate triangle
            }
            a := ((p2.y - p3.y)*(pos_snapped.x - p3.x) + (p3.x - p2.x)*(pos_snapped.y - p3.y)) / denom
            b := ((p3.y - p1.y)*(pos_snapped.x - p3.x) + (p1.x - p3.x)*(pos_snapped.y - p3.y)) / denom
            c := 1 - a - b
            if a >= 0 && b >= 0 && c >= 0 {
                old_tile := get_tile(tile_map, tile_pos.abs_tile)
                new_tile := tile_make_color_walls_colors(color_over(color.xyzw, old_tile.color.xyzw), old_tile.walls, old_tile.wall_colors)
                if action != nil{
                    action.tile_history[tile_pos.abs_tile] = tile_subtract(&old_tile, &new_tile)
                }
                set_tile(tile_map, tile_pos.abs_tile, new_tile)
            }
        }
    }
}
