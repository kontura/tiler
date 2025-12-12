package tiler

import "core:fmt"
import "core:math"
import rl "vendor:raylib"
import rlgl "vendor:raylib/rlgl"

RLGL_SRC_ALPHA :: 0x0302
RLGL_MIN :: 0x8007
RLGL_MAX :: 0x8008

TOKEN_SHADOW_SIZE :: .3

LightInfo :: struct {
    light_mask: rl.RenderTexture,
    radius:     f32,
}

get_N_points_on_circle :: #force_inline proc($N: int, center: [2]f32, radius: f32) -> (res: [N][2]f32) {
    for _, i in res {
        res[i] = {
            center.x + radius * math.cos((2 * math.PI * f32(i)) / f32(N)),
            center.y + radius * math.sin((2 * math.PI * f32(i)) / f32(N)),
        }
    }
    return
}


draw_light_mask :: proc(state: ^GameState, tile_map: ^TileMap, light: ^LightInfo, pos: TileMapPosition) {
    rl.BeginTextureMode(light.light_mask)
    {
        rl.ClearBackground(rl.WHITE)

        rlgl.SetBlendFactors(RLGL_SRC_ALPHA, RLGL_SRC_ALPHA, RLGL_MIN)
        rlgl.SetBlendMode(i32(rl.BlendMode.CUSTOM))

        light_screen_pos := tile_map_to_screen_coord_full(pos, state, tile_map)
        rl.DrawCircleGradient(
            i32(light_screen_pos.x),
            i32(light_screen_pos.y),
            light.radius,
            {255, 255, 255, 0},
            rl.WHITE,
        )

        rlgl.DrawRenderBatchActive()

        rlgl.SetBlendMode(i32(rl.BlendMode.ALPHA))
        rlgl.SetBlendFactors(RLGL_SRC_ALPHA, RLGL_SRC_ALPHA, RLGL_MAX)
        rlgl.SetBlendMode(i32(rl.BlendMode.CUSTOM))

        // Draw wall shadows
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

                //shadow := [2]f32{0.4, 0.4} * f32(tile_map.tile_side_in_pixels) * 3
                if Direction.TOP in current_tile_value.walls {
                    if current_tile_value.wall_colors[Direction.TOP].w != 0 {
                        w1: [2]f32 = {min_x, min_y}
                        w2: [2]f32 = {min_x + f32(tile_map.tile_side_in_pixels), min_y}
                        ray1 := rl.Vector2Normalize(w1 - light_screen_pos) * 50 * f32(tile_map.tile_side_in_pixels)
                        ray2 := rl.Vector2Normalize(w2 - light_screen_pos) * 50 * f32(tile_map.tile_side_in_pixels)
                        draw_quad(w1, w2, w1 + ray1, w2 + ray2, rl.WHITE.xyzw)
                    }
                }
                if current_tile_value.wall_colors[Direction.LEFT].w != 0 {
                    if Direction.LEFT in current_tile_value.walls {
                        w1: [2]f32 = {min_x, min_y}
                        w2: [2]f32 = {min_x, min_y + f32(tile_map.tile_side_in_pixels)}
                        ray1 := rl.Vector2Normalize(w1 - light_screen_pos) * 50 * f32(tile_map.tile_side_in_pixels)
                        ray2 := rl.Vector2Normalize(w2 - light_screen_pos) * 50 * f32(tile_map.tile_side_in_pixels)
                        draw_quad(w1, w1 + ray1, w2, w2 + ray2, rl.WHITE.xyzw)
                    }
                }
            }
        }
        for _, &token in state.tokens {
            // Draw shadows only for real tokens, skip temp 0 token
            if token.alive && token.position != pos {
                token_pos, token_circle_radius := get_token_circle(tile_map, state, token)
                center_from_source: f32 = dist(token_pos, light_screen_pos)
                circle_points := get_N_points_on_circle(20, token_pos.xy, token_circle_radius)
                prev: [2][2]f32
                // Find last farther from center, basically finishing the loop
                #reverse for p in circle_points {
                    p_from_source: f32 = dist(p, light_screen_pos)
                    if p_from_source >= center_from_source {
                        ray :=
                            rl.Vector2Normalize(p - light_screen_pos) *
                            TOKEN_SHADOW_SIZE *
                            f32(tile_map.tile_side_in_pixels)
                        v: [2][2]f32 = {p, p + ray}
                        prev = v
                        break
                    }
                }

                for p in circle_points {
                    p_from_source: f32 = dist(p, light_screen_pos)
                    if p_from_source >= center_from_source {
                        ray :=
                            rl.Vector2Normalize(p - light_screen_pos) *
                            TOKEN_SHADOW_SIZE *
                            f32(tile_map.tile_side_in_pixels)
                        draw_quad_ordered(prev[0], p, p + ray, prev[1], rl.WHITE.xyzw)
                        v: [2][2]f32 = {p, p + ray}
                        prev = v
                    }
                }
            }
        }
        rlgl.DrawRenderBatchActive()

        rlgl.SetBlendMode(i32(rl.BlendMode.ALPHA))
    }
    rl.EndTextureMode()
}

merge_light_masks :: proc(state: ^GameState, tile_map: ^TileMap) {
    rl.BeginTextureMode(state.light_mask)
    {
        rl.ClearBackground(rl.BLACK)

        rlgl.SetBlendFactors(RLGL_SRC_ALPHA, RLGL_SRC_ALPHA, RLGL_MIN)
        rlgl.SetBlendMode(i32(rl.BlendMode.CUSTOM))

        rl.DrawTextureRec(
            state.light.light_mask.texture,
            {0, 0, f32(state.screen_width), f32(-state.screen_height)},
            {0, 0},
            rl.WHITE,
        )
        for _, &token in state.tokens {
            l, ok := &token.light.?
            if ok {
                rl.DrawTextureRec(
                    l.light_mask.texture,
                    {0, 0, f32(state.screen_width), f32(-state.screen_height)},
                    {0, 0},
                    rl.WHITE,
                )
            }
        }

        rlgl.DrawRenderBatchActive()

        rlgl.SetBlendMode(i32(rl.BlendMode.ALPHA))
    }
    rl.EndTextureMode()
}
