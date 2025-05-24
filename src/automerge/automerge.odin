package automerge

import "core:c"
import "core:strings"
import "core:fmt"

AMactorIdPtr :: rawptr
AMresultPtr :: rawptr
AMitemPtr :: rawptr
AMdocPtr :: rawptr
AMobjIdPtr :: rawptr
AMsyncStatePtr :: rawptr
AMsyncMessagePtr :: rawptr

// This actually is accessible struct
AMitemsPtr :: rawptr

AMitems :: struct {
    details: [+8+8+8]u8,
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

        AMmapRange :: proc(doc: AMdocPtr, obj_id: AMobjIdPtr, begin: AMbyteSpan, end: AMbyteSpan, heads: AMitemsPtr) -> AMresultPtr ---
	AMmapGet :: proc(doc: AMdocPtr, obj_id: AMobjIdPtr, key: AMbyteSpan, heads: AMitemsPtr) -> AMresultPtr ---
	AMmapDelete :: proc(doc: AMdocPtr, obj_id: AMobjIdPtr, key: AMbyteSpan) -> AMresultPtr ---

        AMlistPutObject :: proc(doc: AMdocPtr, obj_id: AMobjIdPtr, pos: c.size_t, insert: bool, obj_type: AMobjType) -> AMresultPtr ---
        AMlistGet :: proc(doc: AMdocPtr, obj_id: AMobjIdPtr, pos: c.size_t, heads: AMitemsPtr) -> AMresultPtr ---
        AMlistRange :: proc(doc: AMdocPtr, obj_id: AMobjIdPtr, begin: c.size_t, end: c.size_t, heads: AMitemsPtr) -> AMresultPtr ---

	AMresultError :: proc(result: AMresultPtr) -> AMbyteSpan ---

	AMitemToStr :: proc(item: AMitemPtr, value: ^AMbyteSpan) -> c.bool ---
	AMitemToBytes :: proc(item: AMitemPtr, value: ^AMbyteSpan) -> c.bool ---
	AMitemToUint :: proc(item: AMitemPtr, value: ^c.uint64_t) -> c.bool ---
	AMitemToInt :: proc(item: AMitemPtr, value: ^c.int64_t) -> c.bool ---

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
}

AMitemTo :: proc {
    AMitemToUint,
    AMitemToInt,
    AMitemToString,
    AMitemToBytes,
}

AMmapPut :: proc {
    AMmapPutStr,
    AMmapPutString,
    AMmapPutObject,
    AMmapPutInt,
    AMmapPutUint,
}

AMmapPutString :: proc(doc: AMdocPtr, obj_id: AMobjIdPtr, key: AMbyteSpan, value: string) -> AMresultPtr {
    return AMmapPutStr(doc, obj_id, key, AMstr(strings.clone_to_cstring(value, allocator=context.temp_allocator)))
}

AMitemToString :: proc(item: AMitemPtr, value: ^string) -> c.bool {
    got: AMbyteSpan
    if (AMitemToStr(item, &got)) {
        value^ = string(got.src[:got.count])
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

put_map_value :: proc(doc: AMdocPtr, obj_id: AMobjIdPtr, key: cstring, value: $T, loc := #caller_location) -> bool {
    result := AMmapPut(doc, obj_id, AMstr(key), T(value))
    defer AMresultFree(result)
    verify_result(result) or_return
    return true
}

get_map_value :: proc(doc: AMdocPtr, obj_id: AMobjIdPtr, key: cstring, $T: typeid, loc := #caller_location) -> T {
    result := AMmapGet(doc, obj_id, AMstr(key), c.NULL)
    defer AMresultFree(result)
    item, _ := result_to_item(result)
    return item_to_or_report(item, T)
}

decode_and_receive :: proc(
	data: [^]u8,
	byte_count: uint,
	doc: AMdocPtr,
	sync_state: AMsyncStatePtr,
) {
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

verify_result :: proc(result: AMresultPtr, loc := #caller_location) -> (status:bool) {
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

am_byte_span_to_string :: proc(span: AMbyteSpan) -> string {
    return string(span.src[:span.count])
}
