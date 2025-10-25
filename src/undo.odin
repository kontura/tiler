package tiler
import "core:fmt"
import "core:hash/xxhash"
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

    // Whether this action should be undone (this is an undo action)
    undo:                     bool,

    //TODO(amatej): remove this
    token_history:            map[u64][2]i32,
    //TODO(amatej): I don't think I need to store the id 4 times..
    token_initiative_history: map[u64][2]i32,
    token_initiative_start:   map[u64][2]i32,
    token_life:               map[u64]bool,
    token_size:               map[u64]f64,

    // This can work for only one token
    // But will we ever rename more tokens at once>
    old_names:                map[u64]string,
    new_names:                map[u64]string,

    // NOT SYNCED

    // Whether this action can be reverted.
    // Actions that have already been reverted or are reverting
    // actions cannot be reverted again.
    reverted:                 bool,
    hash:                     [32]byte,
    my_hash:                  u128,

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
    timestamp:                time.Time,
    author_id:                u64,
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
    action.hash = a.hash
    action.mine = a.mine
    action.performed = a.performed
    action.my_hash = a.my_hash
    action.author_id = a.author_id
    action.timestamp = a.timestamp
    for id, &hist in a.token_history {
        action.token_history[id] = hist
    }
    for id, &hist in a.token_initiative_history {
        action.token_initiative_history[id] = hist
    }
    for id, &hist in a.token_initiative_start {
        action.token_initiative_start[id] = hist
    }
    for id, &hist in a.token_life {
        action.token_life[id] = hist
    }
    for id, &hist in a.token_size {
        action.token_size[id] = hist
    }
    for id, &hist in a.old_names {
        action.old_names[id] = hist
    }
    for id, &hist in a.new_names {
        action.new_names[id] = hist
    }
    for pos, &hist in a.tile_history {
        action.tile_history[pos] = hist
    }

    return action
}

make_action :: proc(tool: Tool, allocator := context.allocator) -> Action {
    action: Action
    action.tile_history.allocator = allocator
    action.token_history.allocator = allocator
    action.token_initiative_history.allocator = allocator
    action.token_initiative_start.allocator = allocator
    action.token_life.allocator = allocator
    action.token_size.allocator = allocator
    action.old_names.allocator = allocator
    action.new_names.allocator = allocator
    action.mine = true
    action.tool = tool

    return action
}

finish_last_undo_history_action :: proc(state: ^GameState) {
    if len(state.undo_history) > 0 {
        action: ^Action = &state.undo_history[len(state.undo_history) - 1]
        action.timestamp = time.now()
        action.author_id = state.id

        hash, _ := xxhash.XXH3_create_state(context.temp_allocator)
        update_hash(hash, action)
        if len(state.undo_history) > 1 {
            action_before := state.undo_history[len(state.undo_history) - 2]
            xxhash.XXH3_128_update(hash, mem.ptr_to_bytes(&action_before.my_hash))
        }

        action.my_hash = xxhash.XXH3_128_digest(hash)
    }

}

delete_action :: proc(action: ^Action) {
    delete(action.tile_history)
    delete(action.token_history)
    delete(action.token_life)
    delete(action.token_initiative_history)
    delete(action.token_initiative_start)
    delete(action.token_size)
    for _, &name in action.old_names {
        delete(name)
    }
    delete(action.old_names)
    for _, &name in action.new_names {
        delete(name)
    }
    delete(action.new_names)
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
            for token_id, &pos_delta in action.token_history {
                token := &state.tokens[token_id]
                token.position = action.start
            }
        }
    case .EDIT_TOKEN_INITIATIVE:
        {
            for token_id, &delta_init_pos in action.token_initiative_history {
                old_init, old_init_index, ok := get_token_init_pos(state, token_id)
                if ok {
                    new_init_pos := [2]i32{old_init, old_init_index} + delta_init_pos
                    move_initiative_token(state, token_id, old_init, old_init_index, new_init_pos.x, new_init_pos.y)
                }
            }
        }
    case .EDIT_TOKEN:
        {
            for token_id, life in action.token_life {
                if life {
                    // life is true == token was created (undo is deleteing it)
                    remove_token_by_id_from_initiative(state, token_id)
                    token, ok := &state.tokens[token_id]
                    if ok {
                        token.alive = false
                    }
                } else {
                    // life is false == token was deleted (undo is creating it)
                    token, ok := &state.tokens[token_id]
                    if ok {
                        token.alive = true
                    }
                    add_at_initiative(
                        state,
                        token.id,
                        action.token_initiative_history[token_id].x,
                        action.token_initiative_history[token_id].y,
                    )
                }
            }
            for token_id, delta_size in action.token_size {
                token, ok := &state.tokens[token_id]
                if ok {
                    token.size -= f32(delta_size)
                }
            }
            for token_id, &old_name in action.old_names {
                token, ok := &state.tokens[token_id]
                if action.new_names[token_id] != old_name {
                    delete(token.name)
                    token.name = strings.clone(old_name)
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
            for token_id, &pos_delta in action.token_history {
                token, ok := &state.tokens[token_id]
                if ok {
                    token.position = action.end
                }
            }
        }
    case .EDIT_TOKEN_INITIATIVE:
        {
            for token_id, &delta_init_pos in action.token_initiative_history {
                old_init, old_init_index, ok := get_token_init_pos(state, token_id)
                old: [2]i32 = {old_init, old_init_index}
                //TODO(amatej): first move the token to action.token_initiative_start[token_id]
                //              similarly to what MOVE_TOKEN does
                if ok && old == action.token_initiative_start[token_id] {
                    new_init_pos := [2]i32{old_init, old_init_index} - delta_init_pos
                    move_initiative_token(state, token_id, old_init, old_init_index, new_init_pos.x, new_init_pos.y)
                }
            }
        }
    case .EDIT_TOKEN:
        {
            // We first have to sort all created tokens by id
            // because tokens have to be created in ascending order
            // otherwise it is an error.
            // We token ids are expected to only ever increase by one
            // to keep consistency.
            keys := make([dynamic]u64, len(action.token_life), allocator = context.temp_allocator)
            i := 0
            for key, _ in action.token_life {
                keys[i] = key
                i += 1
            }
            slice.sort(keys[:])
            for token_id in keys {
                if action.token_life[token_id] {
                    // life is true == token was created
                    token, ok := &state.tokens[token_id]
                    if ok {
                        token.alive = true
                        add_at_initiative(
                            state,
                            token.id,
                            action.token_initiative_history[token_id].x,
                            action.token_initiative_history[token_id].y,
                        )
                    } else {
                        if token_id == u64(len(state.tokens)) {
                            pos: TileMapPosition = {
                                {u32(action.token_history[token_id].x), u32(action.token_history[token_id].y)},
                                {0, 0},
                            }
                            token_spawn(
                                state,
                                nil,
                                pos,
                                action.color,
                                action.new_names[token_id],
                                action.token_initiative_history[token_id],
                            )
                        } else {
                            fmt.println(
                                "[WARNING]: REDO attempted to create token with id: ",
                                token_id,
                                " but the next available id is: ",
                                len(state.tokens),
                            )
                        }
                    }
                } else {
                    // life is false == token was deleted
                    token, ok := &state.tokens[token_id]
                    if ok {
                        token_kill(state, token, nil)
                    }
                }
            }
            for token_id, delta_size in action.token_size {
                token, ok := &state.tokens[token_id]
                if ok {
                    token.size += f32(delta_size)
                }
            }
            for token_id, &new_name in action.new_names {
                token, ok := &state.tokens[token_id]
                if action.old_names[token_id] != new_name {
                    delete(token.name)
                    token.name = strings.clone(new_name)
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

update_hash :: proc(hash: ^xxhash.XXH3_state, action: ^Action) -> xxhash.Error {
    xxhash.XXH3_128_update(hash, mem.ptr_to_bytes(&action.tool)) or_return
    xxhash.XXH3_128_update(hash, mem.ptr_to_bytes(&action.start)) or_return
    xxhash.XXH3_128_update(hash, mem.ptr_to_bytes(&action.end)) or_return
    xxhash.XXH3_128_update(hash, mem.ptr_to_bytes(&action.color)) or_return
    xxhash.XXH3_128_update(hash, mem.ptr_to_bytes(&action.radius)) or_return
    xxhash.XXH3_128_update(hash, mem.ptr_to_bytes(&action.undo)) or_return
    xxhash.XXH3_128_update(hash, mem.ptr_to_bytes(&action.token_history)) or_return
    xxhash.XXH3_128_update(hash, mem.ptr_to_bytes(&action.token_initiative_history)) or_return
    xxhash.XXH3_128_update(hash, mem.ptr_to_bytes(&action.token_initiative_start)) or_return
    xxhash.XXH3_128_update(hash, mem.ptr_to_bytes(&action.token_life)) or_return
    xxhash.XXH3_128_update(hash, mem.ptr_to_bytes(&action.token_size)) or_return
    xxhash.XXH3_128_update(hash, mem.ptr_to_bytes(&action.old_names)) or_return
    xxhash.XXH3_128_update(hash, mem.ptr_to_bytes(&action.new_names)) or_return
    xxhash.XXH3_128_update(hash, mem.ptr_to_bytes(&action.author_id)) or_return
    xxhash.XXH3_128_update(hash, mem.ptr_to_bytes(&action.timestamp)) or_return

    return xxhash.Error.None
}
