package tiler
import "core:crypto/sha2"
import "core:fmt"
import "core:mem"
import "core:slice"
import "core:strings"
import "core:time"


Action :: struct {
    // SYNCED
    tool:                     Tool,
    start:                    TileMapPosition,
    end:                      TileMapPosition,
    color:                    [4]u8,
    radius:                   f64,
    token_id:                 u64,

    // Whether this action should be undone (this is an undo action)
    undo:                     bool,
    token_initiative_history: [2]i32,
    token_initiative_start:   [2]i32,
    token_life:               bool,
    token_size:               f64,

    // This can work for only one token
    // But will we ever rename more tokens at once>
    old_name:                 string,
    new_name:                 string,
    hash:                     [32]u8,
    timestamp:                time.Time,
    author_id:                u64,

    // NOT SYNCED

    // Whether this action can be reverted.
    // Actions that have already been reverted or are reverting
    // actions cannot be reverted again.
    reverted:                 bool,

    // Whether this action was made by me, not other peers
    mine:                     bool,

    // This is not synchronized, its local to each peer.
    // Determines if this action was already perfomed.
    performed:                bool,
    // tile delta old_tile - new_tile (this could be a nice cache? because unding an action
    // stored in input format would require to redo all actions from the start, but once done
    // we could store more state in this so we don't have to always redo) Although undo is typically
    // done just once? But the starting actions we get re-done many times..
    tile_history:             map[[2]u32]Tile,
}

duplicate_action :: proc(a: ^Action) -> Action {
    //TODO(amatej): Could we add some detection that all members are copied?
    action: Action = make_action(a.tool, a.tile_history.allocator)
    action.start = a.start
    action.end = a.end
    action.color = a.color
    action.radius = a.radius
    action.undo = a.undo
    action.reverted = a.reverted
    action.mine = a.mine
    action.performed = a.performed
    action.hash = a.hash
    action.author_id = a.author_id
    action.timestamp = a.timestamp
    action.token_initiative_history = a.token_initiative_history
    action.token_initiative_start = a.token_initiative_start
    action.token_life = a.token_life
    action.token_size = a.token_size
    action.token_id = a.token_id
    action.old_name = a.old_name
    action.new_name = a.new_name
    for pos, &hist in a.tile_history {
        action.tile_history[pos] = hist
    }

    return action
}

make_action :: proc(tool: Tool, allocator := context.allocator) -> Action {
    action: Action
    action.tile_history.allocator = allocator
    action.mine = true
    action.tool = tool

    return action
}

compute_hash_with_prev :: proc(action: ^Action, prev_action_hash: ^[32]u8) -> [32]u8 {
    hash: sha2.Context_256
    sha2.init_256(&hash)

    sha2.update(&hash, mem.ptr_to_bytes(&action.tool))
    sha2.update(&hash, mem.ptr_to_bytes(&action.start))
    sha2.update(&hash, mem.ptr_to_bytes(&action.end))
    sha2.update(&hash, mem.ptr_to_bytes(&action.color))
    sha2.update(&hash, mem.ptr_to_bytes(&action.radius))
    sha2.update(&hash, mem.ptr_to_bytes(&action.token_id))

    sha2.update(&hash, mem.ptr_to_bytes(&action.undo))
    sha2.update(&hash, mem.ptr_to_bytes(&action.token_initiative_history))
    sha2.update(&hash, mem.ptr_to_bytes(&action.token_initiative_start))
    sha2.update(&hash, mem.ptr_to_bytes(&action.token_life))
    sha2.update(&hash, mem.ptr_to_bytes(&action.token_size))
    sha2.update(&hash, transmute([]u8)(action.old_name))
    sha2.update(&hash, transmute([]u8)(action.new_name))
    sha2.update(&hash, mem.ptr_to_bytes(&action.timestamp))
    sha2.update(&hash, mem.ptr_to_bytes(&action.author_id))

    if prev_action_hash != nil {
        sha2.update(&hash, prev_action_hash^[:])
    }

    h: [32]u8
    sha2.final(&hash, h[:])

    return h
}

finish_last_undo_history_action :: proc(state: ^GameState) {
    if len(state.undo_history) > 0 {
        action: ^Action = &state.undo_history[len(state.undo_history) - 1]
        action.timestamp = time.now()
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

undo_action :: proc(state: ^GameState, tile_map: ^TileMap, action: ^Action) {
    //make this into a revert, the way git does it, so add a new action with oposite values
    switch action.tool {
    case .RECTANGLE, .BRUSH, .CONE, .CIRCLE, .WALL:
        {
            for abs_tile, &tile in action.tile_history {
                old_tile := get_tile(tile_map, abs_tile)
                set_tile(tile_map, abs_tile, tile_add(&old_tile, &tile))
            }
        }
    case .MOVE_TOKEN, .TOUCH_MOVE:
        {
            token, ok := &state.tokens[action.token_id]
            if ok {
                token.position = action.start
            }
        }
    case .EDIT_TOKEN_INITIATIVE:
        {
            token, ok := &state.tokens[action.token_id]
            if ok {
                old_init, old_init_index, ok := get_token_init_pos(state, token.id)
                if ok {
                    new_init_pos := [2]i32{old_init, old_init_index} + action.token_initiative_history
                    move_initiative_token(state, token.id, old_init, old_init_index, new_init_pos.x, new_init_pos.y)
                }
            }
        }
    case .EDIT_TOKEN, .EDIT_TOKEN_LIFE:
        {
            token, ok := &state.tokens[action.token_id]
            if ok {
                if action.token_life {
                    // life is true == token was created (undo is deleteing it)
                    remove_token_by_id_from_initiative(state, token.id)
                    token.alive = false
                } else {
                    // life is false == token was deleted (undo is creating it)
                    token.alive = true
                    add_at_initiative(
                        state,
                        token.id,
                        action.token_initiative_history.x,
                        action.token_initiative_history.y,
                    )
                }
            }
        }
    case .EDIT_TOKEN_SIZE:
        {
            token, ok := &state.tokens[action.token_id]
            if ok {
                token.size -= f32(action.token_size)
            }
        }
    case .EDIT_TOKEN_NAME:
        {
            token, ok := &state.tokens[action.token_id]
            if ok {
                if action.new_name != action.old_name {
                    delete(token.name)
                    token.name = strings.clone(action.old_name)
                    set_texture_based_on_name(state, token)
                }
            }
        }
    case .EDIT_BG, .LIGHT_SOURCE:
        {
            fmt.println("TODO(amatej): missing implementation")
        }
    case .COLOR_PICKER, .HELP, .TOUCH_ZOOM:
        {}
    }

}

redo_action :: proc(state: ^GameState, tile_map: ^TileMap, action: ^Action) {
    // Optimization for redo
    // It cant work for undo because we woudn't know what was under the tiles,
    // we would have to redo from the start up to the undo action
    //fmt.println("redoing action: ", action)
    switch action.tool {
    case .RECTANGLE:
        {
            rectangle_tool(action.start, action.end, action.color, tile_map, action)
        }
    case .CIRCLE:
        {
            draw_tile_circle(tile_map, action.start, auto_cast action.radius, action.color, action)
        }
    case .CONE:
        {
            draw_cone_tiles(tile_map, action.start, action.end, action.color, action)
        }
    case .WALL:
        {
            wall_tool(tile_map, action.start, action.end, action.color, action)
        }
    case .BRUSH:
        {
            for abs_tile, &tile in action.tile_history {
                old_tile := get_tile(tile_map, abs_tile)
                set_tile(tile_map, abs_tile, tile_subtract(&old_tile, &tile))
            }
        }
    case .MOVE_TOKEN, .TOUCH_MOVE:
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
                old_init, old_init_index, ok := get_token_init_pos(state, token.id)
                old: [2]i32 = {old_init, old_init_index}
                //TODO(amatej): first move the token to action.token_initiative_start[token_id]
                //              similarly to what MOVE_TOKEN does
                if ok && old == action.token_initiative_start {
                    new_init_pos := [2]i32{old_init, old_init_index} - action.token_initiative_history
                    move_initiative_token(state, token.id, old_init, old_init_index, new_init_pos.x, new_init_pos.y)
                }
            }
        }
    case .EDIT_TOKEN, .EDIT_TOKEN_LIFE:
        {
            if action.token_life {
                // life is true == token was created
                token, ok := &state.tokens[action.token_id]
                if ok {
                    token.alive = true
                    add_at_initiative(
                        state,
                        token.id,
                        action.token_initiative_history.x,
                        action.token_initiative_history.y,
                    )
                } else {
                    if action.token_id == u64(len(state.tokens)) {
                        token_spawn(
                            state,
                            nil,
                            action.start,
                            action.color,
                            action.new_name,
                            action.token_initiative_history,
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
                    token_kill(state, token, nil)
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
    case .EDIT_BG, .LIGHT_SOURCE:
        {
            fmt.println("TODO(amatej): missing implementation")
        }
    case .COLOR_PICKER, .HELP, .TOUCH_ZOOM:
        {}
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

// Inject based on timestamp and if identical lexicographically based on author_id
inject_action :: proc(actions: ^[dynamic]Action, start_at: int, action: ^Action) {
    for i := start_at; i < len(actions); i += 1 {
        old_action := &actions[i]
        if old_action.timestamp._nsec == action.timestamp._nsec {
            if old_action.author_id > action.author_id {
                inject_at(actions, i, action^)
                return
            }
        } else if old_action.timestamp._nsec > action.timestamp._nsec {
            inject_at(actions, i, action^)
            return
        }
    }
    append(actions, action^)
}

merge_and_redo_actions :: proc(state: ^GameState, tile_map: ^TileMap, actions: [dynamic]Action) {
    //fmt.println(actions[:])
    //fmt.println(state.undo_history[:])
    new_to_merge, old_to_merge := find_first_not_matching_action(actions[:], state.undo_history[:])
    //fmt.println("new_to_merge: ", new_to_merge, " old_to_merge: ", old_to_merge)
    for i := len(state.undo_history) - 1; i >= old_to_merge; i -= 1 {
        action := &state.undo_history[i]
        if action.undo {
            redo_action(state, tile_map, action)
        } else {
            undo_action(state, tile_map, action)
        }
    }

    // We don't need these actions they are already done and are duplicates
    for i := 0; i < new_to_merge; i += 1 {
        delete_action(&actions[i])
    }
    for i := new_to_merge; i < len(actions); i += 1 {
        inject_action(&state.undo_history, old_to_merge, &actions[i])
    }
    for i := old_to_merge; i < len(state.undo_history); i += 1 {
        action := &state.undo_history[i]
        if action.undo {
            undo_action(state, tile_map, action)
        } else {
            redo_action(state, tile_map, action)
        }
        if i == 0 {
            action.hash = compute_hash_with_prev(action, nil)
        } else {
            action_before := state.undo_history[i - 1]
            action.hash = compute_hash_with_prev(action, &action_before.hash)
        }
    }
    delete(actions)
}

redo_unmatched_actions :: proc(
    state: ^GameState,
    tile_map: ^TileMap,
    new_actions: []Action,
) -> (
    old_undone, new_redone: int,
) {
    do_new_from := 0
    #reverse for &performed_action in state.undo_history {
        #reverse for &new_action, new_index in new_actions {
            if performed_action.hash == new_action.hash {
                // +1 so we don't repeat the matching action
                do_new_from = new_index + 1
                break
            }
        }
        if do_new_from != 0 {
            break
        }
        old_undone += 1
        if performed_action.undo {
            redo_action(state, tile_map, &performed_action)
        } else {
            undo_action(state, tile_map, &performed_action)
        }
    }

    for ; do_new_from < len(new_actions); do_new_from += 1 {
        new_redone += 1
        if new_actions[do_new_from].undo {
            undo_action(state, tile_map, &new_actions[do_new_from])
        } else {
            redo_action(state, tile_map, &new_actions[do_new_from])
        }
    }

    return old_undone, new_redone
}

splice_dynamic_arrays_of_actions :: proc(a, b: ^[dynamic]$Action, drop_last_N_of_a, keep_last_N_of_b: int) {
    for i := 0; i < drop_last_N_of_a; i += 1 {
        popped := pop(a)
        delete_action(&popped)
    }
    count := keep_last_N_of_b
    for count > 0 {
        action := b[len(b) - count]
        append(a, action)
        count -= 1
    }
    for i := 0; i < keep_last_N_of_b; i += 1 {
        // we have moved the ending actions of b to a, so just pop, not delete
        pop(b)
    }
    shorted_b := len(b)
    for i := 0; i < shorted_b; i += 1 {
        popped := pop(b)
        delete_action(&popped)
    }
    delete(b^)
}
