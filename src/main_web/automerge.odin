package main_web

import "core:c"
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
	AMresultStatus :: proc(result: AMresultPtr) -> AMstatus ---
	AMresultItem :: proc(result: AMresultPtr) -> AMitemPtr ---
	AMitemToDoc :: proc(item: AMitemPtr, doc: ^AMdocPtr) -> c.bool ---

	AMmapPutStr :: proc(doc: AMdocPtr, obj_id: AMobjIdPtr, key: AMbyteSpan, value: AMbyteSpan) -> AMresultPtr ---
	AMmapPutBytes :: proc(doc: AMdocPtr, obj_id: AMobjIdPtr, key: AMbyteSpan, value: AMbyteSpan) -> AMresultPtr ---
        AMmapPutObject :: proc(doc: AMdocPtr, obj_id: AMobjIdPtr, key: AMbyteSpan, obj_type: AMobjType) -> AMresultPtr ---
        AMmapPutInt :: proc(doc: AMdocPtr, obj_id: AMobjIdPtr, key: AMbyteSpan, value: c.int64_t) -> AMresultPtr ---
        AMmapPutUint :: proc(doc: AMdocPtr, obj_id: AMobjIdPtr, key: AMbyteSpan, value: c.uint64_t) -> AMresultPtr ---

	AMmapGet :: proc(doc: AMdocPtr, obj_id: AMobjIdPtr, key: AMbyteSpan, heads: AMitemsPtr) -> AMresultPtr ---

        AMlistPutObject :: proc(doc: AMdocPtr, obj_id: AMobjIdPtr, pos: c.size_t, insert: bool, obj_type: AMobjType) -> AMresultPtr ---
        AMlistGet :: proc(doc: AMdocPtr, obj_id: AMobjIdPtr, pos: c.size_t, heads: AMitemsPtr) -> AMresultPtr ---

	AMresultError :: proc(result: AMresultPtr) -> AMbyteSpan ---

	AMitemToStr :: proc(item: AMitemPtr, value: ^AMbyteSpan) -> c.bool ---
	AMitemToBytes :: proc(item: AMitemPtr, value: ^AMbyteSpan) -> c.bool ---
	AMitemToUint :: proc(item: AMitemPtr, value: ^c.uint64_t) -> c.bool ---
	AMitemToInt :: proc(item: AMitemPtr, value: ^c.int64_t) -> c.bool ---

        AMitemObjId :: proc(item: AMitemPtr) -> AMobjIdPtr ---
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

odin_str :: proc(str: string) -> AMbyteSpan {
    span: AMbyteSpan
    span.src = raw_data(str)
    span.count = len(str)

    return span
}

decode_and_receive :: proc(
	data: [^]u8,
	byte_count: uint,
	doc: AMdocPtr,
	sync_state: AMsyncStatePtr,
) {
	fmt.println("recieved count: ", byte_count)
	decodeResult := AMsyncMessageDecode(data, byte_count)
	if (AMresultStatus(decodeResult) != AMstatus.AM_STATUS_OK) {
		fmt.println("error encountered decodeResult")
	}
	automerge_msg: AMsyncMessagePtr
	AMitemToSyncMessage(AMresultItem(decodeResult), &automerge_msg)
	receiveResult := AMreceiveSyncMessage(doc, sync_state, automerge_msg)
	defer AMresultFree(receiveResult)
	if (AMresultStatus(receiveResult) != AMstatus.AM_STATUS_OK) {
		fmt.println("error encountered receiveResult")
	}
}

generate_and_encode :: proc(doc: AMdocPtr, sync_state: AMsyncStatePtr) -> (AMbyteSpan, bool) {
	msgResult := AMgenerateSyncMessage(doc, sync_state)
	//defer AMresultFree(msgResult)
	if (AMresultStatus(msgResult) != AMstatus.AM_STATUS_OK) {
		fmt.println("error encountered msgResult")
	}
	msgItem := AMresultItem(msgResult)

	msg_bytes: AMbyteSpan
	#partial switch AMitemValType(msgItem) {
	case .AM_VAL_TYPE_SYNC_MESSAGE:
		msg: AMsyncMessagePtr
		AMitemToSyncMessage(msgItem, &msg)
		encodeResult := AMsyncMessageEncode(msg)
		if !AMitemToBytes(AMresultItem(encodeResult), &msg_bytes) {
			fmt.println("error encountered encodeResult")
		}
		fmt.println("generated count: ", msg_bytes.count)
		return msg_bytes, false

	case .AM_VAL_TYPE_VOID:
		return msg_bytes, true
	}
	assert(false)
	return msg_bytes, false
}

print_map_key_value :: proc(doc: AMdocPtr, obj_id: AMobjIdPtr, key: cstring) {
	getResult: AMresultPtr = AMmapGet(doc, obj_id, AMstr(key), c.NULL)
	defer AMresultFree(getResult)
	if (AMresultStatus(getResult) != AMstatus.AM_STATUS_OK) {
		fmt.println("error encountered getResult")
	}

	got: AMbyteSpan
	if (AMitemToStr(AMresultItem(getResult), &got)) {
		fmt.println("value under ", key, " key: ", string(got.src[:got.count]))
	} else {
		fmt.println("expected to read a string")
	}

}
