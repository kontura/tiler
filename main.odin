package gridimpro

import "core:math"
import "core:fmt"

import rl "vendor:raylib"

INIT_SCREEN_WIDTH: i32 : 1280
INIT_SCREEN_HEIGHT: i32 : 720

GameState :: struct {
    screen_width: i32,
    screen_height: i32,
    camera_pos: TileMapPosition
}

main :: proc() {
    rl.InitWindow(INIT_SCREEN_WIDTH, INIT_SCREEN_HEIGHT, "GridImpro")
    player_run_texture := rl.LoadTexture("wolf-token.png")

    state : GameState
    state.camera_pos.abs_tile_x = 100
    state.camera_pos.abs_tile_y = 100
    state.camera_pos.rel_tile_x = 0.0
    state.camera_pos.rel_tile_y = 0.0
    state.screen_height = rl.GetScreenHeight()
    state.screen_width = rl.GetScreenWidth()

    tile_map: TileMap
    tile_map.chunk_shift = 8
    tile_map.chunk_mask = (1 << tile_map.chunk_shift) - 1
    tile_map.chunk_dim = (1 << tile_map.chunk_shift)
    tile_map.tile_chunk_count_x = 4
    tile_map.tile_chunk_count_y = 4

    tile_map.tile_chunks = make([dynamic]TileChunk, tile_map.tile_chunk_count_x * tile_map.tile_chunk_count_y)

    for y : u32 = 0; y < tile_map.tile_chunk_count_y; y += 1 {
        for x : u32 = 0; x < tile_map.tile_chunk_count_x; x += 1 {
            tile_map.tile_chunks[y * tile_map.tile_chunk_count_x + x].tiles = make([dynamic]Tile, tile_map.chunk_dim * tile_map.chunk_dim)
        }
    }
    tile_map.tile_side_in_feet = 5
    tile_map.tile_side_in_pixels = 30
    tile_map.feet_to_pixels = f32(tile_map.tile_side_in_pixels) / tile_map.tile_side_in_feet

    tiles_per_width : u32 = 17
    tiles_per_height : u32 = 9

    for screen_y : u32 = 0; screen_y < 32; screen_y += 1 {
        for screen_x : u32 = 0; screen_x < 32; screen_x += 1 {
            for tile_y : u32 = 0; tile_y < 32; tile_y += 1 {
                for tile_x : u32 = 0; tile_x < 32; tile_x += 1 {
                    abs_tile_x : u32 = screen_x * tiles_per_width + tile_x
                    abs_tile_y : u32 = screen_y * tiles_per_height + tile_y

                    set_tile_value(&tile_map, abs_tile_x, abs_tile_y, ((tile_x == tile_y) && (tile_y % 2) == 0) ? {0,55,0,255}:{0,0,55,255})
                }
            }
        }
    }


    for !rl.WindowShouldClose() {
        rl.BeginDrawing()
        rl.ClearBackground(rl.GRAY)

        if rl.IsKeyDown(.LEFT) {
            state.camera_pos.abs_tile_x -= 1
        } else if rl.IsKeyDown(.RIGHT) {
            state.camera_pos.abs_tile_x += 1
        } else if rl.IsKeyDown(.DOWN) {
            state.camera_pos.abs_tile_y += 1
        } else if rl.IsKeyDown(.UP) {
            state.camera_pos.abs_tile_y -= 1
        } else if rl.IsKeyDown(.J) {
            tile_map.tile_side_in_pixels -= 1
            tile_map.tile_side_in_pixels = math.max(2, tile_map.tile_side_in_pixels)
            fmt.println(tile_map.tile_side_in_pixels)
            tile_map.feet_to_pixels = f32(tile_map.tile_side_in_pixels) / tile_map.tile_side_in_feet
        } else if rl.IsKeyDown(.K) {
            tile_map.tile_side_in_pixels += 1
            fmt.println(tile_map.tile_side_in_pixels)
            tile_map.feet_to_pixels = f32(tile_map.tile_side_in_pixels) / tile_map.tile_side_in_feet
        } else if rl.IsKeyDown(.Q) {
            break
        } else {
        }
        state.camera_pos = recanonicalize_position(&tile_map, state.camera_pos)

        rl.DrawRectangleV({0, 0}, {f32(state.screen_width), f32(state.screen_height)}, rl.RED)

        screen_center : rl.Vector2 = {f32(state.screen_width), f32(state.screen_height)} * 0.5

        for row_offset : i32 = -20; row_offset < 20; row_offset += 1 {
            for column_offset : i32 = -30; column_offset < 30; column_offset += 1 {
                current_tile: [2]u32
                current_tile.x = (state.camera_pos.abs_tile_x) + u32(column_offset);
                current_tile.y = (state.camera_pos.abs_tile_y) + u32(row_offset)

                current_tile_value : Tile = get_tile_value(&tile_map, current_tile.x, current_tile.y)

                //current_tile_value.r = current_tile_value.r + u8(f32(column_offset + 20)) * 4;
                //current_tile_value.b = current_tile_value.b + u8(f32(row_offset + 20)) * 4;
                if (row_offset == 0) && column_offset == 0 {
                    current_tile_value = {0,0,0,255}
                }

                // Calculate tile position on screen
                cen_x : f32 = screen_center.x - tile_map.feet_to_pixels * state.camera_pos.rel_tile_x + f32(column_offset * tile_map.tile_side_in_pixels)
                cen_y : f32 = screen_center.y - tile_map.feet_to_pixels * state.camera_pos.rel_tile_y + f32(row_offset * tile_map.tile_side_in_pixels)
                min_x : f32 = cen_x - 0.5 * f32(tile_map.tile_side_in_pixels)
                min_y : f32 = cen_y - 0.5 * f32(tile_map.tile_side_in_pixels)
                min_x = math.max(0, min_x)
                min_y = math.max(0, min_y)
                rl.DrawRectangleV({min_x, min_y}, {f32(tile_map.tile_side_in_pixels), f32(tile_map.tile_side_in_pixels)}, {current_tile_value.r, current_tile_value.g, current_tile_value.b, current_tile_value.a})
            }
        }


        //m_pos := rl.GetMousePosition()
        //fmt.println(m_pos)

        //rl.DrawTextureV(player_run_texture, {64, 64}, rl.WHITE)

        rl.EndDrawing()
    }

    rl.CloseWindow()
}

