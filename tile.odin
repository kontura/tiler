package gridimpro
import "core:math"
import "core:fmt"

TileMapPosition :: struct {
    abs_tile_x : u32,
    abs_tile_y : u32,

    rel_tile_x : f32,
    rel_tile_y : f32,
}

TileChunkPosition :: struct {
    tile_chunk_x: u32,
    tile_chunk_y: u32,

    rel_tile_x: u32,
    rel_tile_y: u32,
}

Tile :: struct {
    r: u8,
    g: u8,
    b: u8,
    a: u8,
}

TileChunk :: struct {
    tiles: [dynamic] Tile
}

TileMap :: struct {
    chunk_shift : u32,
    chunk_mask : u32,

    chunk_dim : u32,

    tile_side_in_feet: f32,
    tile_side_in_pixels: i32,
    feet_to_pixels: f32,
    pixels_to_feet: f32,

    tile_chunk_count_x: u32,
    tile_chunk_count_y: u32,

    tile_chunks: [dynamic]TileChunk,
}

get_tile_chunk :: proc(tile_map: ^TileMap, tile_chunk_x: u32, tile_chunk_y: u32) -> ^TileChunk {
    res : ^TileChunk

    if ((tile_chunk_x >= 0) && (tile_chunk_x < tile_map.tile_chunk_count_x) &&
        (tile_chunk_y >= 0) && (tile_chunk_y < tile_map.tile_chunk_count_y)) {

        res = &tile_map.tile_chunks[tile_chunk_y * tile_map.tile_chunk_count_x + tile_chunk_x]
    } else {
        fmt.println(tile_chunk_x)
        fmt.println(tile_chunk_y)
        assert(false)
    }

    return res
}

get_chunk_position_for :: proc(tile_map: ^TileMap, abs_tile_x: u32, abs_tile_y: u32) -> TileChunkPosition {
    res: TileChunkPosition

    res.tile_chunk_x = abs_tile_x >> tile_map.chunk_shift
    res.tile_chunk_y = abs_tile_y >> tile_map.chunk_shift
    res.rel_tile_x = abs_tile_x & tile_map.chunk_mask
    res.rel_tile_y = abs_tile_y & tile_map.chunk_mask

    return res
}

get_tile_value :: proc(tile_map: ^TileMap, abs_tile_x : u32, abs_tile_y : u32) -> Tile {
    // allow overflow to cast to u32 to wrap arround the world
    chunk_pos : TileChunkPosition = get_chunk_position_for(tile_map, u32(abs_tile_x), u32(abs_tile_y))
    tile_chunk : ^TileChunk = get_tile_chunk(tile_map, chunk_pos.tile_chunk_x, chunk_pos.tile_chunk_y)

    assert(chunk_pos.rel_tile_x < tile_map.chunk_dim)
    assert(chunk_pos.rel_tile_y < tile_map.chunk_dim)

    return tile_chunk.tiles[chunk_pos.rel_tile_y * tile_map.chunk_dim + chunk_pos.rel_tile_x]


}

set_tile_value :: proc(tile_map: ^TileMap, abs_tile_x : u32, abs_tile_y : u32, val : Tile) {
    chunk_pos : TileChunkPosition = get_chunk_position_for(tile_map, abs_tile_x, abs_tile_y)
    tile_chunk : ^TileChunk = get_tile_chunk(tile_map, chunk_pos.tile_chunk_x, chunk_pos.tile_chunk_y)

    assert(chunk_pos.rel_tile_x < tile_map.chunk_dim)
    assert(chunk_pos.rel_tile_y < tile_map.chunk_dim)

    tile_chunk.tiles[chunk_pos.rel_tile_y * tile_map.chunk_dim + chunk_pos.rel_tile_x] = val
}

recanonicalize_coord :: proc(tile_map: ^TileMap, abs_tile: ^u32, rel_tile: ^f32) {
    offset: i32 = i32(math.round(rel_tile^ / tile_map.tile_side_in_feet))
    abs_tile^ += u32(offset)
    rel_tile^ -= f32(offset)*tile_map.tile_side_in_feet
}

recanonicalize_position :: proc(tile_map: ^TileMap, pos: TileMapPosition) -> TileMapPosition {
    res : TileMapPosition = pos

    recanonicalize_coord(tile_map, &res.abs_tile_x, &res.rel_tile_x)
    recanonicalize_coord(tile_map, &res.abs_tile_y, &res.rel_tile_y)

    return res
}
