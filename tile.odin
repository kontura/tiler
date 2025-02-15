package tiler

import "core:math"
import "core:fmt"

TileMapPosition :: struct {
    // Top left is 0,0
    // fixed point number, high bits determine chunk, low bits determine
    // position in chunk
    abs_tile : [2]u32,
    // position in feet
    // -2.5, -2.5 -----------
    //            |         |
    //            |         |
    //            |         |
    //            |         |
    //            ----------- 2.5, 2.5
    rel_tile : [2]f32,
}

TileChunkPosition :: struct {
    tile_chunk: [2]u32,
    rel_tile: [2]u32,
}

Tile :: struct {
    color: [4]u8,
}

TileChunk :: struct {
    tiles: [dynamic] Tile,
}

TileMap :: struct {
    chunk_shift : u32,
    chunk_mask : u32,

    chunk_dim : u32,

    tile_side_in_feet: f32,
    tile_side_in_pixels: i32,
    feet_to_pixels: f32,
    pixels_to_feet: f32,

    tile_chunk_count: [2]u32,

    tile_chunks: [dynamic]TileChunk,
}

tile_distance :: proc(tile_map: ^TileMap, p1: TileMapPosition, p2: TileMapPosition) -> f32 {
    p1_feet: [2]f32 = {f32(p1.abs_tile.x), f32(p1.abs_tile.y)} * tile_map.tile_side_in_feet + p1.rel_tile
    p2_feet: [2]f32 = {f32(p2.abs_tile.x), f32(p2.abs_tile.y)} * tile_map.tile_side_in_feet + p2.rel_tile

    return dist(f32, p1_feet, p2_feet)
}

get_tile_chunk :: proc(tile_map: ^TileMap, tile_chunk: [2]u32) -> ^TileChunk {
    res : ^TileChunk

    if ((tile_chunk.x >= 0) && (tile_chunk.x < tile_map.tile_chunk_count.x) &&
        (tile_chunk.y >= 0) && (tile_chunk.y < tile_map.tile_chunk_count.y)) {

        res = &tile_map.tile_chunks[tile_chunk.y * tile_map.tile_chunk_count.x + tile_chunk.x]
    }
    //TODO(amatej): We could possibly automatically create a new chunk when needed.

    return res
}

get_chunk_position_for :: proc(tile_map: ^TileMap, abs_tile: [2]u32) -> TileChunkPosition {
    res: TileChunkPosition

    res.tile_chunk.x = abs_tile.x >> tile_map.chunk_shift
    res.tile_chunk.y = abs_tile.y >> tile_map.chunk_shift
    res.rel_tile.x = abs_tile.x & tile_map.chunk_mask
    res.rel_tile.y = abs_tile.y & tile_map.chunk_mask

    return res
}

get_tile :: proc(tile_map: ^TileMap, abs_tile: [2]u32) -> Tile {
    // allow overflow to cast to u32 to wrap arround the world
    chunk_pos : TileChunkPosition = get_chunk_position_for(tile_map, abs_tile)
    tile_chunk : ^TileChunk = get_tile_chunk(tile_map, chunk_pos.tile_chunk)

    assert(chunk_pos.rel_tile.x < tile_map.chunk_dim)
    assert(chunk_pos.rel_tile.y < tile_map.chunk_dim)

    if (tile_chunk == nil) {
        //TODO(amatej): return read only empty white tile
        return tile_make()
    }

    return tile_chunk.tiles[chunk_pos.rel_tile.y * tile_map.chunk_dim + chunk_pos.rel_tile.x]
}

tile_make :: proc{
    tile_make_blank,
    tile_make_color,
}

tile_make_color :: proc(color: [4]u8) -> Tile {
    t: Tile = {}
    t.color = color
    return t
}

tile_make_blank :: proc() -> Tile {
    return {}
}

set_tile :: proc(tile_map: ^TileMap, abs_tile: [2]u32, val : Tile) {
    chunk_pos : TileChunkPosition = get_chunk_position_for(tile_map, abs_tile)
    tile_chunk : ^TileChunk = get_tile_chunk(tile_map, chunk_pos.tile_chunk)

    assert(chunk_pos.rel_tile.x < tile_map.chunk_dim)
    assert(chunk_pos.rel_tile.y < tile_map.chunk_dim)

    if (tile_chunk != nil) {
        tile_chunk.tiles[chunk_pos.rel_tile.y * tile_map.chunk_dim + chunk_pos.rel_tile.x] = val
    }
}

recanonicalize_coord :: proc(tile_map: ^TileMap, abs_tile: ^u32, rel_tile: ^f32) {
    offset: i32 = i32(math.round(rel_tile^ / tile_map.tile_side_in_feet))
    abs_tile^ += u32(offset)
    rel_tile^ -= f32(offset)*tile_map.tile_side_in_feet
}

recanonicalize_position :: proc(tile_map: ^TileMap, pos: TileMapPosition) -> TileMapPosition {
    res : TileMapPosition = pos

    recanonicalize_coord(tile_map, &res.abs_tile.x, &res.rel_tile.x)
    recanonicalize_coord(tile_map, &res.abs_tile.y, &res.rel_tile.y)

    return res
}
