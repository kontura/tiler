package tiler_tests

import tiler "../src"
import "core:bytes"
import "core:fmt"
import "core:strings"
import "core:testing"

setup :: proc(id: u64 = 1) -> (tiler.GameState, tiler.TileMap) {
    my_state: tiler.GameState
    my_tile_map: tiler.TileMap
    tiler.game_state_init(&my_state, false, 100, 100, "root", "path", false)
    my_state.id = id
    tiler.tile_map_init(&my_tile_map, false)

    return my_state, my_tile_map
}

teardown :: proc(state: ^tiler.GameState, tile_map: ^tiler.TileMap) {
    tiler.tokens_reset(state)
    delete(state.initiative_to_tokens)
    for id, _ in state.tokens {
        tiler.delete_token(&state.tokens[id])
    }
    delete(state.tokens)

    for _, index in state.undo_history {
        tiler.delete_action(&state.undo_history[index])
    }
    delete(state.undo_history)

    tiler.tilemap_delete(tile_map)
    delete(tile_map.tile_chunks)
}


@(test)
all_actions_tests :: proc(t: ^testing.T) {
    files := tiler.list_files_in_dir("./tests")

    for &expected_file in files {
        if strings.ends_with(expected_file, ".expected") {
            test_name := strings.trim_suffix(expected_file, ".expected")
            state, tile_map := setup()
            full_actions_file := fmt.aprint("./tests/", test_name, sep="", allocator=context.temp_allocator)
            ok_actions := tiler.load_save_override(&state, &tile_map, full_actions_file)
            testing.expect(t, ok_actions, fmt.aprint("Failed to load:", full_actions_file, allocator=context.temp_allocator))

            full_expected_file := fmt.aprint("./tests/", expected_file, sep="", allocator=context.temp_allocator)
            expected_data, ok_map := tiler.read_entire_file(full_expected_file, context.temp_allocator)
            testing.expect(t, ok_map, fmt.aprint("Failed to load expected:", full_expected_file, allocator=context.temp_allocator))
            s: tiler.Serializer
            tiler.serializer_init_reader(&s, expected_data)
            tiler.serialize(&s, &s.version)
            expected_tile_map: tiler.TileMap
            tiler.serialize(&s, &expected_tile_map)
            expected_tokens: map[u64]tiler.Token
            tiler.serialize(&s, &expected_tokens)

            //TODO(amatej): verify tokens match
            delete(expected_tokens)
            for _, &token in expected_tokens {
                tiler.delete_token(&token)
            }

            equal, msg := tiler.tile_maps_equal(&tile_map, &expected_tile_map)
            full_msg := fmt.aprint(test_name, ": ", msg, sep="", allocator=context.temp_allocator)
            testing.expect(t, equal, full_msg)

            tiler.tilemap_delete(&expected_tile_map)
            delete(expected_tile_map.tile_chunks)
            teardown(&state, &tile_map)
        }
    }
}
