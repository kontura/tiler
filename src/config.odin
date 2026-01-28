package tiler
import "core:fmt"
import "core:math"
import "core:os"
import "core:strings"
import "core:time"
import rl "vendor:raylib"

KeyAction :: enum {
    DOWN,
    RELEASED,
    PRESSED,
}

ToolConfig :: struct {
    icon:      rl.GuiIconName,
    help:      string,
    condition: Maybe(proc(_: ^GameState) -> bool),
    is_active: Maybe(proc(_: ^GameState) -> bool),
    action:    proc(_: ^GameState),
    options:   []ToolConfig,
}

Config :: struct {
    key_triggers: []struct {
        binding: rl.KeyboardKey,
        action:  KeyAction,
    },
    // The order of bindings matter we execute only the first tool matching binding
    bindings:     []ToolConfig,
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

toggle_tool_option :: proc(state: ^GameState, tool_option: ToolOtions) {
    if tool_option in state.selected_options {
        state.selected_options -= {tool_option}
    } else {
        state.selected_options += {tool_option}
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


options_menu: []MenuItem = {
    {
        "Toggle Draw Grid", proc(state: ^GameState) {
            state.draw_grid = !state.draw_grid
        },
    },
    {
        "Toggle Draw Initiative", proc(state: ^GameState) {
            state.draw_initiative = !state.draw_initiative
        },
    },
    {
        "Toggle Draw grid mask", proc(state: ^GameState) {
            state.draw_grid_mask = !state.draw_grid_mask
        },
    },
}

main_menu: []MenuItem = {{"New Game", proc(state: ^GameState) {
            tilemap_delete(tile_map)
            tokens_reset(state)
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
            state.menu_items = list_files_in_dir(state.save_location, context.allocator)
            state.selected_index = 0
        }}, {"Save Game", proc(state: ^GameState) {
            state.active_tool = .SAVE_GAME
            for &item in state.menu_items {
                delete(item)
            }
            clear(&state.menu_items)
            state.menu_items = list_files_in_dir(state.save_location, context.allocator)
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
            state.should_run = false
        }}}


cone_tool_config: ToolConfig = {
    .ICON_CURSOR_POINTER,
    "Cone tool",
    nil,
    proc(state: ^GameState) -> bool {return state.active_tool == .CONE},
    proc(state: ^GameState) {state.active_tool = .CONE},
    {},
}
paintbrush_tool_config: ToolConfig = {
    .ICON_PENCIL,
    "Pintbrush",
    nil,
    proc(state: ^GameState) -> bool {return state.active_tool == .BRUSH},
    proc(state: ^GameState) {state.active_tool = .BRUSH},
    {},
}
rectangle_tool_config: ToolConfig = {
    .ICON_BOX,
    "Rectangle tool",
    nil,
    proc(state: ^GameState) -> bool {return state.active_tool == .RECTANGLE},
    proc(state: ^GameState) {state.active_tool = .RECTANGLE},
    {
        {
            .ICON_BOX_GRID_BIG,
            "Surround with walls",
            proc(state: ^GameState) -> bool {return state.active_tool == .RECTANGLE || state.active_tool == .CIRCLE},
            proc(state: ^GameState) -> bool {return .ADD_WALLS in state.selected_options},
            proc(state: ^GameState) {toggle_tool_option(state, .ADD_WALLS)},
            {},
        },
        {
            .ICON_DITHERING,
            "Color dithering",
            proc(state: ^GameState) -> bool {return state.active_tool == .RECTANGLE || state.active_tool == .CIRCLE},
            proc(state: ^GameState) -> bool {return .DITHERING in state.selected_options},
            proc(state: ^GameState) {toggle_tool_option(state, .DITHERING)},
            {},
        },
    },
}
circle_tool_config: ToolConfig = {
    .ICON_PLAYER_RECORD,
    "Circle tool",
    nil,
    proc(state: ^GameState) -> bool {return state.active_tool == .CIRCLE},
    proc(state: ^GameState) {state.active_tool = .CIRCLE},
    {},
}
wall_tool_config: ToolConfig = {
    .ICON_BOX_GRID_BIG,
    "Wall tool",
    nil,
    proc(state: ^GameState) -> bool {return state.active_tool == .WALL},
    proc(state: ^GameState) {state.active_tool = .WALL},
    {},
}
edit_token_tool_config: ToolConfig = {
    .ICON_PLAYER,
    "Edit tokens tool",
    nil,
    proc(state: ^GameState) -> bool {return state.active_tool == .EDIT_TOKEN},
    proc(state: ^GameState) {state.active_tool = .EDIT_TOKEN},
    {},
}
edit_bg_tool_config: ToolConfig = {
    .ICON_LAYERS,
    "Edit background tool",
    nil,
    proc(state: ^GameState) -> bool {return state.active_tool == .EDIT_BG},
    proc(state: ^GameState) {state.active_tool = .EDIT_BG},
    {},
}
move_token_tool_config: ToolConfig = {
    .ICON_TARGET_MOVE,
    "Move tokens tool",
    nil,
    proc(state: ^GameState) -> bool {return state.active_tool == .MOVE_TOKEN},
    proc(state: ^GameState) {state.active_tool = .MOVE_TOKEN},
    {},
}

config_tool_menu: []ToolConfig = {
    move_token_tool_config,
    rectangle_tool_config,
    circle_tool_config,
    cone_tool_config,
    paintbrush_tool_config,
    wall_tool_config,
    edit_token_tool_config,
}

get_tool_tool_menu_rect :: proc(
    state: ^GameState,
    tool_menu: ^[]ToolConfig,
    index: int,
    option_index := -1,
) -> [4]f32 {
    offset := 250 + 32 * index
    return {f32(int(state.screen_width) - 30 - 32 * (option_index + 1)), f32(offset), 30, 30}
}

config: []Config = {
    {key_triggers = {{.LEFT, .PRESSED}}, bindings = {{.ICON_ARROW_LEFT, "Move to the left", nil, nil, move_left, {}}}},
    {{{.RIGHT, .PRESSED}}, {{.ICON_ARROW_RIGHT, "Move to the right", nil, nil, move_right, {}}}},
    {
        key_triggers = {{.UP, .PRESSED}},
        bindings = {
            {
                .ICON_ARROW_UP,
                "Select previous",
                proc(state: ^GameState) -> bool {return(
                        tool_is(state, .LOAD_GAME) ||
                        tool_is(state, .MAIN_MENU) ||
                        tool_is(state, .SAVE_GAME) ||
                        tool_is(state, .OPTIONS_MENU) \
                    )},
                nil,
                proc(state: ^GameState) {
                    state.selected_index -= 1
                    state.selected_index = math.max(state.selected_index, 0)
                },
                {},
            },
            {.ICON_ARROW_UP, "Move up", nil, nil, proc(state: ^GameState) {
                    if state.debug == .ACTIONS {
                        if state.undone > 0 {
                            a := &state.undo_history[len(state.undo_history) - state.undone]
                            redo_action(state, tile_map, a)
                            state.undone -= 1
                        }
                    } else {
                        state.camera_pos.rel_tile.y -= 10
                    }
                }, {}},
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
                nil,
                proc(state: ^GameState) {
                    state.selected_index += 1
                    state.selected_index = math.min(state.selected_index, len(state.menu_items) - 1)
                },
                {},
            },
            {.ICON_ARROW_DOWN, "Move down", nil, nil, proc(state: ^GameState) {
                    if state.debug == .ACTIONS {
                        if state.undone < len(state.undo_history) {
                            a := &state.undo_history[len(state.undo_history) - 1 - state.undone]
                            undo_action(state, tile_map, a)
                            state.undone += 1
                        }
                    } else {
                        state.camera_pos.rel_tile.y += 10
                    }
                }, {}},
        },
    },
    {{{.P, .PRESSED}}, {paintbrush_tool_config}},
    {{{.R, .PRESSED}}, {rectangle_tool_config}},
    {{{.C, .PRESSED}}, {circle_tool_config}},
    {{{.W, .PRESSED}}, {wall_tool_config}},
    {{{.S, .PRESSED}}, {edit_token_tool_config}},
    {{{.B, .PRESSED}}, {edit_bg_tool_config}},
    {{{.M, .PRESSED}}, {move_token_tool_config}},
    {{{.F5, .RELEASED}}, {{.ICON_FILE_SAVE, "Quick save", nil, nil, proc(state: ^GameState) {
                    builder := strings.builder_make(context.temp_allocator)
                    strings.write_string(&builder, state.save_location)
                    strings.write_string(&builder, "autosave-")
                    s, _ := time.time_to_rfc3339(time.now(), 0, false, context.temp_allocator)
                    strings.write_string(&builder, s)
                    if store_save(state, strings.to_string(builder)) {
                        show_message(state, "Saved!", 60)
                    } else {
                        show_message(state, "Saving failed!", 60)
                    }
                }, {}}}},
    {
        {{.D, .PRESSED}},
        {
            {
                nil,
                "Toggle debug info (allows walking current action history)",
                nil,
                nil,
                proc(state: ^GameState) {
                    switch state.debug {
                    case .OFF:
                        {
                            state.debug = .ACTIONS
                        }
                    case .ACTIONS:
                        {
                            // When exiting debug mode ensure all actions are done, we don't want to get into inconsistent state
                            for state.undone > 0 {
                                a := &state.undo_history[len(state.undo_history) - state.undone]
                                redo_action(state, tile_map, a)
                                state.undone -= 1
                            }
                            state.debug = .TOKENS
                        }
                    case .TOKENS:
                        {
                            state.debug = .PERF
                        }
                    case .PERF:
                        {
                            state.debug = .OFF
                        }

                    }
                },
                {},
            },
        },
    },
    {{{.Z, .RELEASED}, {.LEFT_CONTROL, .DOWN}}, {{.ICON_UNDO, "Undo last action", nil, nil, proc(state: ^GameState) {

                    //TODO(amatej): This needs to be fixed/updated for canceled actions.
                    //              Do I need tests to do it properly?
                    #reverse for &action in state.undo_history {
                        if action.mine && action.state != .REVERTED && action.state != .REVERTS {
                            reverted := revert_action(&action)
                            redo_action(state, tile_map, &reverted)
                            reverted.linked_action_authors_index = i64(action.authors_index) * -1
                            action.state = .REVERTED
                            append(&state.undo_history, reverted)
                            finish_last_undo_history_action(state, .REVERTS)
                            state.needs_sync = true
                            if !action.revert_prev {
                                break
                            }
                        }
                    }
                }, {}}}},
    {{{.A, .RELEASED}, {.LEFT_CONTROL, .DOWN}}, {{.ICON_REDO, "Redo all actions", nil, nil, proc(state: ^GameState) {
                    tokens_reset(state)
                    tilemap_delete(tile_map)

                    if state.debug == .ACTIONS {
                        state.undone = len(state.undo_history)
                        fmt.println("you have to redo manually (arrow up)")
                    } else {
                        for &action in state.undo_history {
                            redo_action(state, tile_map, &action)
                        }
                        fmt.println("redone all")
                    }
                }, {}}}},
    {{{.LEFT_CONTROL, .PRESSED}}, {{.ICON_COLOR_PICKER, "Active colorpicker", nil, nil, proc(state: ^GameState) {
                    if state.previous_tool == nil && len(state.selected_tokens) == 0 {
                        state.previous_tool = state.active_tool
                        state.active_tool = .COLOR_PICKER
                    }}, {}}}},
    {{{.LEFT_CONTROL, .RELEASED}}, {{nil, "Deactive colorpicker", nil, nil, proc(state: ^GameState) {
                    if state.previous_tool != nil {
                        state.active_tool = state.previous_tool.?
                        state.previous_tool = nil
                    }}, {}}}},
    {{{.SLASH, .PRESSED}}, {{.ICON_HELP, "Active help", nil, nil, proc(state: ^GameState) {
                    if state.previous_tool == nil {
                        state.previous_tool = state.active_tool
                        state.active_tool = .HELP
                    }}, {}}}},
    {{{.SLASH, .RELEASED}}, {{nil, "Deactive help", nil, nil, proc(state: ^GameState) {
                    if state.previous_tool != nil {
                        state.active_tool = state.previous_tool.?
                        state.previous_tool = nil
                    }}, {}}}},
    {{{.O, .PRESSED}}, {cone_tool_config}},
    {{{.E, .PRESSED}}, {{nil, "Print all actions to console", nil, nil, proc(state: ^GameState) {
                    for &action, index in state.undo_history {
                        fmt.println(index, ". ", action)
                    }
                    fmt.println("Known textures:")
                    for name, _ in state.textures {
                        fmt.println(name)
                    }
                }, {}}}},
    {
        {{.J, .PRESSED}},
        {
            {
                nil,
                "Move selected tokens down",
                proc(state: ^GameState) -> bool {return tool_is(state, .MOVE_TOKEN)},
                nil,
                proc(state: ^GameState) {move_selected_tokens_by_delta(state, {0, 1})},
                {},
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
                nil,
                proc(state: ^GameState) {move_selected_tokens_by_delta(state, {0, -1})},
                {},
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
                nil,
                proc(state: ^GameState) {move_selected_tokens_by_delta(state, {-1, 0})},
                {},
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
                nil,
                proc(state: ^GameState) {move_selected_tokens_by_delta(state, {1, 0})},
                {},
            },
            {
                .ICON_CURSOR_SCALE_LEFT,
                "Light source tool",
                nil,
                nil,
                proc(state: ^GameState) {state.active_tool = .LIGHT_SOURCE},
                {},
            },
        },
    },
    {
        {{.ESCAPE, .PRESSED}},
        {
            {
                nil,
                "Deselected tokens",
                are_tokens_selected,
                nil,
                proc(state: ^GameState) {clear_selected_tokens(state)},
                {},
            },
            {nil, "Main Menu", nil, nil, proc(state: ^GameState) {
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
                }, {}},
        },
    },
    {
        {{.TAB, .PRESSED}},
        {
            {
                nil,
                "Select next token",
                nil,
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
                {},
            },
        },
    },
    {
        {{.F, .PRESSED}},
        {{nil, "Toggle offline state", nil, nil, proc(state: ^GameState) {state.offline = !state.offline}, {}}},
    },
    {{{.ENTER, .PRESSED}}, {{nil, "Confirm", nil, nil, proc(state: ^GameState) {
                    #partial switch state.active_tool {
                    case .LOAD_GAME:
                        {
                            save_name := fmt.aprint(
                                state.save_location,
                                state.menu_items[state.selected_index],
                                sep = "",
                                allocator = context.temp_allocator,
                            )
                            if load_save_override(state, tile_map, save_name) {
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
                                    state.save_location,
                                    state.menu_items[state.selected_index],
                                    sep = "",
                                    allocator = context.temp_allocator,
                                )
                                if store_save(state, save_name) {
                                    state.active_tool = state.previous_tool.?
                                    show_message(state, "Saved!", 60)
                                }
                            }
                        }
                    case .NEW_SAVE_GAME:
                        {
                            save_name := fmt.aprint(
                                state.save_location,
                                state.menu_items[0],
                                sep = "",
                                allocator = context.temp_allocator,
                            )
                            if store_save(state, save_name) {
                                state.active_tool = state.previous_tool.?
                                show_message(state, "Saved!", 60)
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
                    case:
                        {
                            if state.debug == .ACTIONS {
                                dropping_msg := fmt.aprint(
                                    "Dropping: ",
                                    state.undone,
                                    " actions!",
                                    sep = "",
                                    allocator = context.temp_allocator,
                                )
                                show_message(state, dropping_msg, 60)
                                for state.undone > 0 {
                                    removed_action := pop(&state.undo_history)
                                    delete_action(&removed_action)
                                    state.undone -= 1
                                }
                            }
                        }
                    }
                }, {}}}},
}
