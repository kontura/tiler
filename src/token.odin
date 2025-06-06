package tiler

import "core:math/rand"
import "core:strings"
import rl "vendor:raylib"

Token :: struct {
    id: u64,
    position: TileMapPosition,
    color: [4]u8,
    name: string,
    moved: u32,
    size: i32,
    initiative: i32,
    texture: ^rl.Texture2D,
    alive: bool,
}

get_token_circle :: proc(tile_map: ^TileMap, state: ^GameState, token: Token) -> (center: [2]f32, radius: f32) {
    center = tile_map_to_screen_coord(token.position, state, tile_map)
    if token.size % 2 == 0 {
        center -= {f32(tile_map.tile_side_in_pixels)/2, f32(tile_map.tile_side_in_pixels)/2}
        radius = f32(tile_map.tile_side_in_pixels/2*token.size)
    } else {
        radius = f32(tile_map.tile_side_in_pixels/2*token.size)
    }

    return center, radius
}

get_token_texture_pos_size :: proc(tile_map: ^TileMap, state: ^GameState, token: Token) -> (pos: [2]f32, scale: f32) {
    pos = tile_map_to_screen_coord(token.position, state, tile_map)
    pos -= f32(tile_map.tile_side_in_pixels)/2
    pos -= f32(token.size / 2) * f32(tile_map.tile_side_in_pixels)
    // We assume token textures are squares
    scale = f32(tile_map.tile_side_in_pixels * token.size)/f32(token.texture.width)

    return pos, scale
}

get_token_name_temp :: proc(token: ^Token) -> cstring {
    if (len(token.name) == 0) {
        return u64_to_cstring(token.id)
    } else {
        return strings.clone_to_cstring(token.name, context.temp_allocator)
    }
}

make_token :: proc(id: u64, pos: TileMapPosition, color: [4]u8, name : string = "") -> Token {
    return Token{id, pos, color, strings.clone(name), 0, 1, rand.int31_max(22) + 1, nil, true}
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

remove_token_by_id_from_initiative :: proc(state: ^GameState, token_id: u64) -> (i32, i32) {
    for initiative, &tokens in state.initiative_to_tokens {
        for id, index in tokens {
            if id == token_id {
                ordered_remove(&tokens, index)
                return initiative, i32(index)
            }
        }
    }

    return -1,-1
}

set_texture_based_on_name :: proc(state: ^GameState, token: ^Token) {
    lowercase_name := strings.to_lower(token.name, context.temp_allocator)
    for key, &value in state.textures {
        if strings.has_prefix(lowercase_name, key) {
            token.texture = &value
        }
    }

}
