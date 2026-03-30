package tiler

import "core:fmt"
import "core:math"
import "core:math/rand"
import rl "vendor:raylib"

draw_tiles :: proc(state: ^GameState, tile_map: ^TileMap) {
    //TODO(amatej): This is bad usually most of the tiles are empty, we don't have to iterate
    //              over all of this.

    // Draw only tiles in camera view
    top_left := rl.GetScreenToWorld2D({0, 0}, state.camera) / f32(tile_map.tile_side_in_pixels)
    top_left_offset: [2]u32
    top_left_offset.x = u32(top_left.x)
    top_left_offset.y = u32(top_left.y)

    needed_tiles_width := i32(f32(state.screen_width) / f32(tile_map.tile_side_in_pixels) / state.camera.zoom) + 1
    needed_tiles_height := i32(f32(state.screen_height) / f32(tile_map.tile_side_in_pixels) / state.camera.zoom) + 1
    for row_offset: i32 = 0; row_offset <= needed_tiles_height; row_offset += 1 {
        for column_offset: i32 = 0; column_offset <= needed_tiles_width; column_offset += 1 {
            pos: [2]u32
            pos.x = u32(column_offset)
            pos.y = u32(row_offset)
            pos += top_left_offset

            current_tile_value: Tile = get_tile(tile_map, pos)

            if current_tile_value.color.w != 0 {
                rl.DrawRectangleV(
                    {f32(pos.x) * f32(tile_map.tile_side_in_pixels), f32(pos.y) * f32(tile_map.tile_side_in_pixels)},
                    {f32(tile_map.tile_side_in_pixels), f32(tile_map.tile_side_in_pixels)},
                    current_tile_value.color.xyzw,
                )
            }

            if Direction.TOP in current_tile_value.walls {
                if current_tile_value.wall_colors[Direction.TOP].w != 0 {
                    //TODO(amatej): use DrawLineEx if we want to do diagonals
                    rl.DrawRectangleV(
                        {
                            f32(pos.x) * f32(tile_map.tile_side_in_pixels),
                            f32(pos.y) * f32(tile_map.tile_side_in_pixels),
                        },
                        {f32(tile_map.tile_side_in_pixels), f32(tile_map.tile_side_in_pixels) * .1},
                        current_tile_value.wall_colors[Direction.TOP].xyzw,
                    )
                }
            }
            if current_tile_value.wall_colors[Direction.LEFT].w != 0 {
                if Direction.LEFT in current_tile_value.walls {
                    rl.DrawRectangleV(
                        {
                            f32(pos.x) * f32(tile_map.tile_side_in_pixels),
                            f32(pos.y) * f32(tile_map.tile_side_in_pixels),
                        },
                        {f32(tile_map.tile_side_in_pixels) * .1, f32(tile_map.tile_side_in_pixels)},
                        current_tile_value.wall_colors[Direction.LEFT].xyzw,
                    )
                }
            }
        }
    }
}

draw_grid :: proc(state: ^GameState, tile_map: ^TileMap) {
    top_left := rl.GetScreenToWorld2D({0, 0}, state.camera) / f32(tile_map.tile_side_in_pixels)
    top_left_offset: [2]i32
    top_left_offset.x = i32(top_left.x)
    top_left_offset.y = i32(top_left.y)
    // draw grid
    needed_tiles_width := i32(f32(state.screen_width) / f32(tile_map.tile_side_in_pixels) / state.camera.zoom) + 1
    needed_tiles_height := i32(f32(state.screen_height) / f32(tile_map.tile_side_in_pixels) / state.camera.zoom) + 1
    needed := math.max(needed_tiles_width, needed_tiles_height)
    ext := f32(tile_map.tile_side_in_pixels) / state.camera.zoom
    for row_offset: i32 = 0; row_offset <= needed; row_offset += 1 {
        screen_pos: [2]i32 = {row_offset, row_offset}
        screen_pos += top_left_offset
        screen_pos *= tile_map.tile_side_in_pixels
        rl.DrawLineV(
            {f32(top_left_offset.x) * f32(tile_map.tile_side_in_pixels), f32(screen_pos.y)},
            {
                f32(top_left_offset.x + 1) * f32(tile_map.tile_side_in_pixels) +
                f32(state.screen_width) / state.camera.zoom,
                f32(screen_pos.y),
            },
            {0, 0, 0, 25},
        )
        rl.DrawLineV(
            {f32(screen_pos.x), f32(top_left_offset.y) * f32(tile_map.tile_side_in_pixels)},
            {
                f32(screen_pos.x),
                f32(top_left_offset.y + 1) * f32(tile_map.tile_side_in_pixels) +
                f32(state.screen_height) / state.camera.zoom,
            },
            {0, 0, 0, 25},
        )
    }
}

get_scaled_rand_pair :: proc(state: ^GameState, tile_map: ^TileMap) -> [2]f32 {
    return [2]f32 {
        f32(tile_map.tile_side_in_pixels) * state.camera.zoom *
        (rand.float32(state.frame_deterministic_rng) - 0.5) *
        3 *
        rand.float32(state.frame_deterministic_rng),
        f32(tile_map.tile_side_in_pixels) * state.camera.zoom *
        (rand.float32(state.frame_deterministic_rng) - 0.5) *
        3 *
        rand.float32(state.frame_deterministic_rng),
    }
}

draw_grid_mask_to_tex :: proc(state: ^GameState, tile_map: ^TileMap, tex: ^rl.RenderTexture) {
    //if !tile_map.dirty {
    //    return
    //}
    rl.BeginTextureMode(tex^)
    {
        rl.ClearBackground({0, 0, 0, 0})
        signs := [2]f32{1, -1}

        top_left := rl.GetScreenToWorld2D({0, 0}, state.camera) / f32(tile_map.tile_side_in_pixels)
        top_left_offset: [2]u32
        top_left_offset.x = u32(top_left.x)
        top_left_offset.y = u32(top_left.y)

        needed_tiles_width := i32(f32(state.screen_width) / f32(tile_map.tile_side_in_pixels) / state.camera.zoom) + 1
        needed_tiles_height :=
            i32(f32(state.screen_height) / f32(tile_map.tile_side_in_pixels) / state.camera.zoom) + 1
        for row_offset: i32 = 0; row_offset <= needed_tiles_height; row_offset += 1 {
            for column_offset: i32 = 0; column_offset <= needed_tiles_width; column_offset += 1 {
                pos: [2]u32
                pos.x = u32(column_offset)
                pos.y = u32(row_offset)
                pos += top_left_offset

                current_tile_value: Tile = get_tile(tile_map, pos)

                min_x: f32 = f32(pos.x) * f32(tile_map.tile_side_in_pixels)
                min_y: f32 = f32(pos.y) * f32(tile_map.tile_side_in_pixels)
                ss := rl.GetWorldToScreen2D({min_x, min_y}, state.camera)

                if Direction.TOP in current_tile_value.walls || Direction.LEFT in current_tile_value.walls {
                    rand.reset(u64(pos.x + pos.y), state.frame_deterministic_rng)
                    if rand.float32(state.frame_deterministic_rng) < 1.1 {
                        dist_x :=
                            (rand.float32_range(0.4, 1.8, state.frame_deterministic_rng) *
                                rand.choice(signs[:], state.frame_deterministic_rng)) *
                            f32(tile_map.tile_side_in_pixels) * state.camera.zoom
                        dist_y :=
                            (rand.float32_range(0.4, 1.8, state.frame_deterministic_rng) *
                                rand.choice(signs[:], state.frame_deterministic_rng)) *
                            f32(tile_map.tile_side_in_pixels) * state.camera.zoom
                        p := [2]f32{ss.x, ss.y} + [2]f32{dist_x, dist_y}
                        draw_triangle(
                            p + get_scaled_rand_pair(state, tile_map),
                            p + get_scaled_rand_pair(state, tile_map),
                            p + get_scaled_rand_pair(state, tile_map),
                            {255, 0, 0, 200},
                        )
                    }

                    rl.DrawCircle(
                        i32(ss.x),
                        i32(ss.y),
                        rand.float32_range(.2, .3, state.frame_deterministic_rng) *
                        3 *
                        state.camera.zoom *
                        f32(tile_map.tile_side_in_pixels),
                        {255, 0, 0, 200},
                    )
                }

                // Extend tile masks by wall thickness to mask walls of
                // bottom and right tiles. This is needed because we
                // draw only TOP and LEFT tile walls so bottom and right
                // edge tiles have walls in extra next tiles.
                wall_thickness := f32(tile_map.tile_side_in_pixels) * .1
                if current_tile_value.color.w != 0 {
                    rl.DrawRectangleV(
                        {ss.x, ss.y},
                        {
                            (f32(tile_map.tile_side_in_pixels) + wall_thickness) * state.camera.zoom,
                            (f32(tile_map.tile_side_in_pixels) + wall_thickness) * state.camera.zoom,
                        },
                        {0, 255, 0, 200},
                    )
                }
            }
        }
    }
    rl.EndTextureMode()

}
