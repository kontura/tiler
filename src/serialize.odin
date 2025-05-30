package tiler

import "core:fmt"
import "base:intrinsics"
import "core:mem"
import "base:runtime"
import "core:slice"

// Each update to the data layout should be a value in this enum.
// WARNING: do not change the order of these!
Serializer_Version :: enum u32le {
    initial = 0,

    // Don't remove this!
    LATEST_PLUS_ONE,
}

SERIALIZER_VERSION_LATEST :: Serializer_Version(int(Serializer_Version.LATEST_PLUS_ONE) - 1)

Serializer :: struct {
    is_writing:  bool,
    data:        [dynamic]byte,
    read_offset: int,
    version:     Serializer_Version,
    debug:       Serializer_Debug,
}

when ODIN_DEBUG {
    Serializer_Debug :: struct {
        print_scope: bool,
        depth:       int,
    }
} else {
    Serializer_Debug :: struct {}
}

// TODO: serialize with version
serializer_init_writer :: proc(
    s: ^Serializer,
    capacity: int = 1024,
    allocator := context.allocator,
    loc := #caller_location,
) -> mem.Allocator_Error {
    s^ = {
        is_writing = true,
        version    = SERIALIZER_VERSION_LATEST,
        data       = make([dynamic]byte, 0, capacity, allocator, loc) or_return,
    }
    return nil
}

// Warning: doesn't clone the data, make sure it stays available when deserializing!
serializer_init_reader :: proc(s: ^Serializer, data: []byte) {
    s^ = {
        is_writing = false,
        data = transmute([dynamic]u8)runtime.Raw_Dynamic_Array{
            data = (transmute(runtime.Raw_Slice)data).data,
            len = len(data),
            cap = len(data),
            allocator = runtime.nil_allocator(),
        },
    }
}

serializer_clear :: proc(s: ^Serializer) {
    s.read_offset = 0
    clear(&s.data)
}

// The reader doesn't need to be destroyed, since it doesn't own the memory
serializer_destroy_writer :: proc(s: ^Serializer, loc := #caller_location) {
    assert(s.is_writing)
    delete(s.data, loc)
}

serializer_data :: proc(s: Serializer) -> []u8 {
    return s.data[:]
}

_serializer_debug_scope_indent :: proc(depth: int) {
    for _ in 0 ..< depth do runtime.print_string("  ")
}

_serializer_debug_scope_end :: proc(s: ^Serializer, name: string) {
    when ODIN_DEBUG do if s.debug.print_scope {
        s.debug.depth -= 1
        _serializer_debug_scope_indent(s.debug.depth)
        runtime.print_string("}\n")
    }
}

@(disabled = !ODIN_DEBUG, deferred_in = _serializer_debug_scope_end)
serializer_debug_scope :: proc(s: ^Serializer, name: string) {
    when ODIN_DEBUG do if s.debug.print_scope {
        _serializer_debug_scope_indent(s.debug.depth)
        runtime.print_string(name)
        runtime.print_string(" {")
        runtime.print_string("\n")
        s.debug.depth += 1
    }
}

_serialize_bytes :: proc(s: ^Serializer, data: []byte, loc: runtime.Source_Code_Location) -> bool {
    when ODIN_DEBUG do if s.debug.print_scope {
        _serializer_debug_scope_indent(s.debug.depth)
        fmt.printf("%i bytes, ", len(data))
        if s.is_writing {
            fmt.printf("written: %i\n", len(s.data))
        } else {
            fmt.printf("read: %i/%i\n", s.read_offset, len(s.data))
        }
    }

    if len(data) == 0 {
        return true
    }

    if s.is_writing {
        if _, err := append(&s.data, ..data); err != nil {
            when ODIN_DEBUG {
                panic("Serializer failed to append data", loc)
            }
            return false
        }
    } else {
        if len(s.data) < s.read_offset + len(data) {
            when ODIN_DEBUG {
                panic("Serializer attempted to read past the end of the buffer.", loc)
            }
            return false
        }
        copy(data, s.data[s.read_offset:][:len(data)])
        s.read_offset += len(data)
    }

    return true
}

serialize_opaque :: #force_inline proc(s: ^Serializer, data: ^$T, loc := #caller_location) -> bool {
    return _serialize_bytes(s, #force_inline mem.ptr_to_bytes(data), loc)
}

// Serialize slice, fields are treated as opaque bytes.
serialize_opaque_slice :: proc(s: ^Serializer, data: ^$T/[]$E, loc := #caller_location) -> bool {
    serializer_debug_scope(s, "opaque slice")
    serialize_slice_info(s, data, loc) or_return
    return _serialize_bytes(s, slice.to_bytes(data^), loc)
}

// Serialize dynamic array, but leaves fields empty.
serialize_slice_info :: proc(s: ^Serializer, data: ^$T/[]$E, loc := #caller_location) -> bool {
    serializer_debug_scope(s, "slice info")
    num_items := len(data)
    serialize_number(s, &num_items, loc) or_return
    if !s.is_writing {
        data^ = make([]E, num_items, loc = loc)
    }
    return true
}

// Serialize dynamic array, but leaves fields empty.
serialize_dynamic_array_info :: proc(
    s: ^Serializer,
    data: ^$T/[dynamic]$E,
    loc := #caller_location,
) -> bool {
    serializer_debug_scope(s, "dynamic array info")
    num_items := len(data)
    serialize_number(s, &num_items, loc) or_return
    if !s.is_writing {
        data^ = make([dynamic]E, num_items, num_items, loc = loc)
    }
    return true
}

// Serialize dynamic array, fields are treated as opaque bytes.
serialize_opaque_dynamic_array :: proc(
    s: ^Serializer,
    data: ^$T/[dynamic]$E,
    loc := #caller_location,
) -> bool {
    serializer_debug_scope(s, "opaque dynamic array")
    serialize_dynamic_array_info(s, data, loc) or_return
    return _serialize_bytes(s, slice.to_bytes(data[:]), loc)
}

serialize_opaque_as :: proc(s: ^Serializer, data: ^$T, $CONVERT_T: typeid, loc := #caller_location) -> bool {
    serializer_debug_scope(s, fmt.tprint(typeid_of(T), "as", typeid_of(CONVERT_T)))
    if s.is_writing {
        d := CONVERT_T(data^)
        serialize_opaque(s, &d, loc) or_return
    } else {
        d: CONVERT_T
        serialize_opaque(s, &d, loc) or_return
        data^ = T(d)
    }
    return true
}

// Automatically converts to little endian
serialize_number :: proc(
    s: ^Serializer,
    data: ^$T,
    loc := #caller_location,
) -> bool where intrinsics.type_is_float(T) || intrinsics.type_is_integer(T) {
    serializer_debug_scope(s, fmt.tprint(typeid_of(T), "=", data^))

    // Always
    when ODIN_ENDIAN != .Big {
        // Serialize pointer-sized integers as 64-bit
        switch typeid_of(T) {
        case int:
            return serialize_opaque_as(s, data, i64, loc)
        case uint:
            return serialize_opaque_as(s, data, i64, loc)
        case uintptr:
            return serialize_opaque_as(s, data, i64, loc)
        case:
            return serialize_opaque(s, data, loc)
        }

    } else {

        // odinfmt: disable
        switch typeid_of(T) {
        case int: return serialize_opaque_as(s, data, i64le, loc)
        case i16: return serialize_opaque_as(s, data, i16le, loc)
        case i32: return serialize_opaque_as(s, data, i32le, loc)
        case i64: return serialize_opaque_as(s, data, i64le, loc)
        case i128: return serialize_opaque_as(s, data, i128le, loc)

        case uint: return serialize_opaque_as(s, data, u64le, loc)
        case u16: return serialize_opaque_as(s, data, u16le, loc)
        case u32: return serialize_opaque_as(s, data, u32le, loc)
        case u64: return serialize_opaque_as(s, data, u64le, loc)
        case u128: return serialize_opaque_as(s, data, u128le, loc)
        case uintptr: return serialize_opaque_as(s, data, u64le, loc)

        case f16: return serialize_opaque_as(s, data, f16le, loc)
        case f32: return serialize_opaque_as(s, data, f32le, loc)
        case f64: return serialize_opaque_as(s, data, f64le, loc)

        case:
            return serialize_opaque(s, data, loc)
        }
        // odinfmt: enable
    }
    return false
}


serialize_basic :: proc(
    s: ^Serializer,
    data: ^$T,
    loc := #caller_location,
) -> bool where intrinsics.type_is_enum(T) ||
    intrinsics.type_is_boolean(T) ||
    intrinsics.type_is_bit_set(T) {
    serializer_debug_scope(s, fmt.tprint(typeid_of(T), "=", data^))
    return serialize_opaque(s, data, loc)
}


serialize_array :: proc(s: ^Serializer, data: ^$T/[$S]$E, loc := #caller_location) -> bool {
    serializer_debug_scope(s, fmt.tprint(typeid_of(T)))
    when intrinsics.type_is_numeric(E) {
        serialize_opaque(s, data, loc) or_return
    } else {
        for &v in data {
            serialize(s, &v, loc) or_return
        }
    }
    return true
}


serialize_slice :: proc(s: ^Serializer, data: ^$T/[]$E, loc := #caller_location) -> bool {
    serializer_debug_scope(s, fmt.tprint(typeid_of(T)))
    serialize_slice_info(s, data, loc) or_return
    for &v in data {
        serialize(s, &v, loc) or_return
    }
    return true
}


serialize_string :: proc(s: ^Serializer, data: ^string, loc := #caller_location) -> bool {
    serializer_debug_scope(s, fmt.tprintf("string = \"%s\"", data^))
    return serialize_opaque_slice(s, cast(^[]u8)data, loc)
}


serialize_dynamic_array :: proc(s: ^Serializer, data: ^$T/[dynamic]$E, loc := #caller_location) -> bool {
    serializer_debug_scope(s, fmt.tprint(typeid_of(T)))
    serialize_dynamic_array_info(s, data, loc) or_return
    for &v in data {
        serialize(s, &v, loc) or_return
    }
    return true
}


serialize_map :: proc(s: ^Serializer, data: ^$T/map[$K]$V, loc := #caller_location) -> bool {
    serializer_debug_scope(s, fmt.tprint(typeid_of(T)))
    num_items := len(data)
    serialize_number(s, &num_items, loc) or_return

    if s.is_writing {
        for k, v in data {
            k_ := k
            v_ := v
            serialize(s, &k_, loc) or_return
            when size_of(V) > 0 {
                serialize(s, &v_, loc) or_return
            }
        }
    } else {
        data^ = make_map_cap(map[K]V, num_items)
        for _ in 0 ..< num_items {
            k: K
            v: V
            serialize(s, &k, loc) or_return
            when size_of(V) > 0 {
                serialize(s, &v, loc) or_return
            }
            data[k] = v
        }
    }

    return true
}

// WARNING: this requires RTTI!
serialize_union_tag :: proc(
    s: ^Serializer,
    value: ^$T,
    loc := #caller_location,
) -> bool where intrinsics.type_is_union(T) {
    serializer_debug_scope(s, "union tag")
    tag: i64le
    if s.is_writing {
        tag = reflect.get_union_variant_raw_tag(value^)
    }
    serialize_basic(s, &tag, loc) or_return
    if !s.is_writing {
        reflect.set_union_variant_raw_tag(value^, tag)
    }
    return true
}

serialize_tile_map :: proc(s: ^Serializer, tile_map: ^TileMap, loc := #caller_location) -> bool {
    serialize(s, &tile_map.chunk_shift, loc) or_return
    serialize(s, &tile_map.chunk_mask, loc) or_return
    serialize(s, &tile_map.chunk_dim, loc) or_return
    serialize(s, &tile_map.tile_side_in_feet, loc) or_return
    serialize(s, &tile_map.tile_side_in_pixels, loc) or_return
    serialize(s, &tile_map.feet_to_pixels, loc) or_return
    serialize(s, &tile_map.pixels_to_feet, loc) or_return
    // We don't want to serialize the full tile map, its big and doesn't contain that
    // much information. First we "compress" it and we serialize CompressedTileChunks.
    //serialize(s, &tile_map.tile_chunks, loc) or_return
    return true
}

serialize_tile_chunk :: proc(s: ^Serializer, tile_chunk: ^TileChunk, loc := #caller_location) -> bool {
    serialize(s, &tile_chunk.tiles, loc) or_return
    return true
}

serialize_tile :: proc(s: ^Serializer, tile: ^Tile, loc := #caller_location) -> bool {
    serialize(s, &tile.color, loc) or_return
    serialize(s, &tile.walls, loc) or_return
    serialize(s, &tile.wall_colors, loc) or_return
    return true
}

serialize_tile_map_position :: proc(s: ^Serializer, tile_map_position: ^TileMapPosition, loc := #caller_location) -> bool {
    serialize(s, &tile_map_position.abs_tile, loc) or_return
    serialize(s, &tile_map_position.rel_tile, loc) or_return
    return true
}

serialize_token :: proc(s: ^Serializer, token: ^Token, loc := #caller_location) -> bool {
    serialize(s, &token.id, loc) or_return
    serialize(s, &token.position, loc) or_return
    serialize(s, &token.color, loc) or_return
    serialize(s, &token.name, loc) or_return
    serialize(s, &token.size, loc) or_return
    serialize(s, &token.initiative, loc) or_return
    return true
}

serialize_action :: proc(s: ^Serializer, action: ^Action, loc := #caller_location) -> bool {
    serialize(s, &action.tile_history, loc) or_return
    serialize(s, &action.token_history, loc) or_return
    serialize(s, &action.token_initiative_history, loc) or_return
    serialize(s, &action.token_life, loc) or_return
    return true
}

serialize_game_state :: proc(s: ^Serializer, game_state: ^GameState, loc := #caller_location) -> bool {
    serialize(s, &game_state.camera_pos, loc) or_return
    serialize(s, &game_state.selected_color, loc) or_return
    serialize(s, &game_state.selected_alpha, loc) or_return
    serialize(s, &game_state.draw_grid, loc) or_return
    serialize(s, &game_state.draw_initiative, loc) or_return
    serialize(s, &game_state.active_tool, loc) or_return
    serialize(s, &game_state.max_entity_id, loc) or_return
    serialize(s, &game_state.undo_history, loc) or_return
    serialize(s, &game_state.tokens, loc) or_return
    serialize(s, &game_state.initiative_to_tokens, loc) or_return
    return true
}

serialize_compressed_tile_chunks :: proc(s: ^Serializer, ctcs: ^CompressedTileChunks, loc := #caller_location) -> bool {
    serialize(s, &ctcs.tile_chunks, loc) or_return
    return true
}

serialize_compressed_tile_chunk :: proc(s: ^Serializer, ctc: ^CompressedTileChunk, loc := #caller_location) -> bool {
    serialize(s, &ctc.counts, loc) or_return
    serialize(s, &ctc.tiles, loc) or_return
    return true
}

serialize :: proc {
    serialize_number,
    serialize_basic,
    serialize_array,
    serialize_slice,
    serialize_string,
    serialize_dynamic_array,
    serialize_map,

    // Add your custom serialization procedures here
    serialize_tile_map,
    serialize_tile_chunk,
    serialize_tile,
    serialize_tile_map_position,
    serialize_game_state,
    serialize_token,
    serialize_action,
    serialize_compressed_tile_chunks,
    serialize_compressed_tile_chunk,
}
