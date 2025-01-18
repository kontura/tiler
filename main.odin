package tiler

import "core:math"
import "core:fmt"
import "core:mem"
import "core:strings"

import rl "vendor:raylib"

INIT_SCREEN_WIDTH: i32 : 1280
INIT_SCREEN_HEIGHT: i32 : 720

INITIATIVE_COUNT : i32 : 50

GameState :: struct {
    screen_width: i32,
    screen_height: i32,
    camera_pos: TileMapPosition,
    selected_color: [4]u8,
    gui_rectangles: map[Widget]rl.Rectangle,
    draw_grid: bool,
    draw_initiative: bool,
    active_tool: Tool,
    previous_tool: Maybe(Tool),
    tool_start_position: Maybe([2]f32),
    selected_token: u64,
    max_entity_id: u64,
    //TODO(amatej): check if the tool actually does any color change before recoding
    //              undoing non-color changes does nothing
    undo_history: [dynamic]Action,
    tokens: map[u64]Token,
    initiative_to_tokens: map[i32][dynamic]u64,
    // Valid only for one loop
    temp_actions: [dynamic]Action,
    key_consumed: bool,
}

Widget :: enum {
    MAP,
    COLORPICKER,
    COLORBARHUE,
    INITIATIVE,
}

u64_to_cstring :: proc(num: u64) -> cstring{
    builder := strings.builder_make(context.temp_allocator)
    strings.write_u64(&builder, num)
    return strings.to_cstring(&builder)
}

screen_coord_to_tile_map :: proc(pos: rl.Vector2, state: ^GameState, tile_map: ^TileMap) -> TileMapPosition {
    res: TileMapPosition = state.camera_pos

    delta: rl.Vector2 = pos

    screen_center : rl.Vector2 = {f32(state.screen_width), f32(state.screen_height)} * 0.5
    delta -= screen_center

    res.rel_tile.x += delta.x * f32(tile_map.pixels_to_feet)
    res.rel_tile.y += delta.y * f32(tile_map.pixels_to_feet)

    res = recanonicalize_position(tile_map, res)

    //TODO(amatej): Maybe we also want to know where in the tile the mouse is,
    //              we would need to set rel_tile.

    return res
}

find_token_at_screen :: proc(tile_map: ^TileMap, state: ^GameState, pos: rl.Vector2) -> ^Token {
    for _, &token in state.tokens {
        if rl.CheckCollisionPointCircle(pos, get_token_circle(tile_map, state, token)) {
            return &token
        }
    }

    return nil
}

tile_map_to_screen_coord :: proc(pos: TileMapPosition, state: ^GameState, tile_map: ^TileMap) -> rl.Vector2 {
    res : rl.Vector2 = {f32(state.screen_width), f32(state.screen_height)} * 0.5

    delta: [2]i32 = {i32(pos.abs_tile.x), i32(pos.abs_tile.y)}
    delta -= {i32(state.camera_pos.abs_tile.x), i32(state.camera_pos.abs_tile.y)}

    res.x += f32(delta.x * tile_map.tile_side_in_pixels)
    res.y += f32(delta.y * tile_map.tile_side_in_pixels)

    res -= state.camera_pos.rel_tile * tile_map.feet_to_pixels

    return res
}

state: ^GameState
tile_map: ^TileMap

init :: proc() {

    rl.InitWindow(INIT_SCREEN_WIDTH, INIT_SCREEN_HEIGHT, "GridImpro")
    player_run_texture := rl.LoadTexture("wolf-token.png")

    // Since we don't run any simulation we don't have to run when there is not user input
    rl.EnableEventWaiting()

    state = new(GameState)
    state.camera_pos.abs_tile.x = 100
    state.camera_pos.abs_tile.y = 100
    state.camera_pos.rel_tile.x = 0.0
    state.camera_pos.rel_tile.y = 0.0
    state.screen_height = rl.GetScreenHeight()
    state.screen_width = rl.GetScreenWidth()
    state.draw_grid = true
    state.draw_initiative = true
    state.active_tool = Tool.RECTANGLE
    state.selected_color.a = 255
    // entity id 0 is reserved for temporary preview entity
    state.max_entity_id = 1

    tile_map = new(TileMap)
    tile_map.chunk_shift = 8
    tile_map.chunk_mask = (1 << tile_map.chunk_shift) - 1
    tile_map.chunk_dim = (1 << tile_map.chunk_shift)
    tile_map.tile_chunk_count = {4, 4}

    tile_map.tile_chunks = make([dynamic]TileChunk, tile_map.tile_chunk_count.x * tile_map.tile_chunk_count.y)

    for y : u32 = 0; y < tile_map.tile_chunk_count.y; y += 1 {
        for x : u32 = 0; x < tile_map.tile_chunk_count.x; x += 1 {
            tile_map.tile_chunks[y * tile_map.tile_chunk_count.x + x].tiles = make([dynamic]Tile, tile_map.chunk_dim * tile_map.chunk_dim)
            for i: u32 = 0; i < tile_map.chunk_dim * tile_map.chunk_dim; i += 1 {
                tile_map.tile_chunks[y * tile_map.tile_chunk_count.x + x].tiles[i] = { {77, 77, 77, 255} }
            }
        }
    }
    tile_map.tile_side_in_feet = 5
    tile_map.tile_side_in_pixels = 30
    tile_map.feet_to_pixels = f32(tile_map.tile_side_in_pixels) / tile_map.tile_side_in_feet
    tile_map.pixels_to_feet = tile_map.tile_side_in_feet / f32(tile_map.tile_side_in_pixels)

    tiles_per_width : u32 = 17
    tiles_per_height : u32 = 9
}

update :: proc() {
    rl.BeginDrawing()
    rl.ClearBackground(rl.BLACK)

    state.screen_height = rl.GetScreenHeight()
    state.screen_width = rl.GetScreenWidth()
    state.gui_rectangles[.COLORPICKER] = {f32(state.screen_width - 230), 10, 200, 200}
    state.gui_rectangles[.COLORBARHUE] = {f32(state.screen_width - 30), 5, 30, 205}
    if state.draw_initiative {
        state.gui_rectangles[.INITIATIVE] = {0,0,120, f32(state.screen_height)}
    }

    state.temp_actions = make([dynamic]Action, context.temp_allocator)
    state.key_consumed = false

    icon : rl.GuiIconName
    //TODO(amatej): convert to temp action
    highligh_current_tile := false
    token := find_token_at_screen(tile_map, state, rl.GetMousePosition())
    mouse_tile_pos : TileMapPosition = screen_coord_to_tile_map(rl.GetMousePosition(), state, tile_map)

    selected_widget : Widget= .MAP
    for widget, &rec in state.gui_rectangles {
        if (rl.CheckCollisionPointRec(rl.GetMousePosition(), rec)) {
            selected_widget = widget
        }
    }

    // Mouse clicks
    if rl.IsMouseButtonPressed(.LEFT) {
        if (state.tool_start_position == nil) {
            state.tool_start_position = rl.GetMousePosition()
            append(&state.undo_history, Action{})
        }
    } else if rl.IsMouseButtonDown(.RIGHT) {
        state.camera_pos.rel_tile -= rl.GetMouseDelta()
    }

    switch state.active_tool {
    case .BRUSH: {
        if selected_widget == .MAP {
            if rl.IsMouseButtonDown(.LEFT) {
                action : ^Action = &state.undo_history[len(state.undo_history)-1]
                if (!(mouse_tile_pos.abs_tile in action.tile_history)) {
                    action.tile_history[mouse_tile_pos.abs_tile] = get_tile(tile_map, mouse_tile_pos.abs_tile)
                }
                set_tile_value(tile_map, mouse_tile_pos.abs_tile, {state.selected_color})
            }
        }
        icon = .ICON_PENCIL
        highligh_current_tile = true
    }
    case .RECTANGLE: {
        if rl.IsMouseButtonDown(.LEFT) {
            action : ^Action = &state.undo_history[len(state.undo_history)-1]
            append(&state.temp_actions, make_action(context.temp_allocator))
            temp_action : ^Action = &state.temp_actions[len(state.temp_actions)-1]
            rectangle_tool(state, tile_map, rl.GetMousePosition(), temp_action)
        } else if rl.IsMouseButtonReleased(.LEFT) {
            if (state.tool_start_position != nil) {
                action : ^Action = &state.undo_history[len(state.undo_history)-1]
                rectangle_tool(state, tile_map, rl.GetMousePosition(), action)
            }
        }
        icon = .ICON_BOX
        highligh_current_tile = true
    }
    case .MOVE_TOKEN: {
        if rl.IsMouseButtonDown(.LEFT) {
            action : ^Action = &state.undo_history[len(state.undo_history)-1]
            append(&state.temp_actions, make_action(context.temp_allocator))
            temp_action : ^Action = &state.temp_actions[len(state.temp_actions)-1]
            move_token_tool(state, tile_map, rl.GetMousePosition(), temp_action, true)
        } else if rl.IsMouseButtonReleased(.LEFT) {
            if (state.tool_start_position != nil) {
                action : ^Action = &state.undo_history[len(state.undo_history)-1]
                move_token_tool(state, tile_map, rl.GetMousePosition(), action, false)
            }
        }
        icon = .ICON_TARGET_MOVE
    }
    case .COLOR_PICKER: {
        if selected_widget == .MAP {
            if rl.IsMouseButtonPressed(.LEFT) {
                mouse_tile : Tile = get_tile(tile_map, mouse_tile_pos.abs_tile)
                state.selected_color = mouse_tile.color
            }
            icon = .ICON_COLOR_PICKER
        }
    }
    case .EDIT_TOKEN: {
        #partial switch selected_widget {
        case .MAP: {
            if token != nil {
                key := rl.GetKeyPressed()
                if rl.IsKeyDown(.BACKSPACE) {
                    key = .BACKSPACE
                }
                byte : u8 = u8(key)
                if byte != 0 {
                    builder : strings.Builder
                    strings.write_string(&builder, token.name)
                    #partial switch key {
                    case .BACKSPACE:
                        strings.pop_rune(&builder)
                    case .MINUS: {
                        if token.size > 1 {
                            token.size -= 1
                        }
                    }
                    case .EQUAL: {
                        if token.size < 10 && (rl.IsKeyDown(.RIGHT_SHIFT) || rl.IsKeyDown(.LEFT_SHIFT)) {
                            token.size += 1
                        }
                    }
                    case .RIGHT_SHIFT, .LEFT_SHIFT: {
                    }
                    case:
                        strings.write_byte(&builder, byte)
                    }
                    delete(token.name)
                    token.name = strings.to_string(builder)
                    state.key_consumed = true
                }
            } else if rl.IsMouseButtonPressed(.LEFT) {
                t := make_token(state.max_entity_id, mouse_tile_pos, state.selected_color)
                state.tokens[t.id] =  t
                if state.initiative_to_tokens[t.initiative] == nil {
                    state.initiative_to_tokens[t.initiative] = make([dynamic]u64)
                }
                append(&state.initiative_to_tokens[t.initiative], t.id)
                append(&state.undo_history, Action{})
                action : ^Action = &state.undo_history[len(state.undo_history)-1]
                action.token_history[state.max_entity_id] = nil
                state.max_entity_id += 1
            } else {
                c := state.selected_color
                c.a = 90
                state.tokens[0] = make_token(0, mouse_tile_pos, c, " ")
                append(&state.temp_actions, make_action(context.temp_allocator))
                temp_action : ^Action = &state.temp_actions[len(state.temp_actions)-1]
                temp_action.token_history[0] = nil
            }
            icon = .ICON_PLAYER
        }
        case .INITIATIVE: {
            if rl.IsMouseButtonDown(.LEFT) {
                move_initiative_token_tool(state, rl.GetMousePosition(), nil)
            } else if rl.IsMouseButtonReleased(.LEFT) {
                if (state.tool_start_position != nil) {
                    action : ^Action = &state.undo_history[len(state.undo_history)-1]
                    move_initiative_token_tool(state, rl.GetMousePosition(), action)
                }
                state.selected_token = 0
            }
            icon = .ICON_SHUFFLE
        }
        }
    }
    }

    if rl.IsMouseButtonReleased(.LEFT) {
        if (state.tool_start_position != nil) {
            state.tool_start_position = nil
        }
    }

    // Keybinds
    if !state.key_consumed {
        if rl.IsKeyDown(.LEFT) || rl.IsKeyDown(.H) {
            state.camera_pos.rel_tile.x -= 10
        } else if rl.IsKeyDown(.RIGHT) || rl.IsKeyDown(.L) {
            state.camera_pos.rel_tile.x += 10
        } else if rl.IsKeyDown(.DOWN) || rl.IsKeyDown(.J) {
            state.camera_pos.rel_tile.y += 10
        } else if rl.IsKeyDown(.UP) || rl.IsKeyDown(.K) {
            state.camera_pos.rel_tile.y -= 10
        } else if rl.IsKeyPressed(.P) {
            state.active_tool = .BRUSH
        } else if rl.IsKeyPressed(.R) {
            state.active_tool = .RECTANGLE
        } else if rl.IsKeyPressed(.S) {
            state.active_tool = .EDIT_TOKEN
        } else if rl.IsKeyPressed(.M) {
            state.active_tool = .MOVE_TOKEN
        } else if rl.IsKeyPressed(.I) {
            state.draw_initiative = !state.draw_initiative
        } else if rl.IsKeyPressed(.G) {
            state.draw_grid = !state.draw_grid
        } else if rl.IsKeyReleased(.Z) && rl.IsKeyDown(.LEFT_CONTROL) {
            if len(state.undo_history) > 0 {
                action : ^Action = &state.undo_history[len(state.undo_history)-1]
                undo_action(state, tile_map, action)
                pop_last_action(state, tile_map, &state.undo_history)
            }
        } else if rl.IsKeyPressed(.LEFT_CONTROL) {
            if state.previous_tool == nil{
                state.previous_tool = state.active_tool
                state.active_tool = .COLOR_PICKER
            }
        } else if rl.IsKeyReleased(.LEFT_CONTROL) {
            if state.previous_tool != nil {
                state.active_tool = state.previous_tool.?
                state.previous_tool = nil
            }
        }
    }

    state.camera_pos = recanonicalize_position(tile_map, state.camera_pos)

    tile_map.tile_side_in_pixels += i32(rl.GetMouseWheelMove())
    tile_map.tile_side_in_pixels = math.max(5, tile_map.tile_side_in_pixels)
    tile_map.feet_to_pixels = f32(tile_map.tile_side_in_pixels) / tile_map.tile_side_in_feet
    tile_map.pixels_to_feet = tile_map.tile_side_in_feet / f32(tile_map.tile_side_in_pixels)

    screen_center : rl.Vector2 = {f32(state.screen_width), f32(state.screen_height)} * 0.5

    // draw tile map
    tiles_needed_to_fill_half_of_screen := screen_center / f32(tile_map.tile_side_in_pixels)
    for row_offset : i32 = i32(math.floor(-tiles_needed_to_fill_half_of_screen.y)); row_offset <= i32(math.ceil(tiles_needed_to_fill_half_of_screen.y)); row_offset += 1 {
        cen_y : f32 = screen_center.y - tile_map.feet_to_pixels * state.camera_pos.rel_tile.y + f32(row_offset * tile_map.tile_side_in_pixels)
        min_y : f32 = cen_y - 0.5 * f32(tile_map.tile_side_in_pixels)

        for column_offset : i32 = i32(math.floor(-tiles_needed_to_fill_half_of_screen.x)); column_offset <= i32(math.ceil(tiles_needed_to_fill_half_of_screen.x)); column_offset += 1 {
            current_tile: [2]u32
            current_tile.x = (state.camera_pos.abs_tile.x) + u32(column_offset)
            current_tile.y = (state.camera_pos.abs_tile.y) + u32(row_offset)

            current_tile_value : Tile = get_tile(tile_map, current_tile)

            mouse_tile : TileMapPosition = screen_coord_to_tile_map(rl.GetMousePosition(), state, tile_map)

            if (current_tile.y == mouse_tile.abs_tile.y) && (current_tile.x == mouse_tile.abs_tile.x) && highligh_current_tile {
                current_tile_value = {state.selected_color}
            }

            // Calculate tile position on screen
            cen_x : f32 = screen_center.x - tile_map.feet_to_pixels * state.camera_pos.rel_tile.x + f32(column_offset * tile_map.tile_side_in_pixels)
            min_x : f32 = cen_x - 0.5 * f32(tile_map.tile_side_in_pixels)
            rl.DrawRectangleV({min_x, min_y},
                             {f32(tile_map.tile_side_in_pixels), f32(tile_map.tile_side_in_pixels)},
                             current_tile_value.color.xyzw)
        }

        if (state.draw_grid) {
            rl.DrawLineV({0, min_y}, {f32(state.screen_width), min_y}, {0,0,0,20})
        }
    }

    // draw tokens on map
    for _, &token in state.tokens {
        pos: rl.Vector2 = tile_map_to_screen_coord(token.position, state, tile_map)
        rl.DrawCircleV(get_token_circle(tile_map, state, token), token.color.xyzw)
        rl.DrawText(get_token_name_temp(&token), i32(pos.x)-tile_map.tile_side_in_pixels/2, i32(pos.y)+tile_map.tile_side_in_pixels/2, 18, rl.WHITE)
        if (token.moved != 0) {
            rl.DrawText(u64_to_cstring(u64(f32(token.moved) * tile_map.tile_side_in_feet)), i32(pos.x)-tile_map.tile_side_in_pixels, i32(pos.y)-tile_map.tile_side_in_pixels, 28, rl.WHITE)
        }
    }

    // draw initiative tracker
    if (state.draw_initiative) {
        rl.DrawRectangleGradientEx(state.gui_rectangles[.INITIATIVE], {40,40,40,45}, {40,40,40,45}, {0,0,0,0}, {0,0,0,0})
        row_offset : i32 = 10
        for i : i32 = 1; i < INITIATIVE_COUNT; i += 1 {
            tokens := state.initiative_to_tokens[i]
            if (tokens == nil || len(tokens) == 0) {
                if state.active_tool == .EDIT_TOKEN {
                    rl.DrawText(u64_to_cstring(u64(i)), 10, row_offset, 10, rl.GRAY)
                    row_offset += 13
                } else {
                    continue
                }
            } else {
                row_offset += 3
                rl.DrawText(u64_to_cstring(u64(i)), 10, row_offset, 10, rl.GRAY)
                for token_id in tokens {
                    token := state.tokens[token_id]
                    token_size :=  f32(token.size) * 4 + 10
                    half_of_this_row := i32(token_size + 3)
                    rl.DrawCircleV({30 + token_size/2, f32(row_offset + half_of_this_row)}, f32(token_size), token.color.xyzw)
                    rl.DrawText(get_token_name_temp(&token), i32(30 + token_size + 15), row_offset + i32(token_size) - 4, 18, rl.WHITE)
                    row_offset += 2 * half_of_this_row
                }
            }
            rl.DrawRectangleGradientH(0, row_offset, 100, 2, {40,40,40,155}, {0,0,0,0})
        }
    }

    if (state.draw_grid) {
        for column_offset : i32 = i32(math.floor(-tiles_needed_to_fill_half_of_screen.x)); column_offset <= i32(math.ceil(tiles_needed_to_fill_half_of_screen.x)); column_offset += 1 {
            cen_x : f32 = screen_center.x - tile_map.feet_to_pixels * state.camera_pos.rel_tile.x + f32(column_offset * tile_map.tile_side_in_pixels)
            min_x : f32 = cen_x - 0.5 * f32(tile_map.tile_side_in_pixels)
            min_x = math.max(0, min_x)
            rl.DrawLineV({min_x, 0}, {min_x, f32(state.screen_height)}, {0,0,0,20})
        }
    }

    if state.active_tool == .COLOR_PICKER {
        rl.GuiColorPicker(state.gui_rectangles[.COLORPICKER], "color picker", (^rl.Color)(&state.selected_color))
    }

    //player_img := rl.LoadImageFromTexture(player_run_texture)
    //rl.ImageResize(&player_img, tile_map.tile_side_in_pixels, tile_map.tile_side_in_pixels)
    //scaled_player_texture := rl.LoadTextureFromImage(player_img)
    //rl.DrawTextureV(scaled_player_texture, {64, 64}, rl.WHITE)

    mouse_pos: [2]f32 = rl.GetMousePosition()
    rl.GuiDrawIcon(icon, i32(mouse_pos.x) - 4, i32(mouse_pos.y) - 30, 2, rl.WHITE)

    // Before ending the loop revert the last action from history if it is temp
    for _, index in state.temp_actions {
        undo_action(state, tile_map, &state.temp_actions[index])
    }
    clear(&state.temp_actions)

    rl.EndDrawing()
    free_all(context.temp_allocator)
}

shutdown :: proc() {
    rl.CloseWindow()
    delete(state.gui_rectangles)
    for _, &token_ids in state.initiative_to_tokens {
        delete(token_ids)
    }
    delete(state.initiative_to_tokens)
    for _, &token in state.tokens {
        delete_token(&token)
    }
    delete(state.tokens)
    for _, index in state.undo_history {
        delete_action(&state.undo_history[index])
    }
    delete(state.undo_history)
    for y : u32 = 0; y < tile_map.tile_chunk_count.y; y += 1 {
        for x : u32 = 0; x < tile_map.tile_chunk_count.x; x += 1 {
            delete(tile_map.tile_chunks[y * tile_map.tile_chunk_count.x + x].tiles)
        }
    }
    delete(tile_map.tile_chunks)

    free(state)
    free(tile_map)

}

// In a web build, this is called when browser changes size. Remove the
// `rl.SetWindowSize` call if you don't want a resizable game.
game_parent_window_size_changed :: proc(w, h: int) {
	rl.SetWindowSize(i32(w), i32(h))
}

main :: proc() {
    when ODIN_DEBUG {
        track: mem.Tracking_Allocator
        mem.tracking_allocator_init(&track, context.allocator)
        context.allocator = mem.tracking_allocator(&track)
        defer {
            if len(track.allocation_map) > 0 {
                fmt.eprintf("=== %v allocations not freed: ===\n", len(track.allocation_map))
                for _, entry in track.allocation_map {
                    fmt.eprintf("- %v bytes @ %v\n", entry.size, entry.location)
                }
            }
            if len(track.bad_free_array) > 0 {
                fmt.eprintf("=== %v incorrect frees: ===\n", len(track.bad_free_array))
                for entry in track.bad_free_array {
                    fmt.eprintf("- %p @ %v\n", entry.memory, entry.location)
                }
            }
            mem.tracking_allocator_destroy(&track)
        }
    }
    init()
    for !rl.WindowShouldClose() {
        update()
    }
    shutdown()
}
