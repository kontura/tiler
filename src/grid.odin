package tiler

import rl "vendor:raylib"
import "core:fmt"
import "core:math"
import "core:math/rand"

draw_grid_mask :: proc(state: ^GameState, tile_map: ^TileMap) {
    rl.BeginTextureMode(state.grid_mask)
    {
        rl.ClearBackground({0, 0, 0, 0})
        //for _, &token in state.tokens {
        //    if token.id == 0 {
        //        continue
        //    }
        //    token_pos, token_circle_radius := get_token_circle(tile_map, state, token)
        //    rl.DrawCircleGradient(
        //        i32(token_pos.x),
        //        i32(token_pos.y),
        //        10 * f32(tile_map.tile_side_in_pixels),
        //        {0, 0, 0, 255},
        //        {0, 0, 0, 0},
        //    )
        //}

        rand.reset(u64(1))

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
                        rl.DrawCircleGradient(
                            i32(min_x),
                            i32(min_y),
                            rand.float32() * 8 * f32(tile_map.tile_side_in_pixels),
                            {255, 0, 0, 255},
                            {0, 0, 0, 0},
                        )
                }


                if current_tile_value.color.w != 0 {
                    rl.DrawRectangleV(
                        {min_x, min_y},
                        {f32(tile_map.tile_side_in_pixels), f32(tile_map.tile_side_in_pixels)},
                        {0, 0, 0, 0},
                    )
                }

            }
        }


    }
    rl.EndTextureMode()

}
