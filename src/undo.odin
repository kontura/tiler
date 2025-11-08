package tiler
import "core:crypto/sha2"
import "core:fmt"
import "core:mem"
import "core:slice"
import "core:sort"
import "core:strings"
import "core:time"

ActionType :: enum {
    BRUSH,
    RECTANGLE,
    CIRCLE,
    // All EDIT_TOKEN actions have to touch only the token,
    // once they start changing other things (initiative tracker,..)
    // it has to be separate action.
    EDIT_TOKEN_INITIATIVE,
    EDIT_TOKEN_NAME,
    EDIT_TOKEN_SIZE,
    EDIT_TOKEN_LIFE,
    EDIT_TOKEN_POSITION,
    WALL,
    LIGHT_SOURCE,
    CONE,
}

Action :: struct {
    // SYNCED
    type:                   ActionType,
    start:                  TileMapPosition,
    end:                    TileMapPosition,
    color:                  [4]u8,
    radius:                 f64,
    token_id:               u64,
    token_initiative_end:   [2]i32,
    token_initiative_start: [2]i32,
    token_life:             bool,
    token_size:             f64,

    // This can work for only one token
    // But will we ever rename more tokens at once>
    old_name:               string,
    new_name:               string,
    hash:                   [32]u8,
    author_id:              u64,
    authors_index:          u64,

    // NOT SYNCED

    // Whether this action can be reverted.
    // Actions that have already been reverted or are reverting
    // actions cannot be reverted again.
    reverted:               bool,

    // Whether this action was made by me, not other peers
    mine:                   bool,

    // Tile xor value
    // Not synced, used only for undo (this is fine because in order to do undo we
    // have to first redo and this populates tile_history)
    tile_history:           map[[2]u32]Tile,
}

to_string_action :: proc(action: ^Action, allocator := context.allocator) -> string {
    builder := strings.builder_make(allocator)
    at, _ := fmt.enum_value_to_string(action.type)
    strings.write_string(&builder, at)
    switch action.type {
    case .BRUSH:
        {
            strings.write_string(&builder, ", tile_history len: ")
            strings.write_int(&builder, len(action.tile_history))
        }
    case .RECTANGLE, .CONE, .WALL:
        {
            start_text := fmt.aprint(action.start, allocator = context.temp_allocator)
            end_text := fmt.aprint(action.end, allocator = context.temp_allocator)
            color_text := fmt.aprint(action.color, allocator = context.temp_allocator)
            strings.write_string(&builder, " (")
            strings.write_string(&builder, color_text)
            strings.write_string(&builder, ") ")
            strings.write_string(&builder, ", ")
            strings.write_string(&builder, start_text)
            strings.write_string(&builder, " - ")
            strings.write_string(&builder, end_text)
            strings.write_string(&builder, ", tile_history len: ")
            strings.write_int(&builder, len(action.tile_history))
        }
    case .CIRCLE:
        {
            start_text := fmt.aprint(action.start, allocator = context.temp_allocator)
            radius_text := fmt.aprint(action.radius, allocator = context.temp_allocator)
            color_text := fmt.aprint(action.color, allocator = context.temp_allocator)
            strings.write_string(&builder, " (")
            strings.write_string(&builder, color_text)
            strings.write_string(&builder, ") ")
            strings.write_string(&builder, ", ")
            strings.write_string(&builder, start_text)
            strings.write_string(&builder, ": ")
            strings.write_string(&builder, radius_text)
            strings.write_string(&builder, ", tile_history len: ")
            strings.write_int(&builder, len(action.tile_history))
        }
    case .EDIT_TOKEN_POSITION:
        {
            start_text := fmt.aprint(action.start, allocator = context.temp_allocator)
            end_text := fmt.aprint(action.end, allocator = context.temp_allocator)
            strings.write_string(&builder, " ( ")
            strings.write_u64(&builder, action.token_id)
            strings.write_string(&builder, " ), ")
            strings.write_string(&builder, start_text)
            strings.write_string(&builder, " -> ")
            strings.write_string(&builder, end_text)
        }
    case .EDIT_TOKEN_INITIATIVE:
        {
            start_text := fmt.aprint(action.token_initiative_start, allocator = context.temp_allocator)
            end_text := fmt.aprint(action.token_initiative_end, allocator = context.temp_allocator)
            strings.write_string(&builder, " ( ")
            strings.write_u64(&builder, action.token_id)
            strings.write_string(&builder, " ), ")
            strings.write_string(&builder, start_text)
            strings.write_string(&builder, " -> ")
            strings.write_string(&builder, end_text)
        }
    case .EDIT_TOKEN_LIFE:
        {
            strings.write_string(&builder, " ( ")
            strings.write_u64(&builder, action.token_id)
            if len(action.new_name) > 0 {
                strings.write_string(&builder, " -  ")
                strings.write_string(&builder, action.new_name)
            }
            strings.write_string(&builder, " ), ")
            if action.token_life {
                strings.write_string(&builder, "SPAWN ( ")
                pos_start_text := fmt.aprint(action.start, allocator = context.temp_allocator)
                init_end_text := fmt.aprint(action.token_initiative_end, allocator = context.temp_allocator)
                color_text := fmt.aprint(action.color, allocator = context.temp_allocator)
                strings.write_string(&builder, pos_start_text)
                strings.write_string(&builder, ", ")
                strings.write_string(&builder, color_text)
                strings.write_string(&builder, ", ")
                strings.write_string(&builder, init_end_text)
                strings.write_string(&builder, " )")
            } else {
                strings.write_string(&builder, "KILL")
            }
        }
    case .EDIT_TOKEN_SIZE:
        {
            token_size_text := fmt.aprint(action.token_size, allocator = context.temp_allocator)
            strings.write_string(&builder, " ( ")
            strings.write_u64(&builder, action.token_id)
            strings.write_string(&builder, " ), ")
            strings.write_string(&builder, token_size_text)
        }
    case .EDIT_TOKEN_NAME:
        {
            strings.write_string(&builder, " ( ")
            strings.write_u64(&builder, action.token_id)
            strings.write_string(&builder, " ), ")
            strings.write_string(&builder, action.old_name)
            strings.write_string(&builder, " -> ")
            strings.write_string(&builder, action.new_name)
        }
    case .LIGHT_SOURCE:
        {
            strings.write_string(&builder, "TODO(amatej): missing")
        }
    }
    return strings.to_string(builder)
}

duplicate_action :: proc(a: ^Action, allocator := context.allocator) -> Action {
    //TODO(amatej): Could we add some detection that all members are copied?
    action: Action = make_action(a.type, allocator = allocator)
    action.start = a.start
    action.end = a.end
    action.color = a.color
    action.radius = a.radius
    action.reverted = a.reverted
    action.mine = a.mine
    action.hash = a.hash
    action.author_id = a.author_id
    action.authors_index = a.authors_index
    action.token_initiative_end = a.token_initiative_end
    action.token_initiative_start = a.token_initiative_start
    action.token_life = a.token_life
    action.token_size = a.token_size
    action.token_id = a.token_id
    action.old_name = strings.clone(a.old_name, allocator)
    action.new_name = strings.clone(a.new_name, allocator)
    action.tile_history = make(map[[2]u32]Tile, allocator = allocator)
    for pos, &hist in a.tile_history {
        action.tile_history[pos] = hist
    }

    return action
}

make_action :: proc(type: ActionType, allocator := context.allocator) -> Action {
    action: Action
    action.tile_history.allocator = allocator
    action.mine = true
    action.type = type

    return action
}

compute_hash_with_prev :: proc(action: ^Action, prev_action_hash: ^[32]u8) -> [32]u8 {
    hash: sha2.Context_256
    sha2.init_256(&hash)

    sha2.update(&hash, mem.ptr_to_bytes(&action.type))
    sha2.update(&hash, mem.ptr_to_bytes(&action.start))
    sha2.update(&hash, mem.ptr_to_bytes(&action.end))
    sha2.update(&hash, mem.ptr_to_bytes(&action.color))
    sha2.update(&hash, mem.ptr_to_bytes(&action.radius))
    sha2.update(&hash, mem.ptr_to_bytes(&action.token_id))

    sha2.update(&hash, mem.ptr_to_bytes(&action.token_initiative_end))
    sha2.update(&hash, mem.ptr_to_bytes(&action.token_initiative_start))
    sha2.update(&hash, mem.ptr_to_bytes(&action.token_life))
    sha2.update(&hash, mem.ptr_to_bytes(&action.token_size))
    sha2.update(&hash, transmute([]u8)(action.old_name))
    sha2.update(&hash, transmute([]u8)(action.new_name))
    sha2.update(&hash, mem.ptr_to_bytes(&action.authors_index))
    sha2.update(&hash, mem.ptr_to_bytes(&action.author_id))

    if action.type == .BRUSH {
        tile_keys := make([dynamic][2]u32, allocator = context.temp_allocator)
        for k, _ in action.tile_history {
            append(&tile_keys, k)
        }
        sort.sort(sort.Interface {
            len = proc(it: sort.Interface) -> int {
                keys := cast(^[][2]u32)it.collection
                return len(keys)
            },
            less = proc(it: sort.Interface, i, j: int) -> bool {
                keys := cast(^[][2]u32)it.collection
                i_key, j_key := keys[i], keys[j]
                if i_key.x != j_key.x {
                    return i_key.x > j_key.x
                }
                return i_key.y > j_key.y
            },
            swap = proc(it: sort.Interface, i, j: int) {
                keys := cast(^[][2]u32)it.collection
                keys[i], keys[j] = keys[j], keys[i]
            },
            collection = &tile_keys,
        })
        for key in tile_keys {
            sha2.update(&hash, mem.ptr_to_bytes(&action.tile_history[key]))
        }
    }

    if prev_action_hash != nil {
        sha2.update(&hash, prev_action_hash^[:])
    }

    h: [32]u8
    sha2.final(&hash, h[:])

    return h
}

serialize_actions :: proc(actions: []Action, allocator := context.allocator) -> []byte {
    s: Serializer
    serializer_init_writer(&s, allocator = allocator)
    as := actions
    serialize(&s, &as)
    return s.data[:]
}

finish_last_undo_history_action :: proc(state: ^GameState) {
    if len(state.undo_history) > 0 {
        action: ^Action = &state.undo_history[len(state.undo_history) - 1]
        action.authors_index = u64(len(state.undo_history))
        state.my_action_count += 1
        action.author_id = state.id

        if len(state.undo_history) > 1 {
            action_before := state.undo_history[len(state.undo_history) - 2]
            action.hash = compute_hash_with_prev(action, &action_before.hash)
        } else {
            action.hash = compute_hash_with_prev(action, nil)
        }

    }
}

delete_action :: proc(action: ^Action) {
    delete(action.tile_history)
    delete(action.old_name)
    delete(action.new_name)
}

revert_action :: proc(action: ^Action, allocator := context.allocator) -> Action {
    reverted := duplicate_action(action, allocator)
    reverted.start, reverted.end = reverted.end, reverted.start
    //TODO(amatej): color is not delta and I don't have the starting color

    reverted.token_initiative_start, reverted.token_initiative_end =
        reverted.token_initiative_end, reverted.token_initiative_start

    reverted.token_life = !reverted.token_life
    reverted.token_size *= -1
    reverted.new_name, reverted.old_name = reverted.old_name, reverted.new_name

    return reverted
}

undo_action :: proc(state: ^GameState, tile_map: ^TileMap, action: ^Action) {
    reverted := revert_action(action, context.temp_allocator)
    redo_action(state, tile_map, &reverted)
}

redo_action :: proc(state: ^GameState, tile_map: ^TileMap, action: ^Action) {
    switch action.type {
    case .RECTANGLE:
        {
            // Some actions can have tile_history (its needed for undo),
            // if present its faster than doing the tool
            if len(action.tile_history) > 0 {
                for abs_tile, &tile in action.tile_history {
                    old_tile := get_tile(tile_map, abs_tile)
                    set_tile(tile_map, abs_tile, tile_xor(&old_tile, &tile))
                }
            } else {
                rectangle_tool(action.start, action.end, action.color, tile_map, action)
            }
        }
    case .CIRCLE:
        {
            if len(action.tile_history) > 0 {
                for abs_tile, &tile in action.tile_history {
                    old_tile := get_tile(tile_map, abs_tile)
                    set_tile(tile_map, abs_tile, tile_xor(&old_tile, &tile))
                }
            } else {
                draw_tile_circle(tile_map, action.start, auto_cast action.radius, action.color, action)
            }
        }
    case .CONE:
        {
            if len(action.tile_history) > 0 {
                for abs_tile, &tile in action.tile_history {
                    old_tile := get_tile(tile_map, abs_tile)
                    set_tile(tile_map, abs_tile, tile_xor(&old_tile, &tile))
                }
            } else {
                draw_cone_tiles(tile_map, action.start, action.end, action.color, action)
            }
        }
    case .WALL:
        {
            if len(action.tile_history) > 0 {
                for abs_tile, &tile in action.tile_history {
                    old_tile := get_tile(tile_map, abs_tile)
                    set_tile(tile_map, abs_tile, tile_xor(&old_tile, &tile))
                }
            } else {
                wall_tool(tile_map, action.start, action.end, action.color, action)
            }
        }
    case .BRUSH:
        {
            for abs_tile, &tile in action.tile_history {
                old_tile := get_tile(tile_map, abs_tile)
                set_tile(tile_map, abs_tile, tile_xor(&old_tile, &tile))
            }
        }
    case .EDIT_TOKEN_POSITION:
        {
            token, ok := &state.tokens[action.token_id]
            if ok {
                token.position = action.end
            }
        }
    case .EDIT_TOKEN_INITIATIVE:
        {
            token, ok := &state.tokens[action.token_id]
            if ok {
                move_initiative_token(state, token.id, action.token_initiative_end.x, action.token_initiative_end.y)
            }
        }
    case .EDIT_TOKEN_LIFE:
        {
            if action.token_life {
                // life is true == token was created
                token, ok := &state.tokens[action.token_id]
                if ok {
                    // guard againts adding the same token id into initiative multiple times
                    if token.alive == false {
                        token.alive = true
                        add_at_initiative(
                            state,
                            token.id,
                            action.token_initiative_end.x,
                            action.token_initiative_end.y,
                        )
                    }
                } else {
                    if action.token_id == u64(len(state.tokens)) {
                        token_spawn(
                            state,
                            nil,
                            action.start,
                            action.color,
                            action.new_name,
                            action.token_initiative_end,
                        )
                    } else {
                        fmt.println(
                            "[WARNING]: REDO attempted to create token with id: ",
                            action.token_id,
                            " but the next available id is: ",
                            len(state.tokens),
                        )
                    }
                }
            } else {
                // life is false == token was deleted
                token, ok := &state.tokens[action.token_id]
                if ok {
                    token_kill(state, tile_map, token, nil)
                }
            }
        }
    case .EDIT_TOKEN_SIZE:
        {
            token, ok := &state.tokens[action.token_id]
            if ok {
                token.size += f32(action.token_size)
            }
        }
    case .EDIT_TOKEN_NAME:
        {
            token, ok := &state.tokens[action.token_id]
            if ok {
                if action.old_name != action.new_name {
                    delete(token.name)
                    token.name = strings.clone(action.new_name)
                    set_texture_based_on_name(state, token)
                }
            }
        }
    case .LIGHT_SOURCE:
        {
            fmt.println("TODO(amatej): missing implementation")
        }
    }
}

// Returns a (normal - from the start) index of the first action that doesn't match in both arrays
// It goes from the back so even if one array is only partial it should work
find_first_not_matching_action :: proc(actions_a: []Action, actions_b: []Action) -> (pos_a, pos_b: int) {
    #reverse for &action_a, index_a in actions_a {
        #reverse for &action_b, index_b in actions_b {
            if action_a.hash == action_b.hash {
                return index_a + 1, index_b + 1
            }
        }
    }

    return 0, 0
}

// Inject based on authors_index and if identical lexicographically based on author_id
// If both author_id and timestamp are identical don't inject
// returns true if action was injected, false otherwise
inject_action :: proc(actions: ^[dynamic]Action, start_at: int, action: ^Action) -> bool {
    for i := start_at; i < len(actions); i += 1 {
        old_action := &actions[i]
        if old_action.authors_index == action.authors_index {
            // if autorhor and timestamp are both identical return without injecting (duplicate action)
            if old_action.author_id == action.author_id {
                return false
            }

            if old_action.author_id > action.author_id {
                inject_at(actions, i, action^)
                return true
            }
        } else if old_action.authors_index > action.authors_index {
            inject_at(actions, i, action^)
            return true
        }
    }
    append(actions, action^)
    return true
}

// returns true if at least one already present action changed hash
merge_and_redo_actions :: proc(
    state: ^GameState,
    tile_map: ^TileMap,
    actions: [dynamic]Action,
) -> (
    hashes_changed: bool,
) {
    fmt.println(actions[:])
    new_to_merge, old_to_merge := find_first_not_matching_action(actions[:], state.undo_history[:])
    fmt.println("new_to_merge: ", new_to_merge, " old_to_merge: ", old_to_merge)
    hashes_changed = false
    for i := len(state.undo_history) - 1; i >= old_to_merge; i -= 1 {
        action := &state.undo_history[i]
        undo_action(state, tile_map, action)
        hashes_changed = true
    }

    // We don't need these actions they are already done and are duplicates
    for i := 0; i < new_to_merge; i += 1 {
        delete_action(&actions[i])
    }
    for i := new_to_merge; i < len(actions); i += 1 {
        if !inject_action(&state.undo_history, old_to_merge, &actions[i]) {
            fmt.println("DROPPING DUPLICATE ACTION: ", actions[i])
            delete_action(&actions[i])
        }
    }
    for i := old_to_merge; i < len(state.undo_history); i += 1 {
        action := &state.undo_history[i]
        redo_action(state, tile_map, action)
        if i == 0 {
            action.hash = compute_hash_with_prev(action, nil)
        } else {
            action_before := state.undo_history[i - 1]
            action.hash = compute_hash_with_prev(action, &action_before.hash)
        }
    }
    delete(actions)
    return hashes_changed
}
