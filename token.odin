package tiler

Token :: struct {
    id: u64,
    position: TileMapPosition,
    color: [4]u8,
    name: string,
    moved: u32
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

make_token :: proc(id: u64, pos: TileMapPosition, color: [4]u8) -> Token {
    return Token{id, pos, color, "", 0, 1}

}

delete_token :: proc(token: ^Token) {
    delete(token.name)
}
