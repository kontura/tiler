package tiler
import "core:fmt"
import rl "vendor:raylib"

KeyAction :: enum {
    DOWN,
    RELEASED,
    PRESSED,
}

Config :: struct {
    key_triggers: []struct {
        binding: rl.KeyboardKey,
        action:  KeyAction,
    },
    // The order of bindings matter we execute only the first tool matching binding
    bindings:     []struct {
        icon:      rl.GuiIconName,
        //TODO(amatej): reorder? maybe the two maybes should be after each other
        tool:      Maybe(Tool),
        help:      string,
        condition: Maybe(proc(_: ^GameState) -> bool),
        action:    proc(_: ^GameState),
    },
}

move_left :: proc(state: ^GameState) {
    state.camera_pos.rel_tile.x -= 10
}

move_right :: proc(state: ^GameState) {
    state.camera_pos.rel_tile.x += 10
}

are_tokens_selected :: proc(state: ^GameState) -> bool {
    return len(state.selected_tokens) > 0
}

move_selected_tokens_by_delta :: proc(state: ^GameState, delta: [2]i32) {
    delta := delta
    if rl.IsKeyDown(.LEFT_SHIFT) {
        delta *= 6
    }
    for token_id in state.selected_tokens {
        t := &state.tokens[token_id]
        pos := t.position
        abs_tile := pos.abs_tile
        pos.abs_tile.x = u32(i32(pos.abs_tile.x) + delta.x)
        pos.abs_tile.y = u32(i32(pos.abs_tile.y) + delta.y)
        next_token_pos := tile_map_to_screen_coord(pos, state, tile_map)
        rl.SetMousePosition(i32(next_token_pos.x), i32(next_token_pos.y))
    }
}

select_next_init_token :: proc(state: ^GameState, init_start: i32, init_index_start: i32) {
    init_index := init_index_start
    init := init_start
    for loop := 0; loop < 2; loop += 1 {
        for i: i32 = init; i < INITIATIVE_COUNT; i += 1 {
            tokens, ok := &state.initiative_to_tokens[i]
            if ok {
                for ii: i32 = init_index; int(ii) < len(tokens); ii += 1 {
                    append(&state.selected_tokens, tokens[ii])
                    // This could be used to move tokens only by keayboard, when we wannt to start at
                    // token current pos.
                    //t := &state.tokens[tokens[ii]]
                    //next_token_pos := tile_map_to_screen_coord(t.position, state, tile_map)
                    //rl.SetMousePosition(i32(next_token_pos.x), i32(next_token_pos.y))
                    return
                }
            }
            init = 0
            init_index = 0
        }
    }
}

config: []Config = {
    {key_triggers = {{.LEFT, .PRESSED}}, bindings = {{.ICON_ARROW_LEFT, nil, "Move to the left", nil, move_left}}},
    {{{.RIGHT, .PRESSED}}, {{.ICON_ARROW_RIGHT, nil, "Move to the right", nil, move_right}}},
    {
        key_triggers = {{.UP, .PRESSED}},
        bindings     = {
            {
                .ICON_ARROW_UP,
                nil,
                "Move up",
                nil,
                proc(state: ^GameState) {
                    // TODO(amatej): convert to a tool
                    if state.debug {
                        if state.undone > 0 {
                            a := &state.undo_history[len(state.undo_history) - state.undone]
                            if a.undo {
                                undo_action(state, tile_map, a)
                            } else {
                                redo_action(state, tile_map, a)
                            }
                            state.undone -= 1
                        }
                    } else {
                        state.camera_pos.rel_tile.y -= 10
                    }
                },
            },
        },
    },
    {{{.DOWN, .PRESSED}}, {{.ICON_ARROW_DOWN, nil, "Move down", nil, proc(state: ^GameState) {
                    if state.debug {
                        if state.undone < len(state.undo_history) {
                            a := &state.undo_history[len(state.undo_history) - 1 - state.undone]
                            if a.undo {
                                redo_action(state, tile_map, a)
                            } else {
                                undo_action(state, tile_map, a)
                            }
                            state.undone += 1
                        }
                    } else {
                        state.camera_pos.rel_tile.y += 10
                    }
                }}}},
    {{{.P, .PRESSED}}, {{.ICON_PENCIL, nil, "Pintbrush", nil, proc(state: ^GameState) {state.active_tool = .BRUSH}}}},
    {
        {{.R, .PRESSED}},
        {{.ICON_BOX, nil, "Rectangle tool", nil, proc(state: ^GameState) {state.active_tool = .RECTANGLE}}},
    },
    {
        {{.C, .PRESSED}},
        {{.ICON_PLAYER_RECORD, nil, "Circle tool", nil, proc(state: ^GameState) {state.active_tool = .CIRCLE}}},
    },
    {
        {{.W, .PRESSED}},
        {{.ICON_BOX_GRID_BIG, nil, "Wall tool", nil, proc(state: ^GameState) {state.active_tool = .WALL}}},
    },
    {
        {{.S, .PRESSED}},
        {{.ICON_PLAYER, nil, "Edit tokens tool", nil, proc(state: ^GameState) {state.active_tool = .EDIT_TOKEN}}},
    },
    {
        {{.B, .PRESSED}},
        {{.ICON_LAYERS, nil, "Edit background tool", nil, proc(state: ^GameState) {state.active_tool = .EDIT_BG}}},
    },
    {
        {{.M, .PRESSED}},
        {{.ICON_TARGET_MOVE, nil, "Move tokens tool", nil, proc(state: ^GameState) {state.active_tool = .MOVE_TOKEN}}},
    },
    {
        {{.I, .PRESSED}},
        {
            {
                nil,
                nil,
                "Toggle initiative drawing",
                nil,
                proc(state: ^GameState) {state.draw_initiative = !state.draw_initiative},
            },
        },
    },
    {
        {{.G, .PRESSED}},
        {{nil, nil, "Toggle grid drawing", nil, proc(state: ^GameState) {state.draw_grid = !state.draw_grid}}},
    },
    {
        {{.V, .RELEASED}, {.LEFT_CONTROL, .DOWN}},
        {{.ICON_FILE_SAVE, nil, "Save game", nil, proc(state: ^GameState) {state.save = .REQUESTED}}},
    },
    {
        {{.D, .PRESSED}},
        {
            {
                nil,
                nil,
                "Toggle debug info (freezes syncing, allows walking current action history)",
                nil,
                proc(state: ^GameState) {
                    if state.debug {
                        // When exiting debug mode ensure all actions are done, we don't want to get into inconsistent state
                        for state.undone > 0 {
                            a := &state.undo_history[len(state.undo_history) - state.undone]
                            if a.undo {
                                undo_action(state, tile_map, a)
                            } else {
                                redo_action(state, tile_map, a)
                            }
                            state.undone -= 1
                        }
                        state.debug = false
                    } else {
                        state.debug = true
                    }
                },
            },
        },
    },
    {{{.Z, .RELEASED}, {.LEFT_CONTROL, .DOWN}}, {{.ICON_UNDO, nil, "Undo last action", nil, proc(state: ^GameState) {
                    #reverse for &action in state.undo_history {
                        if action.mine && !action.reverted {
                            undo_action(state, tile_map, &action)
                            action.reverted = true
                            append(&state.undo_history, duplicate_action(&action))
                            undo_action: ^Action = &state.undo_history[len(state.undo_history) - 1]
                            undo_action.undo = true
                            state.needs_sync = true
                            break
                        }
                    }
                }}}},
    {{{.A, .RELEASED}, {.LEFT_CONTROL, .DOWN}}, {{.ICON_REDO, nil, "Redo all actions", nil, proc(state: ^GameState) {
                    tokens_reset(state)
                    tilemap_clear(tile_map)

                    for &action in state.undo_history {
                        redo_action(state, tile_map, &action)
                    }
                    fmt.println("redone all")
                }}}},
    {{{.LEFT_CONTROL, .PRESSED}}, {{.ICON_COLOR_PICKER, nil, "Active colorpicker", nil, proc(state: ^GameState) {
                    if state.previous_tool == nil {
                        state.previous_tool = state.active_tool
                        state.active_tool = .COLOR_PICKER
                    }}}}},
    {{{.LEFT_CONTROL, .RELEASED}}, {{nil, nil, "Deactive colorpicker", nil, proc(state: ^GameState) {
                    if state.previous_tool != nil {
                        state.active_tool = state.previous_tool.?
                        state.previous_tool = nil
                    }}}}},
    {{{.SLASH, .PRESSED}}, {{.ICON_HELP, nil, "Active help", nil, proc(state: ^GameState) {
                    if state.previous_tool == nil {
                        state.previous_tool = state.active_tool
                        state.active_tool = .HELP
                    }}}}},
    {{{.SLASH, .RELEASED}}, {{nil, nil, "Deactive help", nil, proc(state: ^GameState) {
                    if state.previous_tool != nil {
                        state.active_tool = state.previous_tool.?
                        state.previous_tool = nil
                    }}}}},
    {
        {{.O, .PRESSED}},
        {{.ICON_CURSOR_POINTER, nil, "Cone tool", nil, proc(state: ^GameState) {state.active_tool = .CONE}}},
    },
    {{{.E, .PRESSED}}, {{nil, nil, "Print all actions to console", nil, proc(state: ^GameState) {
                    for &action, index in state.undo_history {
                        fmt.println(index, ". ", action)
                    }
                }}}},
    {
        {{.J, .PRESSED}},
        {
            {
                nil,
                .MOVE_TOKEN,
                "Move selected tokens down",
                nil,
                proc(state: ^GameState) {move_selected_tokens_by_delta(state, {0, 1})},
            },
        },
    },
    {
        {{.K, .PRESSED}},
        {
            {
                nil,
                .MOVE_TOKEN,
                "Move selected tokens up",
                nil,
                proc(state: ^GameState) {move_selected_tokens_by_delta(state, {0, -1})},
            },
        },
    },
    {
        {{.H, .PRESSED}},
        {
            {
                nil,
                .MOVE_TOKEN,
                "Move selected tokens left",
                nil,
                proc(state: ^GameState) {move_selected_tokens_by_delta(state, {-1, 0})},
            },
        },
    },
    {
        {{.L, .PRESSED}},
        {
            {
                nil,
                .MOVE_TOKEN,
                "Move selected tokens right",
                are_tokens_selected,
                proc(state: ^GameState) {move_selected_tokens_by_delta(state, {1, 0})},
            },
            {
                .ICON_CURSOR_SCALE_LEFT,
                nil,
                "Light source tool",
                nil,
                proc(state: ^GameState) {state.active_tool = .LIGHT_SOURCE},
            },
        },
    },
    {
        {{.ESCAPE, .PRESSED}},
        {
            {
                nil,
                nil,
                "Deselected tokens",
                are_tokens_selected,
                proc(state: ^GameState) {clear_selected_tokens(state)},
            },
            {nil, nil, "Quit", nil, proc(state: ^GameState) {state.should_run = false}},
        },
    },
    {
        {{.TAB, .PRESSED}},
        {
            {
                nil,
                nil,
                "Select next token",
                nil,
                proc(state: ^GameState) {
                    if len(state.tokens) > 1 {
                        if len(state.selected_tokens) != 1 {
                            old_init, old_index, ok := get_token_init_pos(state, state.last_selected_token_id)
                            if ok {
                                select_next_init_token(state, old_init, old_index + 1)
                            } else {
                                // find first initiative token
                                select_next_init_token(state, 0, 0)
                            }
                        } else {
                            selected_token_id := state.selected_tokens[0]
                            old_init, old_index, ok := get_token_init_pos(state, selected_token_id)
                            assert(ok)
                            clear_selected_tokens(state)
                            select_next_init_token(state, old_init, old_index + 1)
                        }
                    }
                },
            },
        },
    },
    {
        {{.F, .PRESSED}},
        {{nil, nil, "Toggle offline state", nil, proc(state: ^GameState) {state.offline = !state.offline}}},
    },
}
