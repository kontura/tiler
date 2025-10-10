package automerge

import game ".."
import "base:intrinsics"
import "core:c"
import "core:fmt"
import "core:mem"
import "core:strings"

AMactorIdPtr :: rawptr
AMresultPtr :: rawptr
AMitemPtr :: rawptr
AMdocPtr :: rawptr
AMobjIdPtr :: rawptr
AMsyncStatePtr :: rawptr
AMsyncMessagePtr :: rawptr
AMchangePtr :: rawptr

// This actually is accessible struct
AMitemsPtr :: rawptr

AMitems :: struct {
    details: [+8 + 8 + 8]u8,
}

AMstatus :: enum c.int {
    AM_STATUS_OK = 0,
    AM_STATUS_ERROR,
    AM_STATUS_INVALID_RESULT,
}


AMobjType :: enum c.int {
    /**
   * The default tag, not a type signifier.
   */
    AM_OBJ_TYPE_DEFAULT = 0,
    /**
   * A list.
   */
    AM_OBJ_TYPE_LIST = 1,
    /**
   * A key-value map.
   */
    AM_OBJ_TYPE_MAP,
    /**
   * A list of Unicode graphemes.
   */
    AM_OBJ_TYPE_TEXT,
}

AMvalType :: enum c.int {
    /**
     * An actor identifier value.
     */
    AM_VAL_TYPE_ACTOR_ID     = (1 << 1),
    /**
     * A boolean value.
     */
    AM_VAL_TYPE_BOOL         = (1 << 2),
    /**
     * A view onto an array of bytes value.
     */
    AM_VAL_TYPE_BYTES        = (1 << 3),
    /**
     * A change value.
     */
    AM_VAL_TYPE_CHANGE       = (1 << 4),
    /**
     * A change hash value.
     */
    AM_VAL_TYPE_CHANGE_HASH  = (1 << 5),
    /**
     * A CRDT counter value.
     */
    AM_VAL_TYPE_COUNTER      = (1 << 6),
    /**
     * A cursor value.
     */
    AM_VAL_TYPE_CURSOR       = (1 << 7),
    /**
     * The default tag, not a type signifier.
     */
    AM_VAL_TYPE_DEFAULT      = 0,
    /**
     * A document value.
     */
    AM_VAL_TYPE_DOC          = (1 << 8),
    /**
     * A 64-bit float value.
     */
    AM_VAL_TYPE_F64          = (1 << 9),
    /**
     * A 64-bit signed integer value.
     */
    AM_VAL_TYPE_INT          = (1 << 10),
    /**
     * A mark.
     */
    AM_VAL_TYPE_MARK         = (1 << 11),
    /**
     * A null value.
     */
    AM_VAL_TYPE_NULL         = (1 << 12),
    /**
     * An object type value.
     */
    AM_VAL_TYPE_OBJ_TYPE     = (1 << 13),
    /**
     * A UTF-8 string view value.
     */
    AM_VAL_TYPE_STR          = (1 << 14),
    /**
     * A synchronization have value.
     */
    AM_VAL_TYPE_SYNC_HAVE    = (1 << 15),
    /**
     * A synchronization message value.
     */
    AM_VAL_TYPE_SYNC_MESSAGE = (1 << 16),
    /**
     * A synchronization state value.
     */
    AM_VAL_TYPE_SYNC_STATE   = (1 << 17),
    /**
     * A *nix timestamp (milliseconds) value.
     */
    AM_VAL_TYPE_TIMESTAMP    = (1 << 18),
    /**
     * A 64-bit unsigned integer value.
     */
    AM_VAL_TYPE_UINT         = (1 << 19),
    /**
     * An unknown type of value.
     */
    AM_VAL_TYPE_UNKNOWN      = (1 << 20),
    /**
     * A void.
     */
    AM_VAL_TYPE_VOID         = (1 << 0),
}

AM_ROOT :: c.NULL

AMbyteSpan :: struct {
    src:   [^]c.uint8_t,
    count: c.size_t,
}


@(default_calling_convention = "c")
foreign _ {
    AMcreate :: proc(actor_id: AMactorIdPtr) -> AMresultPtr ---
    AMcommit :: proc(doc: AMdocPtr, message: AMbyteSpan, timestamp: ^i64) -> AMresultPtr ---
    AMresultStatus :: proc(result: AMresultPtr) -> AMstatus ---
    AMresultItem :: proc(result: AMresultPtr) -> AMitemPtr ---
    AMresultItems :: proc(result: AMresultPtr) -> AMitems ---
    AMitemToDoc :: proc(item: AMitemPtr, doc: ^AMdocPtr) -> c.bool ---

    AMmapPutStr :: proc(doc: AMdocPtr, obj_id: AMobjIdPtr, key: AMbyteSpan, value: AMbyteSpan) -> AMresultPtr ---
    AMmapPutBytes :: proc(doc: AMdocPtr, obj_id: AMobjIdPtr, key: AMbyteSpan, value: AMbyteSpan) -> AMresultPtr ---
    AMmapPutObject :: proc(doc: AMdocPtr, obj_id: AMobjIdPtr, key: AMbyteSpan, obj_type: AMobjType) -> AMresultPtr ---
    AMmapPutInt :: proc(doc: AMdocPtr, obj_id: AMobjIdPtr, key: AMbyteSpan, value: c.int64_t) -> AMresultPtr ---
    AMmapPutUint :: proc(doc: AMdocPtr, obj_id: AMobjIdPtr, key: AMbyteSpan, value: c.uint64_t) -> AMresultPtr ---
    AMmapPutF64 :: proc(doc: AMdocPtr, obj_id: AMobjIdPtr, key: AMbyteSpan, value: c.double) -> AMresultPtr ---
    AMmapPutBool :: proc(doc: AMdocPtr, obj_id: AMobjIdPtr, key: AMbyteSpan, value: c.bool) -> AMresultPtr ---

    AMmapRange :: proc(doc: AMdocPtr, obj_id: AMobjIdPtr, begin: AMbyteSpan, end: AMbyteSpan, heads: AMitemsPtr) -> AMresultPtr ---
    AMmapGet :: proc(doc: AMdocPtr, obj_id: AMobjIdPtr, key: AMbyteSpan, heads: AMitemsPtr) -> AMresultPtr ---
    AMmapDelete :: proc(doc: AMdocPtr, obj_id: AMobjIdPtr, key: AMbyteSpan) -> AMresultPtr ---

    AMlistPutObject :: proc(doc: AMdocPtr, obj_id: AMobjIdPtr, pos: c.size_t, insert: bool, obj_type: AMobjType) -> AMresultPtr ---
    AMlistGet :: proc(doc: AMdocPtr, obj_id: AMobjIdPtr, pos: c.size_t, heads: AMitemsPtr) -> AMresultPtr ---
    AMlistRange :: proc(doc: AMdocPtr, obj_id: AMobjIdPtr, begin: c.size_t, end: c.size_t, heads: AMitemsPtr) -> AMresultPtr ---
    AMlistDelete :: proc(doc: AMdocPtr, obj_id: AMobjIdPtr, pos: c.size_t) -> AMresultPtr ---

    AMresultError :: proc(result: AMresultPtr) -> AMbyteSpan ---

    AMitemToStr :: proc(item: AMitemPtr, value: ^AMbyteSpan) -> c.bool ---
    AMitemToBytes :: proc(item: AMitemPtr, value: ^AMbyteSpan) -> c.bool ---
    AMitemToUint :: proc(item: AMitemPtr, value: ^c.uint64_t) -> c.bool ---
    AMitemToInt :: proc(item: AMitemPtr, value: ^c.int64_t) -> c.bool ---
    AMitemToBool :: proc(item: AMitemPtr, value: ^c.bool) -> c.bool ---
    AMitemToCounter :: proc(item: AMitemPtr, value: ^c.int64_t) -> c.bool ---
    AMitemToF64 :: proc(item: AMitemPtr, value: ^c.double) -> c.bool ---
    AMitemToChange :: proc(item: AMitemPtr, value: ^AMchangePtr) -> c.bool ---
    AMitemToChangeHash :: proc(item: AMitemPtr, value: ^AMbyteSpan) -> c.bool ---

    AMitemObjId :: proc(item: AMitemPtr) -> AMobjIdPtr ---
    AMitemsNext :: proc(items: AMitemsPtr, n: c.ptrdiff_t) -> AMitemsPtr ---

    AMobjSize :: proc(doc: AMdocPtr, obj_id: AMobjIdPtr, heads: AMitemsPtr) -> c.size_t ---

    AMresultFree :: proc(result: AMresultPtr) ---
    AMstr :: proc(c_str: cstring) -> AMbyteSpan ---
    AMstrdup :: proc(str: AMbyteSpan, nul: rawptr) -> cstring ---
    AMsyncStateInit :: proc() -> AMresultPtr ---
    AMitemToSyncState :: proc(item: AMitemPtr, sync_state: ^AMsyncStatePtr) -> c.bool ---
    AMgenerateSyncMessage :: proc(doc: AMdocPtr, sync_state: AMsyncStatePtr) -> AMresultPtr ---
    AMreceiveSyncMessage :: proc(doc: AMdocPtr, sync_state: AMsyncStatePtr, sync_message: AMsyncMessagePtr) -> AMresultPtr ---
    AMitemToSyncMessage :: proc(item: AMitemPtr, msg: ^AMsyncMessagePtr) -> c.bool ---
    AMsyncMessageDecode :: proc(src: [^]u8, count: c.size_t) -> AMresultPtr ---
    AMsyncMessageEncode :: proc(sync_message: AMsyncMessagePtr) -> AMresultPtr ---
    AMitemValType :: proc(item: AMitemPtr) -> AMvalType ---

    AMmapPutCounter :: proc(doc: AMdocPtr, obj_id: AMobjIdPtr, key: AMbyteSpan, value: c.int64_t) -> AMresultPtr ---
    AMmapIncrement :: proc(doc: AMdocPtr, obj_id: AMobjIdPtr, key: AMbyteSpan, value: c.int64_t) -> AMresultPtr ---

    // There is some memory problem with this method when using emscripten
    AMsave :: proc(doc: AMdocPtr) -> AMresultPtr ---
    AMclone :: proc(doc: AMdocPtr) -> AMresultPtr ---
    AMsaveIncremental :: proc(doc: AMdocPtr) -> AMresultPtr ---
    AMload :: proc(src: [^]c.uint8_t, count: c.size_t) -> AMresultPtr ---
    AMloadIncremental :: proc(doc: AMdocPtr, src: [^]c.uint8_t, count: c.size_t) -> AMresultPtr ---

    AMgetChanges :: proc(doc: AMdocPtr, have_deps: AMitemsPtr) -> AMresultPtr ---
    AMchangeHash :: proc(change: AMchangePtr) -> AMbyteSpan ---
    AMchangeMessage :: proc(change: AMchangePtr) -> AMbyteSpan ---
    AMchangeIsEmpty :: proc(change: AMchangePtr) -> bool ---
}

//TODO(amatej): add here AMitemToOdinBytes
AMitemTo :: proc {
    AMitemToUint,
    AMitemToInt,
    AMitemToEnum,
    AMitemToBool,
    AMitemToString,
    AMitemToBytes,
    AMitemToF64,
    AMitemToOdinBytes,
}

AMmapPut :: proc {
    AMmapPutBytes,
    AMmapPutOdinBytes,
    AMmapPutString,
    AMmapPutObject,
    AMmapPutInt,
    AMmapPutUint,
    AMmapPutF64,
    AMmapPutBool,
    AMmapPutEnum,
}

AMmapPutOpaue :: proc(doc: AMdocPtr, obj_id: AMobjIdPtr, key: AMbyteSpan, data: ^$T) -> AMresultPtr {
    return AMmapPutOdinBytes(doc, obj_id, key, #force_inline mem.ptr_to_bytes(data))
}

AMmapPutEnum :: proc(
    doc: AMdocPtr,
    obj_id: AMobjIdPtr,
    key: AMbyteSpan,
    value: $T,
) -> AMresultPtr where intrinsics.type_is_enum(T) {
    return AMmapPut(doc, obj_id, key, u64(value))
}

AMmapPutOdinBytes :: proc(doc: AMdocPtr, obj_id: AMobjIdPtr, key: AMbyteSpan, data: []byte) -> AMresultPtr {
    data_bytes: AMbyteSpan
    data_bytes.count = len(data)
    value := data
    data_bytes.src = &value[0]
    return AMmapPut(doc, obj_id, key, data_bytes)
}

AMmapPutString :: proc(doc: AMdocPtr, obj_id: AMobjIdPtr, key: AMbyteSpan, value: string) -> AMresultPtr {
    return AMmapPutStr(doc, obj_id, key, AMstr(strings.clone_to_cstring(value, allocator = context.temp_allocator)))
}

AMitemToString :: proc(item: AMitemPtr, value: ^string) -> c.bool {
    got: AMbyteSpan
    if (AMitemToStr(item, &got)) {
        value^ = strings.clone(string(got.src[:got.count]))
        return true
    } else {
        return false
    }
}

AMitemToEnum :: proc(item: AMitemPtr, value: ^$T) -> c.bool where intrinsics.type_is_enum(T) {
    enum_num: u64
    if (AMitemTo(item, &enum_num)) {
        value^ = T(enum_num)
        return true
    } else {
        return false
    }
}

AMitemToOdinBytes :: proc(item: AMitemPtr, value: ^[]byte) -> c.bool {
    got: AMbyteSpan
    if (AMitemToBytes(item, &got)) {
        value^ = got.src[:got.count]
        return true
    } else {
        return false
    }
}

item_to_or_report :: proc(item: AMitemPtr, $T: typeid, loc := #caller_location) -> T {
    value: T
    if (!AMitemTo(item, &value)) {
        fmt.println("Failed to convert item at: ", loc)
    }
    return value
}


odin_str :: proc(str: string) -> AMbyteSpan {
    span: AMbyteSpan
    span.src = raw_data(str)
    span.count = len(str)

    return span
}

put_into_map :: proc {
    put_map_value,
    put_map_bit_set,
    put_map_map,
    put_map_array,

    // custom types
    put_map_tile,
    put_map_action,
    put_map_tile_map_position,
}

put_map_array :: proc(
    doc: AMdocPtr,
    obj_id: AMobjIdPtr,
    key: cstring,
    value: $T/[$S]$E,
    loc := #caller_location,
) -> bool {
    when intrinsics.type_is_numeric(E) {
        d := value
        result := AMmapPutOpaue(doc, obj_id, AMstr(key), &d)
        defer AMresultFree(result)
        verify_result(result, loc) or_return
    } else {
        //TODO(amatej): For now wrap it in a map, with indexes as keys because I don't have the wrapper ready to handle lists
        //list_result := AMmapPutObject(doc, obj_id, AMstr(key), .AM_OBJ_TYPE_LIST)
        list_result := AMmapPutObject(doc, obj_id, AMstr(key), .AM_OBJ_TYPE_MAP)
        defer AMresultFree(list_result)
        list_id := result_to_objid(list_result) or_return
        i := 0
        for v in value {
            key := fmt.caprint(i, allocator = context.temp_allocator)
            put_into_map(doc, list_id, key, v) or_return
            i += 1
        }
    }
    return true
}

//TODO(amatej): the just a list of key,value,key,value..
put_map_map :: proc(
    doc: AMdocPtr,
    obj_id: AMobjIdPtr,
    key: cstring,
    value: $T/map[$S]$E,
    loc := #caller_location,
) -> bool where intrinsics.type_is_map(T) {
    list_result := AMmapPutObject(doc, obj_id, AMstr(key), .AM_OBJ_TYPE_LIST)
    defer AMresultFree(list_result)
    list_id := result_to_objid(list_result) or_return
    for k, v in value {
        map_result := AMlistPutObject(doc, list_id, c.SIZE_MAX, true, .AM_OBJ_TYPE_MAP)
        defer AMresultFree(map_result)
        map_id := result_to_objid(map_result) or_return
        put_into_map(doc, map_id, "key", k) or_return
        put_into_map(doc, map_id, "value", v) or_return
    }
    return true
}

put_map_bit_set :: proc(
    doc: AMdocPtr,
    obj_id: AMobjIdPtr,
    key: cstring,
    value: $T,
    loc := #caller_location,
) -> bool where intrinsics.type_is_bit_set(T) {
    data := value
    result := AMmapPutOpaue(doc, obj_id, AMstr(key), &data)
    defer AMresultFree(result)
    verify_result(result, loc) or_return
    return true
}

put_map_value :: proc(
    doc: AMdocPtr,
    obj_id: AMobjIdPtr,
    key: cstring,
    value: $T,
    loc := #caller_location,
) -> bool where intrinsics.type_is_integer(T) ||
    intrinsics.type_is_float(T) ||
    intrinsics.type_is_string(T) ||
    intrinsics.type_is_enum(T) ||
    intrinsics.type_is_boolean(T) {
    result := AMmapPut(doc, obj_id, AMstr(key), T(value))
    defer AMresultFree(result)
    verify_result(result, loc) or_return
    return true
}

get_from_map :: proc {
    get_map_value,
    get_map_map,
    get_map_array,
    get_map_bitset,

    // Custom types
    get_map_tile,
    get_map_action,
    get_map_tile_map_position,
}

get_map_map :: proc(
    doc: AMdocPtr,
    obj_id: AMobjIdPtr,
    key: cstring,
    $T: typeid/map[$S]$E,
    loc := #caller_location,
) -> T {
    gotten_map: T
    result := AMmapGet(doc, obj_id, AMstr(key), c.NULL)
    defer AMresultFree(result)
    item, _ := result_to_item(result, loc)

    if AMitemValType(item) != .AM_VAL_TYPE_VOID {
        list_id := AMitemObjId(item)

        range_result := AMlistRange(doc, list_id, 0, c.SIZE_MAX, c.NULL)
        defer AMresultFree(range_result)
        verify_result(range_result)

        items: AMitems = AMresultItems(range_result)
        each_item: AMitemPtr = AMitemsNext(&items, 1)
        for each_item != c.NULL {
            map_id := AMitemObjId(each_item)

            key := get_from_map(doc, map_id, "key", S)
            value := get_from_map(doc, map_id, "value", E)
            gotten_map[key] = value

            each_item = AMitemsNext(&items, 1)
        }
    }

    return gotten_map
}

get_map_array :: proc(
    doc: AMdocPtr,
    obj_id: AMobjIdPtr,
    key: cstring,
    $T: typeid/[$S]$E,
    loc := #caller_location,
) -> T {
    when intrinsics.type_is_numeric(E) {
        result := AMmapGet(doc, obj_id, AMstr(key), c.NULL)
        defer AMresultFree(result)
        item, _ := result_to_item(result, loc)
        bytes: []byte
        if (!AMitemToOdinBytes(item, &bytes)) {
            fmt.println("Failed to convert item at: ", loc)
        }
        value: T
        value_ptr := mem.ptr_to_bytes(&value)
        copy(value_ptr[:], bytes[:len(bytes)])

        return value
    } else {

        result := AMmapGet(doc, obj_id, AMstr(key), c.NULL)
        defer AMresultFree(result)
        item, _ := result_to_item(result, loc)
        value: T

        if AMitemValType(item) != .AM_VAL_TYPE_VOID {
            list_id := AMitemObjId(item)

            //TODO(amatej): for now its a map
            range_result := AMmapRange(doc, list_id, AMstr(nil), AMstr(nil), c.NULL)
            defer AMresultFree(range_result)
            verify_result(range_result)

            items: AMitems = AMresultItems(range_result)
            each_item: AMitemPtr = AMitemsNext(&items, 1)
            i := 0
            for each_item != c.NULL {
                i_key := fmt.caprint(i, allocator = context.temp_allocator)
                item_id := AMitemObjId(each_item)

                v := get_from_map(doc, list_id, i_key, type_of(value[S(0)]))
                value[S(i)] = v

                each_item = AMitemsNext(&items, 1)
                i += 1
            }
        }
        return value
        //panic("implementation is missing")
        //for &v in data {
        //}
    }
}

get_map_bitset :: proc(
    doc: AMdocPtr,
    obj_id: AMobjIdPtr,
    key: cstring,
    $T: typeid,
    loc := #caller_location,
) -> T where intrinsics.type_is_bit_set(T) {
    //TODO(amatej): this is the same as for numeric array --> extract it
    result := AMmapGet(doc, obj_id, AMstr(key), c.NULL)
    defer AMresultFree(result)
    item, _ := result_to_item(result, loc)

    bytes: []byte
    if (!AMitemToOdinBytes(item, &bytes)) {
        fmt.println("Failed to convert item at: ", loc)
    }
    value: T
    value_ptr := mem.ptr_to_bytes(&value)
    copy(value_ptr[:], bytes[:len(bytes)])

    return value
}

get_map_value :: proc(
    doc: AMdocPtr,
    obj_id: AMobjIdPtr,
    key: cstring,
    $T: typeid,
    loc := #caller_location,
) -> T where intrinsics.type_is_integer(T) ||
    intrinsics.type_is_boolean(T) ||
    intrinsics.type_is_float(T) ||
    T == AMbyteSpan ||
    intrinsics.type_is_string(T) ||
    intrinsics.type_is_enum(T) {
    result := AMmapGet(doc, obj_id, AMstr(key), c.NULL)
    defer AMresultFree(result)
    item, _ := result_to_item(result, loc)
    return item_to_or_report(item, T)
}

decode_and_receive :: proc(data: [^]u8, byte_count: uint, doc: AMdocPtr, sync_state: AMsyncStatePtr) {
    decode_result := AMsyncMessageDecode(data, byte_count)
    defer AMresultFree(decode_result)
    item, _ := result_to_item(decode_result)
    assert(AMitemValType(item) == .AM_VAL_TYPE_SYNC_MESSAGE)

    automerge_msg: AMsyncMessagePtr
    AMitemToSyncMessage(item, &automerge_msg)
    receive_result := AMreceiveSyncMessage(doc, sync_state, automerge_msg)
    defer AMresultFree(receive_result)
    verify_result(receive_result)
}

verify_result :: proc(result: AMresultPtr, loc := #caller_location) -> (status: bool) {
    if result == nil {
        return false
    }
    if (AMresultStatus(result) != AMstatus.AM_STATUS_OK) {
        fmt.println("Result status NOT ok: ", am_byte_span_to_string(AMresultError(result)), " at: ", loc)
        return false
    }
    return true
}

result_to_item :: proc(result: AMresultPtr, loc := #caller_location) -> (item: AMitemPtr, status: bool) {
    verify_result(result, loc) or_return
    item = AMresultItem(result)
    return item, true
}

result_to_objid :: proc(result: AMresultPtr, loc := #caller_location) -> (obj_id: AMobjIdPtr, status: bool) {
    item := result_to_item(result, loc) or_return
    obj_id = AMitemObjId(item)
    return obj_id, true
}

// The returned string will be valid only as long as the AMbyteSpan is valid
am_byte_span_to_string :: proc(span: AMbyteSpan) -> string {
    return string(span.src[:span.count])
}
am_byte_span_to_bytes :: proc(span: AMbyteSpan) -> []byte {
    return span.src[:span.count]
}

put_map_tile_map_position :: proc(
    doc: AMdocPtr,
    obj_id: AMobjIdPtr,
    key: cstring,
    value: game.TileMapPosition,
    loc := #caller_location,
) -> bool {
    map_result := AMmapPutObject(doc, obj_id, AMstr(key), .AM_OBJ_TYPE_MAP)
    defer AMresultFree(map_result)
    map_id := result_to_objid(map_result) or_return

    put_into_map(doc, map_id, "abs_tile", value.abs_tile) or_return
    put_into_map(doc, map_id, "rel_tile", value.rel_tile) or_return

    return true
}

get_map_tile_map_position :: proc(
    doc: AMdocPtr,
    obj_id: AMobjIdPtr,
    key: cstring,
    $T: typeid,
    loc := #caller_location,
) -> T where T ==
    game.TileMapPosition {
    map_result := AMmapGet(doc, obj_id, AMstr(key), c.NULL)
    defer AMresultFree(map_result)
    map_id, _ := result_to_objid(map_result)

    tile: game.TileMapPosition
    tile.abs_tile = get_from_map(doc, map_id, "abs_tile", [2]u32)
    tile.rel_tile = get_from_map(doc, map_id, "rel_tile", [2]f32)
    return tile
}

put_map_tile :: proc(
    doc: AMdocPtr,
    obj_id: AMobjIdPtr,
    key: cstring,
    value: game.Tile,
    loc := #caller_location,
) -> bool {
    map_result := AMmapPutObject(doc, obj_id, AMstr(key), .AM_OBJ_TYPE_MAP)
    defer AMresultFree(map_result)
    map_id := result_to_objid(map_result) or_return

    put_into_map(doc, map_id, "color", value.color) or_return
    put_into_map(doc, map_id, "walls", value.walls) or_return
    put_into_map(doc, map_id, "wall_colors", value.wall_colors) or_return

    return true
}


get_map_tile :: proc(
    doc: AMdocPtr,
    obj_id: AMobjIdPtr,
    key: cstring,
    $T: typeid,
    loc := #caller_location,
) -> T where T ==
    game.Tile {
    map_result := AMmapGet(doc, obj_id, AMstr(key), c.NULL)
    defer AMresultFree(map_result)
    map_id, _ := result_to_objid(map_result)

    tile: game.Tile
    tile.color = get_from_map(doc, map_id, "color", [4]u8)
    tile.walls = get_from_map(doc, map_id, "walls", game.WallSet)
    tile.wall_colors = get_from_map(doc, map_id, "wall_colors", [game.Direction][4]u8)
    return tile
}


put_map_action :: proc(
    doc: AMdocPtr,
    obj_id: AMobjIdPtr,
    key: cstring,
    value: ^game.Action,
    loc := #caller_location,
) -> bool {
    map_result := AMmapPutObject(doc, obj_id, AMstr(key), .AM_OBJ_TYPE_MAP)
    defer AMresultFree(map_result)
    map_id := result_to_objid(map_result) or_return

    put_into_map(doc, map_id, "tool", value.tool) or_return
    put_into_map(doc, map_id, "start", value.start) or_return
    put_into_map(doc, map_id, "end", value.end) or_return
    put_into_map(doc, map_id, "color", value.color) or_return
    put_into_map(doc, map_id, "radius", value.radius) or_return

    put_into_map(doc, map_id, "undo", value.undo) or_return

    // BRUSH tool has to sync tile_history because there is no
    // way to describe its effect more concisely.
    if value.undo || value.tool == .BRUSH {
        put_into_map(doc, map_id, "tile_history", value.tile_history) or_return
    }

    put_into_map(doc, map_id, "token_history", value.token_history) or_return
    put_into_map(doc, map_id, "token_initiative_history", value.token_initiative_history) or_return
    put_into_map(doc, map_id, "token_initiative_start", value.token_initiative_start) or_return
    put_into_map(doc, map_id, "token_life", value.token_life) or_return
    put_into_map(doc, map_id, "token_size", value.token_size) or_return

    put_into_map(doc, map_id, "old_names", value.old_names) or_return
    put_into_map(doc, map_id, "new_names", value.new_names) or_return

    return true
}


get_map_action :: proc(
    doc: AMdocPtr,
    obj_id: AMobjIdPtr,
    key: cstring,
    $T: typeid,
    loc := #caller_location,
) -> T where T ==
    game.Action {
    map_result := AMmapGet(doc, obj_id, AMstr(key), c.NULL)
    defer AMresultFree(map_result)
    map_id, _ := result_to_objid(map_result)

    action: game.Action
    action.tool = get_from_map(doc, map_id, "tool", game.Tool)
    action.start = get_from_map(doc, map_id, "start", game.TileMapPosition)
    action.end = get_from_map(doc, map_id, "end", game.TileMapPosition)
    action.color = get_from_map(doc, map_id, "color", [4]u8)
    action.radius = get_from_map(doc, map_id, "radius", f64)

    action.undo = get_from_map(doc, map_id, "undo", bool)

    action.tile_history = get_from_map(doc, map_id, "tile_history", map[[2]u32]game.Tile)
    action.token_history = get_from_map(doc, map_id, "token_history", map[u64][2]i32)
    action.token_initiative_history = get_from_map(doc, map_id, "token_initiative_history", map[u64][2]i32)
    action.token_initiative_start = get_from_map(doc, map_id, "token_initiative_start", map[u64][2]i32)
    action.token_life = get_from_map(doc, map_id, "token_life", map[u64]bool)
    action.token_size = get_from_map(doc, map_id, "token_size", map[u64]f64)

    action.old_names = get_from_map(doc, map_id, "old_names", map[u64]string)
    action.new_names = get_from_map(doc, map_id, "new_names", map[u64]string)

    return action
}
