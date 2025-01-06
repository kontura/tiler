package gridimpro

import "core:math"
import "core:fmt"

import rl "vendor:raylib"

INIT_SCREEN_WIDTH: i32 : 1280
INIT_SCREEN_HEIGHT: i32 : 720

GameState :: struct {
    screen_width: i32,
    screen_height: i32,
    camera_pos: TileMapPosition,
    selected_color: rl.Color,
    gui_rectangles: map[string]rl.Rectangle,
    draw_grid: bool,
    active_tool: Tool,
    tool_start_position: Maybe([2]f32),
    //TODO(amatej): Perhaps this could be integrated into undo?
    revert_temp_tile_color: map[[2]u32][4]u8,
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

main :: proc() {
    rl.InitWindow(INIT_SCREEN_WIDTH, INIT_SCREEN_HEIGHT, "GridImpro")
    player_run_texture := rl.LoadTexture("wolf-token.png")

    // Since we don't run any simulation we don't have to run when there is not user input
    rl.EnableEventWaiting()

    state : GameState
    state.camera_pos.abs_tile.x = 100
    state.camera_pos.abs_tile.y = 100
    state.camera_pos.rel_tile.x = 0.0
    state.camera_pos.rel_tile.y = 0.0
    state.screen_height = rl.GetScreenHeight()
    state.screen_width = rl.GetScreenWidth()
    state.draw_grid = true
    state.active_tool = Tool.RECTANGLE
    state.gui_rectangles = make(map[string]rl.Rectangle)
    state.gui_rectangles["colorpicker"] = {f32(state.screen_width - 230), 0, 200, 200}
    defer delete(state.gui_rectangles)

    tile_map: TileMap
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

    state.selected_color.a = 255

    tiles_per_width : u32 = 17
    tiles_per_height : u32 = 9

    for !rl.WindowShouldClose() {
        rl.BeginDrawing()
        rl.ClearBackground(rl.BLACK)

        state.screen_height = rl.GetScreenHeight()
        state.screen_width = rl.GetScreenWidth()

        if rl.IsKeyDown(.LEFT) || rl.IsKeyDown(.H) {
            state.camera_pos.rel_tile.x -= 10
        } else if rl.IsKeyDown(.RIGHT) || rl.IsKeyDown(.L) {
            state.camera_pos.rel_tile.x += 10
        } else if rl.IsKeyDown(.DOWN) || rl.IsKeyDown(.J) {
            state.camera_pos.rel_tile.y += 10
        } else if rl.IsKeyDown(.UP) || rl.IsKeyDown(.K) {
            state.camera_pos.rel_tile.y -= 10
        } else if rl.IsKeyDown(.Q) {
            break
        } else if rl.IsMouseButtonDown(.LEFT) {
            ui_active : bool = false
            for _, &rec in state.gui_rectangles {
                if (rl.CheckCollisionPointRec(rl.GetMousePosition(), rec)) {
                    ui_active = true
                }
            }

            if (!ui_active) {
                switch state.active_tool {
                    case .BRUSH: {
                        mouse_tile : TileMapPosition = screen_coord_to_tile_map(rl.GetMousePosition(), &state, &tile_map)
                        set_tile_value(&tile_map, mouse_tile.abs_tile, {state.selected_color.xyzw})
                    }
                    case .RECTANGLE: {
                        if (state.tool_start_position == nil) {
                            state.tool_start_position = rl.GetMousePosition()
                        }
                        rectangle_tool(&state, &tile_map, rl.GetMousePosition(), true)
                    }
                }
            }
        } else if rl.IsMouseButtonReleased(.LEFT) {
            if (state.tool_start_position != nil) {
                #partial switch state.active_tool {
                    case .RECTANGLE: {
                        rectangle_tool(&state, &tile_map, rl.GetMousePosition(), false)
                        state.tool_start_position = nil
                    }
                }
            }
        } else if rl.IsMouseButtonDown(.RIGHT) {
            state.camera_pos.rel_tile -= rl.GetMouseDelta()
        } else {
        }
        state.camera_pos = recanonicalize_position(&tile_map, state.camera_pos)

        tile_map.tile_side_in_pixels += i32(rl.GetMouseWheelMove())
        tile_map.tile_side_in_pixels = math.max(5, tile_map.tile_side_in_pixels)
        tile_map.feet_to_pixels = f32(tile_map.tile_side_in_pixels) / tile_map.tile_side_in_feet
        tile_map.pixels_to_feet = tile_map.tile_side_in_feet / f32(tile_map.tile_side_in_pixels)

        screen_center : rl.Vector2 = {f32(state.screen_width), f32(state.screen_height)} * 0.5

        tiles_needed_to_fill_half_of_screen := screen_center / f32(tile_map.tile_side_in_pixels)
        for row_offset : i32 = i32(math.floor(-tiles_needed_to_fill_half_of_screen.y)); row_offset <= i32(math.ceil(tiles_needed_to_fill_half_of_screen.y)); row_offset += 1 {
            cen_y : f32 = screen_center.y - tile_map.feet_to_pixels * state.camera_pos.rel_tile.y + f32(row_offset * tile_map.tile_side_in_pixels)
            min_y : f32 = cen_y - 0.5 * f32(tile_map.tile_side_in_pixels)
            min_y = math.max(0, min_y)

            for column_offset : i32 = i32(math.floor(-tiles_needed_to_fill_half_of_screen.x)); column_offset <= i32(math.ceil(tiles_needed_to_fill_half_of_screen.x)); column_offset += 1 {
                current_tile: [2]u32
                current_tile.x = (state.camera_pos.abs_tile.x) + u32(column_offset);
                current_tile.y = (state.camera_pos.abs_tile.y) + u32(row_offset)

                current_tile_value : Tile = get_tile_value(&tile_map, current_tile)

                mouse_tile : TileMapPosition = screen_coord_to_tile_map(rl.GetMousePosition(), &state, &tile_map)

                if (current_tile.y == mouse_tile.abs_tile.y) && (current_tile.x == mouse_tile.abs_tile.x) {
                    current_tile_value = {state.selected_color.xyzw}
                }

                // Calculate tile position on screen
                cen_x : f32 = screen_center.x - tile_map.feet_to_pixels * state.camera_pos.rel_tile.x + f32(column_offset * tile_map.tile_side_in_pixels)
                min_x : f32 = cen_x - 0.5 * f32(tile_map.tile_side_in_pixels)
                min_x = math.max(0, min_x)
                rl.DrawRectangleV({min_x, min_y},
                                 {f32(tile_map.tile_side_in_pixels), f32(tile_map.tile_side_in_pixels)},
                                 current_tile_value.color.xyzw)
            }

            if (state.draw_grid) {
                rl.DrawLineV({0, min_y}, {f32(state.screen_width), min_y}, {0,0,0,20})
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

        rl.DrawTextureV(player_run_texture, {64, 64}, rl.WHITE)
        ret := rl.GuiColorPanel(state.gui_rectangles["colorpicker"], "test", &state.selected_color)

        // Before ending the loop revert temp tile changes
        for abs_tile, &color in state.revert_temp_tile_color {
            set_tile_value(&tile_map, abs_tile, {color})
        }
        clear(&state.revert_temp_tile_color)

        rl.EndDrawing()
    }

    rl.CloseWindow()
}

