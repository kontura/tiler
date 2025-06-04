package automerge
import "core:testing"
import "core:fmt"

get_new_doc :: proc() -> AMdocPtr {
    doc_result := AMcreate(nil)
    item, _ := result_to_item(doc_result)
    doc: AMdocPtr
    if !AMitemToDoc(item, &doc) {
        assert(false)
    }
    return doc
}

// The main interface should be: put_into_map and get_from_map

@(test)
add_number_to_doc :: proc(t: ^testing.T) {
    doc := get_new_doc()

    testing.expect_value(t, put_into_map(doc, AM_ROOT, "key", u64(99)), true)
    testing.expect_value(t, get_from_map(doc, AM_ROOT, "key", u64), 99)
}


@(test)
add_string_to_doc :: proc(t: ^testing.T) {
    doc := get_new_doc()

    testing.expect_value(t, put_into_map(doc, AM_ROOT, "key", "test string"), true)
    testing.expect_value(t, get_from_map(doc, AM_ROOT, "key", string), "test string")
}

@(test)
add_fixed_byte_array_to_doc :: proc(t: ^testing.T) {
    doc := get_new_doc()

    color : [4]u8 = {255, 0, 255, 0}
    testing.expect_value(t, put_into_map(doc, AM_ROOT, "key", color), true)
    testing.expect_value(t, get_from_map(doc, AM_ROOT, "key", [4]u8), color)
}

@(test)
add_fixed_num_array_to_doc :: proc(t: ^testing.T) {
    doc := get_new_doc()

    arr : [4]i32 = {3, -33, 9999, 1}
    testing.expect_value(t, put_into_map(doc, AM_ROOT, "key", arr), true)
    testing.expect_value(t, get_from_map(doc, AM_ROOT, "key", [4]i32), arr)
}


@(test)
add_enum_to_doc :: proc(t: ^testing.T) {
    doc := get_new_doc()

    ENUM_VAL :: enum {
            ONE = 0,
            TWO,
            THREE,
    }

    testing.expect_value(t, put_into_map(doc, AM_ROOT, "key", ENUM_VAL.THREE), true)
    testing.expect_value(t, get_from_map(doc, AM_ROOT, "key", ENUM_VAL), ENUM_VAL.THREE)
}

@(test)
add_bitset_to_doc :: proc(t: ^testing.T) {
    doc := get_new_doc()

    Direction :: enum{TOP, LEFT}
    WallSet :: bit_set[Direction]

    walls : WallSet = {Direction.LEFT, Direction.TOP}
    testing.expect_value(t, put_into_map(doc, AM_ROOT, "key", walls), true)
    testing.expect_value(t, get_from_map(doc, AM_ROOT, "key", WallSet), walls)

    walls = {Direction.TOP}
    testing.expect_value(t, put_into_map(doc, AM_ROOT, "key", walls), true)
    testing.expect_value(t, get_from_map(doc, AM_ROOT, "key", WallSet), walls)

    walls = {}
    testing.expect_value(t, put_into_map(doc, AM_ROOT, "key", walls), true)
    testing.expect_value(t, get_from_map(doc, AM_ROOT, "key", WallSet), walls)
}

@(test)
add_basic_map_to_doc :: proc(t: ^testing.T) {
    doc := get_new_doc()

    m := make(map[u64]i64, allocator=context.temp_allocator)
    m[5] = -9

    testing.expect_value(t, put_into_map(doc, AM_ROOT, "key", m), true)
    m_from_doc := get_from_map(doc, AM_ROOT, "key", map[u64]i64)
    testing.expect_value(t, m_from_doc[5], m[5])
}


@(test)
add_map_to_doc :: proc(t: ^testing.T) {
    doc := get_new_doc()

    m := make(map[u64][2]i32, allocator=context.temp_allocator)
    m[5] = {-9, 3}
    m[1] = {1, 8}

    testing.expect_value(t, put_into_map(doc, AM_ROOT, "key", m), true)
    m_from_doc := get_from_map(doc, AM_ROOT, "key", map[u64][2]i32)
    testing.expect_value(t, m_from_doc[5], m[5])
    testing.expect_value(t, m_from_doc[1], m[1])
    testing.expect_value(t, m_from_doc[2], m[2])
}


@(test)
add_array_of_array_to_doc :: proc(t: ^testing.T) {
    doc := get_new_doc()

    Direction :: enum{TOP, LEFT}
    a : [Direction][4]u8
    a[.TOP] = {255, 55, 77, 22}
    a[.LEFT] = {11, 99, 9, 0}

    testing.expect_value(t, put_into_map(doc, AM_ROOT, "key", a), true)
    testing.expect_value(t, get_from_map(doc, AM_ROOT, "key", [Direction][4]u8), a)


    b : [Direction][4]u8
    b[.LEFT] = {255, 55, 77, 22}
    testing.expect_value(t, put_into_map(doc, AM_ROOT, "key", b), true)
    testing.expect_value(t, get_from_map(doc, AM_ROOT, "key", [Direction][4]u8), b)

    c : [Direction][4]u8
    testing.expect_value(t, put_into_map(doc, AM_ROOT, "key", c), true)
    testing.expect_value(t, get_from_map(doc, AM_ROOT, "key", [Direction][4]u8), c)

    d : [Direction][4]u8
    d[.TOP] = {1, 55, 77, 22}
    testing.expect_value(t, put_into_map(doc, AM_ROOT, "key", d), true)
    testing.expect_value(t, get_from_map(doc, AM_ROOT, "key", [Direction][4]u8), d)
}
