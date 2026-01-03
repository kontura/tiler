package tiler

import rl "vendor:raylib"
import "core:fmt"
import "core:math"
import "core:math/rand"

draw_grid_to_tex :: proc(state: ^GameState, tile_map: ^TileMap, tex: ^rl.RenderTexture) {
    screen_center: rl.Vector2 = {f32(state.screen_width), f32(state.screen_height)} * 0.5
    tiles_needed_to_fill_half_of_screen := screen_center / f32(tile_map.tile_side_in_pixels)
    rl.BeginTextureMode(tex^)
    {
        rl.ClearBackground({0, 0, 0, 0})
        // draw grid
        for row_offset: i32 = i32(math.floor(-tiles_needed_to_fill_half_of_screen.y));
            row_offset <= i32(math.ceil(tiles_needed_to_fill_half_of_screen.y));
            row_offset += 1 {
            cen_y: f32 =
                screen_center.y -
                tile_map.feet_to_pixels * state.camera_pos.rel_tile.y +
                f32(row_offset * tile_map.tile_side_in_pixels)
            min_y: f32 = cen_y - 0.5 * f32(tile_map.tile_side_in_pixels)
            rl.DrawLineV({0, min_y}, {f32(state.screen_width), min_y}, {0, 0, 0, 255})
        }
        for column_offset: i32 = i32(math.floor(-tiles_needed_to_fill_half_of_screen.x));
            column_offset <= i32(math.ceil(tiles_needed_to_fill_half_of_screen.x));
            column_offset += 1 {
            cen_x: f32 =
                screen_center.x -
                tile_map.feet_to_pixels * state.camera_pos.rel_tile.x +
                f32(column_offset * tile_map.tile_side_in_pixels)
            min_x: f32 = cen_x - 0.5 * f32(tile_map.tile_side_in_pixels)
            min_x = math.max(0, min_x)
            rl.DrawLineV({min_x, 0}, {min_x, f32(state.screen_height)}, {0, 0, 0, 255})
        }
    }
    rl.EndTextureMode()
}

get_scaled_rand_pair :: proc(state: ^GameState, tile_map: ^TileMap) -> [2]f32 {
    return [2]f32{f32(tile_map.tile_side_in_pixels) * (rand.float32(state.frame_deterministic_rng) - 0.5) * 3 * rand.float32(state.frame_deterministic_rng),
                  f32(tile_map.tile_side_in_pixels) * (rand.float32(state.frame_deterministic_rng) - 0.5) * 3 * rand.float32(state.frame_deterministic_rng)}
}

draw_grid_mask_to_tex :: proc(state: ^GameState, tile_map: ^TileMap, tex: ^rl.RenderTexture) {
    rl.BeginTextureMode(tex^)
    {
        rl.ClearBackground({0, 0, 0, 0})
        signs := [2]f32{1, -1}

        screen_center: rl.Vector2 = {f32(state.screen_width), f32(state.screen_height)} * 0.5
        tiles_needed_to_fill_half_of_screen := screen_center / f32(tile_map.tile_side_in_pixels)
        for row_offset: i32 = i32(math.floor(-tiles_needed_to_fill_half_of_screen.y));
            row_offset <= i32(math.ceil(tiles_needed_to_fill_half_of_screen.y));
            row_offset += 1 {
            cen_y: f32 =
                screen_center.y -
                tile_map.feet_to_pixels * state.camera_pos.rel_tile.y +
                f32(row_offset * tile_map.tile_side_in_pixels)
            min_y: f32 = cen_y - 0.5 * f32(tile_map.tile_side_in_pixels)

            for column_offset: i32 = i32(math.floor(-tiles_needed_to_fill_half_of_screen.x));
                column_offset <= i32(math.ceil(tiles_needed_to_fill_half_of_screen.x));
                column_offset += 1 {
                current_tile: [2]u32
                current_tile.x = (state.camera_pos.abs_tile.x) + u32(column_offset)
                current_tile.y = (state.camera_pos.abs_tile.y) + u32(row_offset)

                current_tile_value: Tile = get_tile(tile_map, current_tile)

                // Calculate tile position on screen
                cen_x: f32 =
                    screen_center.x -
                    tile_map.feet_to_pixels * state.camera_pos.rel_tile.x +
                    f32(column_offset * tile_map.tile_side_in_pixels)
                min_x: f32 = cen_x - 0.5 * f32(tile_map.tile_side_in_pixels)


                if Direction.TOP in current_tile_value.walls || Direction.LEFT in current_tile_value.walls {
                        rand.reset(u64(current_tile.x + current_tile.y), state.frame_deterministic_rng)
                        if rand.float32(state.frame_deterministic_rng) < 1.1 {
                            dist_x := (rand.float32_range(0.4, 1.8, state.frame_deterministic_rng) * rand.choice(signs[:], state.frame_deterministic_rng)) * f32(tile_map.tile_side_in_pixels)
                            dist_y := (rand.float32_range(0.4, 1.8, state.frame_deterministic_rng) * rand.choice(signs[:], state.frame_deterministic_rng)) * f32(tile_map.tile_side_in_pixels)
                            p := [2]f32{min_x, min_y} + [2]f32{dist_x, dist_y}
                            draw_triangle(
                                p + get_scaled_rand_pair(state, tile_map),
                                p + get_scaled_rand_pair(state, tile_map),
                                p + get_scaled_rand_pair(state, tile_map),
                                {255, 255, 255, 255})

                        }

                        rl.DrawCircle(
                            i32(min_x),
                            i32(min_y),
                            rand.float32_range(.2, .3, state.frame_deterministic_rng) * 3 * f32(tile_map.tile_side_in_pixels),
                            {255, 255, 255, 255},
                        )
                }
            }
        }
    }
    rl.EndTextureMode()

}
