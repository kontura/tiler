package tiler
import "core:fmt"
import "core:math"
import "core:os"
import "core:strings"
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
        help:      string,
        condition: Maybe(proc(_: ^GameState) -> bool),
        action:    proc(_: ^GameState),
    },
}

MenuItem :: struct {
    name:   string,
    action: proc(_: ^GameState),
}

move_left :: proc(state: ^GameState) {
    state.camera_pos.rel_tile.x -= 10
}

move_right :: proc(state: ^GameState) {
    state.camera_pos.rel_tile.x += 10
}

tool_is :: proc(state: ^GameState, tool: Tool) -> bool {
    if state.active_tool == tool {
        return true
    } else {
        return false
    }
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


options_menu: []MenuItem = {{"Toggle Draw Grid", proc(state: ^GameState) {
            state.draw_grid = !state.draw_grid

        }}, {"Toggle Draw Initiative", proc(state: ^GameState) {
            state.draw_initiative = !state.draw_initiative
        }}}

main_menu: []MenuItem = {{"New Game", proc(state: ^GameState) {
            for i := len(state.undo_history) - 1; i >= 0; i -= 1 {
                action := &state.undo_history[i]
                if action.undo {
                    redo_action(state, tile_map, action)
                } else {
                    undo_action(state, tile_map, action)
                }
            }
            for i := 0; i < len(state.undo_history); i += 1 {
                delete_action(&state.undo_history[i])
            }
            clear(&state.undo_history)
            state.active_tool = .MOVE_TOKEN
        }}, {"Load Game", proc(state: ^GameState) {
            state.active_tool = .LOAD_GAME
            for &item in state.menu_items {
                delete(item)
            }
            clear(&state.menu_items)
            state.menu_items = list_files_in_dir("/persist/", context.allocator)
            state.selected_index = 0
        }}, {"Save Game", proc(state: ^GameState) {
            state.active_tool = .SAVE_GAME
            for &item in state.menu_items {
                delete(item)
            }
            clear(&state.menu_items)
            state.menu_items = list_files_in_dir("/persist/", context.allocator)
            inject_at(&state.menu_items, 0, strings.clone("<NEW SAVE>"))
            state.selected_index = 0
        }}, {"Options", proc(state: ^GameState) {
            state.active_tool = .OPTIONS_MENU
            for &item in state.menu_items {
                delete(item)
            }
            clear(&state.menu_items)
            for &item in options_menu {
                append(&state.menu_items, strings.clone(item.name))
            }
            state.selected_index = 0
        }}, {"Quit Game", proc(state: ^GameState) {
            os.exit(0)
        }}}

config: []Config = {
    {key_triggers = {{.LEFT, .PRESSED}}, bindings = {{.ICON_ARROW_LEFT, "Move to the left", nil, move_left}}},
    {{{.RIGHT, .PRESSED}}, {{.ICON_ARROW_RIGHT, "Move to the right", nil, move_right}}},
    {
        key_triggers = {{.UP, .PRESSED}},
        bindings     = {
            {
                .ICON_ARROW_UP,
                "Select previous",
                proc(state: ^GameState) -> bool {return(
                        tool_is(state, .LOAD_GAME) ||
                        tool_is(state, .MAIN_MENU) ||
                        tool_is(state, .SAVE_GAME) ||
                        tool_is(state, .OPTIONS_MENU) \
                    )},
                proc(state: ^GameState) {
                    state.selected_index -= 1
                    state.selected_index = math.max(state.selected_index, 0)
                },
            },
            {
                .ICON_ARROW_UP,
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
    {
        key_triggers = {{.DOWN, .PRESSED}},
        bindings = {
            {
                .ICON_ARROW_DOWN,
                "Select next",
                proc(state: ^GameState) -> bool {return(
                        tool_is(state, .LOAD_GAME) ||
                        tool_is(state, .MAIN_MENU) ||
                        tool_is(state, .SAVE_GAME) ||
                        tool_is(state, .OPTIONS_MENU) \
                    )},
                proc(state: ^GameState) {
                    state.selected_index += 1
                    state.selected_index = math.min(state.selected_index, len(state.menu_items) - 1)
                },
            },
            {.ICON_ARROW_DOWN, "Move down", nil, proc(state: ^GameState) {
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
                }},
        },
    },
    {{{.P, .PRESSED}}, {{.ICON_PENCIL, "Pintbrush", nil, proc(state: ^GameState) {state.active_tool = .BRUSH}}}},
    {{{.R, .PRESSED}}, {{.ICON_BOX, "Rectangle tool", nil, proc(state: ^GameState) {state.active_tool = .RECTANGLE}}}},
    {
        {{.C, .PRESSED}},
        {{.ICON_PLAYER_RECORD, "Circle tool", nil, proc(state: ^GameState) {state.active_tool = .CIRCLE}}},
    },
    {{{.W, .PRESSED}}, {{.ICON_BOX_GRID_BIG, "Wall tool", nil, proc(state: ^GameState) {state.active_tool = .WALL}}}},
    {
        {{.S, .PRESSED}},
        {{.ICON_PLAYER, "Edit tokens tool", nil, proc(state: ^GameState) {state.active_tool = .EDIT_TOKEN}}},
    },
    {
        {{.B, .PRESSED}},
        {{.ICON_LAYERS, "Edit background tool", nil, proc(state: ^GameState) {state.active_tool = .EDIT_BG}}},
    },
    {
        {{.M, .PRESSED}},
        {{.ICON_TARGET_MOVE, "Move tokens tool", nil, proc(state: ^GameState) {state.active_tool = .MOVE_TOKEN}}},
    },
    {
        {{.V, .RELEASED}, {.LEFT_CONTROL, .DOWN}},
        {
            {
                .ICON_FILE_SAVE,
                "Quick save",
                nil,
                proc(state: ^GameState) {
                    //TODO(amatej): generate with timestamp
                    store_save(state, "/persist/tiler_save")
                    state.timeout = 60
                },
            },
        },
    },
    {
        {{.D, .PRESSED}},
        {
            {
                nil,
                "Toggle debug info (allows walking current action history)",
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
    {{{.Z, .RELEASED}, {.LEFT_CONTROL, .DOWN}}, {{.ICON_UNDO, "Undo last action", nil, proc(state: ^GameState) {
                    #reverse for &action in state.undo_history {
                        if action.mine && !action.reverted {
                            undo_action(state, tile_map, &action)
                            action.reverted = true
                            append(&state.undo_history, duplicate_action(&action))
                            undo_action: ^Action = &state.undo_history[len(state.undo_history) - 1]
                            undo_action.undo = true
                            finish_last_undo_history_action(state)
                            state.needs_sync = true
                            break
                        }
                    }
                }}}},
    {{{.A, .RELEASED}, {.LEFT_CONTROL, .DOWN}}, {{.ICON_REDO, "Redo all actions", nil, proc(state: ^GameState) {
                    tokens_reset(state)
                    tilemap_clear(tile_map)

                    for &action in state.undo_history {
                        if action.undo {
                            undo_action(state, tile_map, &action)
                        } else {
                            redo_action(state, tile_map, &action)
                        }
                    }
                    fmt.println("redone all")
                }}}},
    {{{.LEFT_CONTROL, .PRESSED}}, {{.ICON_COLOR_PICKER, "Active colorpicker", nil, proc(state: ^GameState) {
                    if state.previous_tool == nil {
                        state.previous_tool = state.active_tool
                        state.active_tool = .COLOR_PICKER
                    }}}}},
    {{{.LEFT_CONTROL, .RELEASED}}, {{nil, "Deactive colorpicker", nil, proc(state: ^GameState) {
                    if state.previous_tool != nil {
                        state.active_tool = state.previous_tool.?
                        state.previous_tool = nil
                    }}}}},
    {{{.SLASH, .PRESSED}}, {{.ICON_HELP, "Active help", nil, proc(state: ^GameState) {
                    if state.previous_tool == nil {
                        state.previous_tool = state.active_tool
                        state.active_tool = .HELP
                    }}}}},
    {{{.SLASH, .RELEASED}}, {{nil, "Deactive help", nil, proc(state: ^GameState) {
                    if state.previous_tool != nil {
                        state.active_tool = state.previous_tool.?
                        state.previous_tool = nil
                    }}}}},
    {
        {{.O, .PRESSED}},
        {{.ICON_CURSOR_POINTER, "Cone tool", nil, proc(state: ^GameState) {state.active_tool = .CONE}}},
    },
    {{{.E, .PRESSED}}, {{nil, "Print all actions to console", nil, proc(state: ^GameState) {
                    for &action, index in state.undo_history {
                        fmt.println(index, ". ", action)
                    }
                }}}},
    {
        {{.J, .PRESSED}},
        {
            {
                nil,
                "Move selected tokens down",
                proc(state: ^GameState) -> bool {return tool_is(state, .MOVE_TOKEN)},
                proc(state: ^GameState) {move_selected_tokens_by_delta(state, {0, 1})},
            },
        },
    },
    {
        {{.K, .PRESSED}},
        {
            {
                nil,
                "Move selected tokens up",
                proc(state: ^GameState) -> bool {return tool_is(state, .MOVE_TOKEN)},
                proc(state: ^GameState) {move_selected_tokens_by_delta(state, {0, -1})},
            },
        },
    },
    {
        {{.H, .PRESSED}},
        {
            {
                nil,
                "Move selected tokens left",
                proc(state: ^GameState) -> bool {return tool_is(state, .MOVE_TOKEN)},
                proc(state: ^GameState) {move_selected_tokens_by_delta(state, {-1, 0})},
            },
        },
    },
    {
        {{.L, .PRESSED}},
        {
            {
                nil,
                "Move selected tokens right",
                proc(state: ^GameState) -> bool {return tool_is(state, .MOVE_TOKEN)},
                proc(state: ^GameState) {move_selected_tokens_by_delta(state, {1, 0})},
            },
            {
                .ICON_CURSOR_SCALE_LEFT,
                "Light source tool",
                nil,
                proc(state: ^GameState) {state.active_tool = .LIGHT_SOURCE},
            },
        },
    },
    {
        {{.ESCAPE, .PRESSED}},
        {
            {nil, "Deselected tokens", are_tokens_selected, proc(state: ^GameState) {clear_selected_tokens(state)}},
            {nil, "Main Menu", nil, proc(state: ^GameState) {
                    if state.active_tool == .MAIN_MENU {
                        state.active_tool = state.previous_tool.?
                    } else {
                        if !(state.active_tool == .OPTIONS_MENU ||
                               state.active_tool == .SAVE_GAME ||
                               state.active_tool == .NEW_SAVE_GAME ||
                               state.active_tool == .LOAD_GAME) {
                            state.previous_tool = state.active_tool
                        }
                        state.active_tool = .MAIN_MENU
                        for &item in state.menu_items {
                            delete(item)
                        }
                        clear(&state.menu_items)
                        for &item in main_menu {
                            append(&state.menu_items, strings.clone(item.name))
                        }
                    }
                }},
        },
    },
    {
        {{.TAB, .PRESSED}},
        {
            {
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
    {{{.F, .PRESSED}}, {{nil, "Toggle offline state", nil, proc(state: ^GameState) {state.offline = !state.offline}}}},
    {{{.ENTER, .PRESSED}}, {{nil, "Confirm", nil, proc(state: ^GameState) {
                    #partial switch state.active_tool {
                    case .LOAD_GAME:
                        {
                            save_name := fmt.aprint(
                                "/persist/",
                                state.menu_items[state.selected_index],
                                sep = "",
                                allocator = context.temp_allocator,
                            )
                            if load_save_override(state, save_name) {
                                state.active_tool = state.previous_tool.?
                            }
                        }
                    case .SAVE_GAME:
                        {
                            if state.selected_index == 0 {
                                state.active_tool = .NEW_SAVE_GAME
                                delete(state.menu_items[0])
                                state.menu_items[0] = strings.clone("")
                            } else {
                                save_name := fmt.aprint(
                                    "/persist/",
                                    state.menu_items[state.selected_index],
                                    sep = "",
                                    allocator = context.temp_allocator,
                                )
                                if store_save(state, save_name) {
                                    state.active_tool = state.previous_tool.?
                                    state.timeout = 60
                                }
                            }
                        }
                    case .NEW_SAVE_GAME:
                        {
                            save_name := fmt.aprint(
                                "/persist/",
                                state.menu_items[0],
                                sep = "",
                                allocator = context.temp_allocator,
                            )
                            if store_save(state, save_name) {
                                state.active_tool = state.previous_tool.?
                                state.timeout = 60
                            }
                        }
                    case .MAIN_MENU:
                        {
                            main_menu[state.selected_index].action(state)
                        }
                    case .OPTIONS_MENU:
                        {
                            options_menu[state.selected_index].action(state)
                        }
                    }
                }}}},
}
