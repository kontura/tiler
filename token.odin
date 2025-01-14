package tiler

Token :: struct {
    id: u64,
    position: TileMapPosition,
    color: [4]u8,
    name: string,
    moved: u32,
    size: i32,
    //TODO(amatej): image
}

find_token_at_tile_map :: proc(pos: TileMapPosition, state: ^GameState) -> ^Token {
    for &token in state.tokens {
        if token.position.abs_tile == pos.abs_tile {
            return &token
        }
    }

    return nil
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

make_token :: proc(id: u64, pos: TileMapPosition, color: [4]u8) -> Token {
    return Token{id, pos, color, "", 0, 1}

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
