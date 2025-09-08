package tiler

import "core:math/rand"
import "core:strings"
import rl "vendor:raylib"

Token :: struct {
    id:         u64,
    position:   TileMapPosition,
    color:      [4]u8,
    name:       string,
    moved:      u32,
    size:       i32,
    initiative: i32,
    texture:    ^rl.Texture2D,
    alive:      bool,
}

get_token_circle :: proc(tile_map: ^TileMap, state: ^GameState, token: Token) -> (center: [2]f32, radius: f32) {
    center = tile_map_to_screen_coord(token.position, state, tile_map)
    if token.size % 2 == 0 {
        center -= {f32(tile_map.tile_side_in_pixels) / 2, f32(tile_map.tile_side_in_pixels) / 2}
        radius = f32(tile_map.tile_side_in_pixels / 2 * token.size)
    } else {
        radius = f32(tile_map.tile_side_in_pixels / 2 * token.size)
    }

    return center, radius
}

get_token_texture_pos_size :: proc(tile_map: ^TileMap, state: ^GameState, token: Token) -> (pos: [2]f32, scale: f32) {
    pos = tile_map_to_screen_coord(token.position, state, tile_map)
    pos -= f32(tile_map.tile_side_in_pixels) / 2
    pos -= f32(token.size / 2) * f32(tile_map.tile_side_in_pixels)
    // We assume token textures are squares
    scale = f32(tile_map.tile_side_in_pixels * token.size) / f32(token.texture.width)

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
        return Token{id, pos, color, strings.clone(name), 0, 1, rand.int31_max(22) + 1, nil, true}
    } else {
        return Token{id, pos, color, strings.clone(name), 0, 1, initiative, nil, true}
    }
}

delete_token :: proc(token: ^Token) {
    delete(token.name)
}

// When size is even the real token position is in lower right,
// see get_token_circle
set_token_position :: proc(token: ^Token, pos: TileMapPosition) {
    if token.size % 2 == 0 {
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

set_texture_based_on_name :: proc(state: ^GameState, token: ^Token) {
    lowercase_name := strings.to_lower(token.name, context.temp_allocator)
    for key, &value in state.textures {
        if strings.has_prefix(lowercase_name, key) {
            token.texture = &value
        }
    }

}

token_spawn :: proc(
    state: ^GameState,
    action: ^Action,
    pos: TileMapPosition,
    color: [4]u8,
    name: string = "",
    initiative: i32 = -1,
    id_override: u64 = 0,
) -> u64 {
    id := id_override > 0 ? id_override : u64(len(state.tokens))
    t := make_token(id, pos, color, name, initiative)
    state.tokens[t.id] = t
    set_texture_based_on_name(state, &state.tokens[t.id])
    state.needs_sync = true
    add_at_initiative(state, t.id, t.initiative, 0)
    if action != nil {
        action.token_life[t.id] = true
        action.performed = true
        action.color = color
        action.token_initiative_history[t.id] = {t.initiative, 0}
        action.token_history[t.id] = {i32(pos.abs_tile.x), i32(pos.abs_tile.y)}
        action.new_names[t.id] = name
    }
    return t.id
}
