package tiler

import "core:fmt"
import "core:math"
import "core:math/rand"
import "core:strings"
import rl "vendor:raylib"

TOKEN_DEFAULT_LIGHT_RADIUS :: 10

Token :: struct {
    id:         u64,
    position:   TileMapPosition,
    color:      [4]u8,
    name:       string,
    moved:      u32,
    size:       f32,
    initiative: i32,
    texture:    ^rl.Texture2D,
    alive:      bool,
    light:      Maybe(LightInfo),
    target_position: TileMapPosition,
}

get_token_circle :: proc(tile_map: ^TileMap, state: ^GameState, token: Token) -> (center: [2]f32, radius: f32) {
    center = tile_map_to_screen_coord_full(token.position, state, tile_map)
    if math.mod_f32(token.size, 2) <= 0.5 {
        center -= {f32(tile_map.tile_side_in_pixels) / 2, f32(tile_map.tile_side_in_pixels) / 2}
    }
    radius = f32(tile_map.tile_side_in_pixels) / 2 * token.size

    return center, radius
}

tokens_animate_pos:: proc(tile_map: ^TileMap, state: ^GameState) {
    for id, &token in state.tokens {
        if token.position != token.target_position {
            current_dist : = tile_pos_distance(tile_map, token.position, token.target_position)
            new_dist := exponential_smoothing(0, current_dist)
            tile_vec := tile_pos_difference(token.target_position, token.position)
            tile_vec_normal := tile_vec_div(tile_vec, current_dist)
            tile_vec_multed := tile_vec_mul(tile_vec_normal, current_dist - new_dist)
            token.position = recanonicalize_position(tile_map, tile_pos_add_tile_vec(token.position, tile_vec_multed))
            l, ok := &token.light.?
            if ok {
                l.dirty = true
            }
        }
    }
}

get_token_texture_pos_size :: proc(tile_map: ^TileMap, state: ^GameState, token: Token) -> (pos: [2]f32, scale: f32) {
    pos = tile_map_to_screen_coord_full(token.position, state, tile_map)
    if math.mod_f32(token.size, 2) <= 0.5 {
        pos -= f32(tile_map.tile_side_in_pixels) / 2.0
    }
    pos -= token.size / f32(2.0) * f32(tile_map.tile_side_in_pixels)
    // We assume token textures are squares
    scale = f32(tile_map.tile_side_in_pixels) * token.size / f32(token.texture.width)

    return pos, scale
}

get_token_name_temp :: proc(token: ^Token) -> cstring {
    if (len(token.name) == 0) {
        return u64_to_cstring(token.id)
    } else {
        return strings.clone_to_cstring(token.name, context.temp_allocator)
    }
}

make_token :: proc(id: u64, pos: TileMapPosition, color: [4]u8, name: string = "", initiative: i32 = -1) -> Token {
    if initiative == -1 {
        return Token{id, pos, color, strings.clone(name), 0, 1, rand.int31_max(22) + 1, nil, true, nil, pos}
    } else {
        return Token{id, pos, color, strings.clone(name), 0, 1, initiative, nil, true, nil, pos}
    }
}

delete_token :: proc(token: ^Token) {
    delete(token.name)
}

//TODO(amatej): should this be a tool
token_kill :: proc(state: ^GameState, tile_map: ^TileMap, token: ^Token, action: ^Action) {
    init, init_index, ok := remove_token_by_id_from_initiative(state, token.id)
    token.alive = false
    if action != nil {
        action.token_id = token.id
        action.token_life = false
        action.token_initiative_end = {init, init_index}
    }
    // token with id 0 is special temp token, it is not in initiative
    // and we don't want to emit particles
    if token.id != 0 {
        if !ok {
            fmt.eprintln("Killing: ", token.id, " but cant find it in initiative.")
        }
        for i := 0; i < 80 * int(token.size) * int(token.size); i += 1 {
            angle := rand.float32() * 2 * math.PI
            rand_radius := math.sqrt(rand.float32()) * f32(token.size) * tile_map.tile_side_in_feet / 2
            random_pos_in_token_circle := token.position
            random_pos_in_token_circle.rel_tile.x += rand_radius * math.cos(angle)
            random_pos_in_token_circle.rel_tile.y += rand_radius * math.sin(angle)
            random_pos_in_token_circle = recanonicalize_position(tile_map, random_pos_in_token_circle)
            particle_emit(
                state,
                random_pos_in_token_circle,
                PARTICLE_BASE_VELOCITY + f32(token.size) * 4,
                PARTICLE_LIFETIME + f32(token.size) / 4,
                token.color,
                PARTICLE_SIZE,
            )
        }
    }
}

// When size is even the real token position is in lower right,
// see get_token_circle
set_token_position :: proc(token: ^Token, pos: TileMapPosition) {
    if math.mod_f32(token.size, 2) <= 0.5 {
        pos := pos
        pos.abs_tile += {1, 1}
        token.position = pos
    } else {
        token.position = pos
    }

}

get_token_init_pos :: proc(state: ^GameState, token_id: u64) -> (i32, i32, bool) {
    t_init := state.tokens[token_id].initiative
    tokens := state.initiative_to_tokens[t_init]
    for id, index in tokens {
        if id == token_id {
            return t_init, i32(index), true
        }
    }

    return 0, 0, false
}

remove_token_by_id_from_initiative :: proc(state: ^GameState, token_id: u64) -> (i32, i32, bool) {
    for initiative, &tokens in state.initiative_to_tokens {
        for id, index in tokens {
            if id == token_id {
                ordered_remove(&tokens, index)
                return initiative, i32(index), true
            }
        }
    }

    return 0, 0, false
}

remove_all_tokens_by_id_from_initiative :: proc(state: ^GameState, token_id: u64) -> i32 {
    count: i32 = 0
    for initiative, &tokens in state.initiative_to_tokens {
        for id, index in tokens {
            if id == token_id {
                ordered_remove(&tokens, index)
                count += 1
            }
        }
    }

    return count
}

set_texture_based_on_name :: proc(state: ^GameState, token: ^Token) {
    lowercase_name := strings.to_lower(token.name, context.temp_allocator)
    for key, &value in state.textures {
        if strings.has_prefix(lowercase_name, key) {
            token.texture = &value
        }
    }

}

clear_selected_tokens :: proc(state: ^GameState) {
    if len(state.selected_tokens) > 0 {
        state.last_selected_token_id = state.selected_tokens[0]
        clear(&state.selected_tokens)
    }
}

token_spawn :: proc(
    state: ^GameState,
    action: ^Action,
    pos: TileMapPosition,
    color: [4]u8,
    name: string = "",
    initiative: [2]i32 = {-1, 0},
    id_override: u64 = 0,
) -> u64 {
    id := id_override > 0 ? id_override : u64(len(state.tokens))
    t := make_token(id, pos, color, name, initiative.x)
    state.tokens[t.id] = t
    set_texture_based_on_name(state, &state.tokens[t.id])
    state.needs_sync = true
    add_at_initiative(state, t.id, t.initiative, initiative.y)
    if action != nil {
        action.token_id = t.id
        action.token_life = true
        action.color = color
        init_pos, init_index, ok := get_token_init_pos(state, t.id)
        // the newly created token has to be in initiative
        assert(ok)
        action.token_initiative_end = {init_pos, init_index}
        action.start = pos
        action.new_name = strings.clone(name)
    }
    return t.id
}
