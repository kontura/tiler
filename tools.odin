package tiler

import "core:math"
import "core:fmt"
import "core:strings"

Tool :: enum {
    BRUSH,
    RECTANGLE,
    COLOR_PICKER,
    CIRCLE,
    EDIT_TOKEN,
    MOVE_TOKEN,
}

dist :: proc($T: typeid, p1: [2]T, p2: [2]T) -> f32 {
    dx := f32(p2.x) - f32(p1.x)
    dx *= dx
    dy := f32(p2.y) - f32(p1.y)
    dy *= dy

    return math.sqrt_f32(dx + dy)
}

circle_tool :: proc(state: ^GameState,  tile_map: ^TileMap, current_pos: [2]f32, action: ^Action) -> cstring {
    start_mouse_tile : TileMapPosition = screen_coord_to_tile_map(state.tool_start_position.?, state, tile_map)

    half := tile_map.tile_side_in_feet/2
    start_mouse_tile.rel_tile.x = start_mouse_tile.rel_tile.x >= 0 ? half : -half
    start_mouse_tile.rel_tile.y = start_mouse_tile.rel_tile.y >= 0 ? half : -half

    current_mouse_tile : TileMapPosition = screen_coord_to_tile_map(current_pos, state, tile_map)

    max_dist_in_feet := tile_distance(tile_map, start_mouse_tile, current_mouse_tile)
    max_dist_up := u32(math.ceil_f32(max_dist_in_feet))

    start_tile : [2]u32 = {start_mouse_tile.abs_tile.x - max_dist_up, start_mouse_tile.abs_tile.y - max_dist_up}
    end_tile : [2]u32 = {start_mouse_tile.abs_tile.x + max_dist_up, start_mouse_tile.abs_tile.y + max_dist_up}

    for y : u32 = start_tile.y; y <= end_tile.y; y += 1 {
        for x : u32 = start_tile.x; x <= end_tile.x; x += 1 {
            temp_tile_pos: TileMapPosition = {{x,y}, {0,0}}

            dist := tile_distance(tile_map, temp_tile_pos, start_mouse_tile)

            if (max_dist_in_feet > dist) {
                action.tile_history[{x,y}] = get_tile(tile_map, {x, y})
                set_tile_value(tile_map, {x, y}, {state.selected_color.xyzw, {}})
            }
        }
    }

    builder := strings.builder_make(context.temp_allocator)
    strings.write_string(&builder, fmt.aprintf("%.1f", max_dist_in_feet, allocator=context.temp_allocator))
    return strings.to_cstring(&builder)
}

rectangle_tool :: proc(state: ^GameState,  tile_map: ^TileMap, end_pos: [2]f32, action: ^Action) -> cstring {
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

    builder := strings.builder_make(context.temp_allocator)
    strings.write_string(&builder, fmt.aprintf("%.0fx%.0f",
                                               abs(f32(start_tile.x) - f32(end_tile.x)) * 5,
                                               abs(f32(start_tile.y) - f32(end_tile.y)) * 5,
                                               allocator=context.temp_allocator))
    return strings.to_cstring(&builder)
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

move_initiative_token_tool :: proc(state: ^GameState, end_pos: [2]f32, action: ^Action) {
    if state.selected_token == 0 {
        _, _, state.selected_token = find_at_initiative(state, state.tool_start_position.?.y)
    } else {
        end_initiative, end_index, _ := find_at_initiative(state, end_pos.y)
        init, i := remove_token_by_id_from_initiative(state, state.selected_token)
        if action != nil {
            action.token_initiative_history[state.selected_token] = [2]i32{init, i}
        }
        remove_token_by_id_from_initiative(state, state.selected_token)
        if state.initiative_to_tokens[end_initiative] == nil {
            state.initiative_to_tokens[end_initiative] = make([dynamic]u64)
        }
        tokens := &state.initiative_to_tokens[end_initiative]
        if i32(len(tokens)) >= end_index {
            inject_at(tokens, end_index, state.selected_token)
        } else {
            append(tokens, state.selected_token)
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
