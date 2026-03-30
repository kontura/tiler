package tiler

import "core:fmt"
import "core:math"
import rl "vendor:raylib"
import rlgl "vendor:raylib/rlgl"

RLGL_SRC_ALPHA :: 0x0302
RLGL_MIN :: 0x8007
RLGL_MAX :: 0x8008

TOKEN_SHADOW_LEN :: 50

LightInfo :: struct {
    light_wall_mask:  rl.RenderTexture,
    light_token_mask: rl.RenderTexture,
    radius:           f32,
    dirty_wall:       bool,
    dirty_token:      bool,
    shadow_len:       f32,
    intensity:        f32,
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
    light_screen_pos := tile_map_to_screen_coord_full(pos, state, tile_map)
    if light.dirty_wall || tile_map.dirty || true {
        rl.BeginTextureMode(light.light_wall_mask)
        {
            rl.ClearBackground(rl.WHITE)

            rlgl.SetBlendFactors(RLGL_SRC_ALPHA, RLGL_SRC_ALPHA, RLGL_MIN)
            rlgl.SetBlendMode(i32(rl.BlendMode.CUSTOM))

            intensity_color: rl.Color = rl.ColorFromNormalized([4]f32{1, 1, 1, 1 - light.intensity})
            rl.DrawCircleGradient(
                i32(light_screen_pos.x),
                i32(light_screen_pos.y),
                light.radius * f32(tile_map.tile_side_in_pixels) * state.camera.zoom,
                intensity_color,
                rl.WHITE,
            )

            rlgl.DrawRenderBatchActive()

            rlgl.SetBlendMode(i32(rl.BlendMode.ALPHA))
            rlgl.SetBlendFactors(RLGL_SRC_ALPHA, RLGL_SRC_ALPHA, RLGL_MAX)
            rlgl.SetBlendMode(i32(rl.BlendMode.CUSTOM))

            //TODO(amatej): we have to also somehow cap this by what the camera can see,
            //              the global light has enourmous radios
            //              The global light likely doesn't run because it underflows the u32
            //TODO(amatej): Don't use so many textures, use channels for separate lights,
            //              scale down the lights and store multiple in one texture
            //// Draw wall shadows
            for row_offset: u32 = pos.abs_tile.y - u32(light.radius);
                row_offset <= pos.abs_tile.y + u32(light.radius);
                row_offset += 1 {
                for column_offset: u32 = pos.abs_tile.x - u32(light.radius);
                    column_offset <= pos.abs_tile.x + u32(light.radius);
                    column_offset += 1 {
                    current_tile_pos : TileMapPosition = {{column_offset, row_offset}, {-2.5, -2.5}}
                    current_tile_value: Tile = get_tile(tile_map, current_tile_pos.abs_tile)
                    current_tile_screen_pos := tile_map_to_screen_coord_full(current_tile_pos, state, tile_map)
                    //rl.DrawCircleV(current_tile_screen_pos, 5, rl.WHITE)
                    min_x := current_tile_screen_pos.x
                    min_y := current_tile_screen_pos.y

                    if Direction.TOP in current_tile_value.walls {
                        if current_tile_value.wall_colors[Direction.TOP].w != 0 {
                            w1: [2]f32 = {min_x, min_y}
                            w2: [2]f32 = {min_x + f32(tile_map.tile_side_in_pixels)*state.camera.zoom, min_y}
                            ray1 :=
                                rl.Vector2Normalize(w1 - light_screen_pos) *
                                light.shadow_len *
                                f32(tile_map.tile_side_in_pixels)
                            ray2 :=
                                rl.Vector2Normalize(w2 - light_screen_pos) *
                                light.shadow_len *
                                f32(tile_map.tile_side_in_pixels)
                            draw_quad(w1, w2, w1 + ray1, w2 + ray2, rl.WHITE.xyzw)
                        }
                    }
                    if current_tile_value.wall_colors[Direction.LEFT].w != 0 {
                        if Direction.LEFT in current_tile_value.walls {
                            w1: [2]f32 = {min_x, min_y}
                            w2: [2]f32 = {min_x, min_y + f32(tile_map.tile_side_in_pixels)*state.camera.zoom}
                            ray1 :=
                                rl.Vector2Normalize(w1 - light_screen_pos) *
                                light.shadow_len *
                                f32(tile_map.tile_side_in_pixels)
                            ray2 :=
                                rl.Vector2Normalize(w2 - light_screen_pos) *
                                light.shadow_len *
                                f32(tile_map.tile_side_in_pixels)
                            draw_quad(w1, w1 + ray1, w2, w2 + ray2, rl.WHITE.xyzw)
                        }
                    }
                }
            }

            rlgl.DrawRenderBatchActive()

            rlgl.SetBlendMode(i32(rl.BlendMode.ALPHA))
        }
        rl.EndTextureMode()
        light.dirty_wall = false
    }
    if light.dirty_token || true {
        rl.BeginTextureMode(light.light_token_mask)
        {
            rl.ClearBackground(rl.WHITE)

            rlgl.SetBlendFactors(RLGL_SRC_ALPHA, RLGL_SRC_ALPHA, RLGL_MIN)
            rlgl.SetBlendMode(i32(rl.BlendMode.CUSTOM))

            rl.DrawTextureRec(
                light.light_wall_mask.texture,
                {0, 0, f32(state.screen_width), f32(-state.screen_height)},
                {0, 0},
                rl.WHITE,
            )

            rlgl.DrawRenderBatchActive()

            rlgl.SetBlendMode(i32(rl.BlendMode.ALPHA))
            rlgl.SetBlendFactors(RLGL_SRC_ALPHA, RLGL_SRC_ALPHA, RLGL_MAX)
            rlgl.SetBlendMode(i32(rl.BlendMode.CUSTOM))

            for _, &token in state.tokens {
                // Draw shadows only for real tokens, skip temp 0 token
                if token.alive && token.position != pos {
                    // token_pos is world space
                    token_pos, token_circle_radius := get_token_circle(tile_map, state, &token)
                    token_circle_radius *= state.camera.zoom
                    token_pos = rl.GetWorldToScreen2D(token_pos, state.camera)
                    center_from_source: f32 = dist(token_pos, light_screen_pos)
                    circle_points := get_N_points_on_circle(20, token_pos.xy, token_circle_radius)
                    prev: [2][2]f32
                    // Find last farther from center, basically finishing the loop
                    #reverse for p in circle_points {
                        p_from_source: f32 = dist(p, light_screen_pos)
                        if p_from_source >= center_from_source {
                            ray :=
                                rl.Vector2Normalize(p - light_screen_pos) *
                                light.shadow_len *
                                f32(tile_map.tile_side_in_pixels) *
                                state.camera.zoom /
                                4
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
                                light.shadow_len *
                                f32(tile_map.tile_side_in_pixels) *
                                state.camera.zoom /
                                4
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
        light.dirty_token = false
    }
}

merge_light_masks :: proc(state: ^GameState, tile_map: ^TileMap) {
    rl.BeginTextureMode(state.light_mask)
    {
        rl.ClearBackground(rl.BLACK)

        rlgl.SetBlendFactors(RLGL_SRC_ALPHA, RLGL_SRC_ALPHA, RLGL_MIN)
        rlgl.SetBlendMode(i32(rl.BlendMode.CUSTOM))
        rl.DrawTextureRec(
            state.light.light_token_mask.texture,
            {0, 0, f32(state.screen_width), f32(-state.screen_height)},
            {0, 0},
            rl.WHITE,
        )
        for _, &token in state.tokens {
            l, ok := &token.light.?
            if ok {
                rl.DrawTextureRec(
                    l.light_token_mask.texture,
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

set_dirty_wall_for_token :: proc(token: ^Token) {
    l, ok := &token.light.?
    if ok {
        l.dirty_wall = true
    }
}

set_dirty_token_for_all_lights :: proc(state: ^GameState) {
    state.light.dirty_token = true
    for _, &token in state.tokens {
        l, ok := &token.light.?
        if ok {
            l.dirty_token = true
        }
    }
}
