package tiler

import "core:math/rand"
import "core:strings"

Token :: struct {
    id: u64,
    position: TileMapPosition,
    color: [4]u8,
    name: string,
    moved: u32,
    size: i32,
    initiative: i32,
    //TODO(amatej): image
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

get_token_name_temp :: proc(token: ^Token) -> cstring {
    if (len(token.name) == 0) {
        return u64_to_cstring(token.id)
    } else {
        return strings.clone_to_cstring(token.name, context.temp_allocator)
    }
}

make_token :: proc(id: u64, pos: TileMapPosition, color: [4]u8, name : string = "") -> Token {
    return Token{id, pos, color, name, 0, 1, rand.int31_max(22) + 1}
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

remove_token_by_id_from_initiative :: proc(state: ^GameState, token_id: u64) {
    for _, &tokens in state.initiative_to_tokens {
        for id, index in tokens {
            if id == token_id {
                ordered_remove(&tokens, index)
                return
            }
        }
    }


}
