package tiler

import "core:fmt"
import "core:testing"
import "core:bytes"

@(test)
build_binary_message_test :: proc(t: ^testing.T) {
    msg := build_binary_message(1200, .ACTIONS, 8888, nil)
    expected : []u8 = {1, 8, 176, 4, 0, 0, 0, 0, 0, 0, 8, 184, 34, 0, 0, 0, 0, 0, 0}
    testing.expect(t, bytes.equal(msg, expected), fmt.aprint(expected, " x ", msg, allocator = context.temp_allocator))

    type, sender, target, payload := parse_binary_message(msg)
    testing.expect_value(t, type, MESSAGE_TYPE.ACTIONS)
    testing.expect_value(t, sender, 1200)
    testing.expect_value(t, target, 8888)
    testing.expect_value(t, len(payload), 0)
}
