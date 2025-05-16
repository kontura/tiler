package main_web

import "core:c"

EMSCRIPTEN_WEBSOCKET_T :: c.int
EMSCRIPTEN_RESULT :: c.int
pthread_t :: c.ulong
EM_CALLBACK_THREAD_CONTEXT_CALLING_THREAD :: 2

EmscriptenWebSocketOpenEvent :: struct {
    socket: EMSCRIPTEN_WEBSOCKET_T,
}
EmscriptenWebSocketMessageEvent :: struct {
    socket: EMSCRIPTEN_WEBSOCKET_T,
    data: [^]u8,
    numBytes: u32,
    isText: c.bool,
}

em_websocket_open_callback_func :: proc "c" (eventType: c.int, #by_ptr websocketEvent: EmscriptenWebSocketOpenEvent, userData: rawptr ) -> c.bool
em_websocket_message_callback_func :: proc "c" (eventType: c.int, #by_ptr websocketEvent: EmscriptenWebSocketMessageEvent, userData: rawptr ) -> c.bool

EmscriptenWebSocketCreateAttributes :: struct {
    url: cstring,
    protocols: cstring,
    createOnMainThread: c.bool,
}

@(default_calling_convention = "c")
foreign {
        emscripten_websocket_is_supported :: proc() -> c.int ---
        emscripten_websocket_new :: proc(createAttributes: ^EmscriptenWebSocketCreateAttributes) -> EMSCRIPTEN_WEBSOCKET_T ---
        emscripten_websocket_set_onopen_callback_on_thread :: proc(socket: EMSCRIPTEN_WEBSOCKET_T, userData: rawptr, callback: em_websocket_open_callback_func, targetThread: pthread_t ) -> EMSCRIPTEN_RESULT ---
        emscripten_websocket_set_onmessage_callback_on_thread :: proc(socket: EMSCRIPTEN_WEBSOCKET_T, userData: rawptr, callback: em_websocket_message_callback_func, targetThread: pthread_t ) -> EMSCRIPTEN_RESULT ---
        emscripten_websocket_set_onclose_callback_on_thread :: proc(socket: EMSCRIPTEN_WEBSOCKET_T, userData: rawptr, callback: em_websocket_open_callback_func, targetThread: pthread_t ) -> EMSCRIPTEN_RESULT ---
        emscripten_websocket_set_onerror_callback_on_thread :: proc(socket: EMSCRIPTEN_WEBSOCKET_T, userData: rawptr, callback: em_websocket_open_callback_func, targetThread: pthread_t ) -> EMSCRIPTEN_RESULT ---
        emscripten_websocket_send_utf8_text :: proc(socket: EMSCRIPTEN_WEBSOCKET_T, textData: cstring) -> EMSCRIPTEN_RESULT ---
        emscripten_websocket_send_binary :: proc(socket: EMSCRIPTEN_WEBSOCKET_T, binData: rawptr, dataLen: c.uint32_t) -> EMSCRIPTEN_RESULT ---
}
