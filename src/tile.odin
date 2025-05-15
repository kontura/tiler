package tiler

import "core:math"

// TODO(amatej): add diagonal walls
Direction :: enum{TOP, LEFT}
WallSet :: bit_set[Direction]

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
    walls: WallSet,
    wall_colors: [Direction][4]u8,

}

TileChunk :: struct {
    tiles: [dynamic] Tile,
}

// Compresed tile chunks are used when serializing only
// It is much more efficient than dumping the entire raw
// TileChunk
CompressedTileChunk :: struct {
    counts: [dynamic]u64,
    tiles: [dynamic]Tile,
}

CompressedTileChunks :: struct {
    tile_chunks: map[[2]u32]CompressedTileChunk,
}

TileMap :: struct {
    chunk_shift : u32,
    chunk_mask : u32,

    chunk_dim : u32,

    tile_side_in_feet: f32,
    tile_side_in_pixels: i32,
    feet_to_pixels: f32,
    pixels_to_feet: f32,

    tile_chunks: map[[2]u32]TileChunk,
}

tile_distance :: proc(tile_map: ^TileMap, p1: TileMapPosition, p2: TileMapPosition) -> f32 {
    p1_feet: [2]f32 = {f32(p1.abs_tile.x), f32(p1.abs_tile.y)} * tile_map.tile_side_in_feet + p1.rel_tile
    p2_feet: [2]f32 = {f32(p2.abs_tile.x), f32(p2.abs_tile.y)} * tile_map.tile_side_in_feet + p2.rel_tile

    return dist(f32, p1_feet, p2_feet)
}

tile_pos_to_crossing_pos :: proc(p: TileMapPosition) -> [2]u32 {
    res : [2]u32 = p.abs_tile
    res.x += p.rel_tile.x > 0 ? 1 : 0
    res.y += p.rel_tile.y > 0 ? 1 : 0

    return res
}

get_tile_chunk :: proc(tile_map: ^TileMap, tile_chunk: [2]u32) -> ^TileChunk {
    res, ok := &tile_map.tile_chunks[tile_chunk]
    if ok {
        return res
    } else {
        tile_map.tile_chunks[tile_chunk] = {make([dynamic]Tile, tile_map.chunk_dim * tile_map.chunk_dim)}
        for i: u32 = 0; i < tile_map.chunk_dim * tile_map.chunk_dim; i += 1 {
            tile_map.tile_chunks[tile_chunk].tiles[i] = tile_make([4]u8{77, 77, 77, 255})
        }
        return &tile_map.tile_chunks[tile_chunk]
    }
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
    tile_make_color_walls_colors,
    tile_make_color_walls_color,
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

tile_make_color_walls_colors :: proc(color: [4]u8, walls: WallSet, wall_colors: [Direction][4]u8) -> Tile {
    t: Tile = {}
    t.color = color
    t.walls = walls
    t.wall_colors = wall_colors

    return t
}

tile_make_color_walls_color :: proc(color: [4]u8, walls: WallSet, wall_color: [4]u8) -> Tile {
    t: Tile = {}
    t.color = color
    t.walls = walls
    for d in walls {
        t.wall_colors[d] = wall_color
    }

    return t
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

// Compress tile chunk to arrays of counts of a given tile in the same order.
// For example: the first counts[0] tiles are tiles[0] in given TileChunk.
compress_tile_chunk :: proc(tile_chunk: ^TileChunk, allocator := context.temp_allocator) -> CompressedTileChunk {
    counts := make([dynamic]u64, allocator)
    tiles := make([dynamic]Tile, allocator)

    counted_tile: Tile = tile_chunk.tiles[0]
    count: u64 = 1
    for i: int = 1; i < len(tile_chunk.tiles); i += 1 {
        if counted_tile == tile_chunk.tiles[i] {
            count += 1
        } else {
            append(&tiles, counted_tile)
            append(&counts, count)
            count = 1
            counted_tile = tile_chunk.tiles[i]
        }
    }
    append(&tiles, counted_tile)
    append(&counts, count)

    return {counts, tiles}
}

decompress_tile_chunk_into :: proc(ctc: ^CompressedTileChunk, tile_chunk: ^TileChunk) {
    assert(len(tile_chunk.tiles) == 0)
    assert(len(ctc.counts) == len(ctc.tiles))
    for i: int = 0; i < len(ctc.counts); i += 1 {
        for j: u64 = 0; j < ctc.counts[i]; j += 1 {
            append(&tile_chunk.tiles, ctc.tiles[i])
        }
    }
}
