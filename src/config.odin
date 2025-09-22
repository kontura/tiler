package tiler
import "core:fmt"
import rl "vendor:raylib"

KeyAction :: enum {
    DOWN,
    RELEASED,
    PRESSED,
}

KeyTrigger :: struct {
    binding: rl.KeyboardKey,
    action:  KeyAction,
}

Config :: struct {
    icon:         rl.GuiIconName,
    key_triggers: []KeyTrigger,
    help:         string,
    action:       proc(_: ^GameState),
}

move_left :: proc(state: ^GameState) {
    state.camera_pos.rel_tile.x -= 10
}

move_right :: proc(state: ^GameState) {
    state.camera_pos.rel_tile.x += 10
}

config: []Config = {
    {.ICON_ARROW_LEFT, {{.LEFT, .DOWN}}, "Move to the left", move_left},
    {.ICON_ARROW_RIGHT, {{.RIGHT, .DOWN}}, "Move to the right", move_right},
    {.ICON_ARROW_UP, {{.UP, .PRESSED}}, "Move up", proc(state: ^GameState) {
            if state.debug {
                if state.undone > 0 {
                    redo_action(state, tile_map, &state.undo_history[len(state.undo_history) - state.undone])
                    state.undone -= 1
                }
            } else {
                state.camera_pos.rel_tile.y -= 10
            }
        }},
    {.ICON_ARROW_DOWN, {{.DOWN, .PRESSED}}, "Move down", proc(state: ^GameState) {
            if state.debug {
                if state.undone < len(state.undo_history) {
                    undo_action(state, tile_map, &state.undo_history[len(state.undo_history) - 1 - state.undone])
                    state.undone += 1
                }
            } else {
                state.camera_pos.rel_tile.y += 10
            }
        }},
    {.ICON_PENCIL, {{.P, .PRESSED}}, "Pintbrush", proc(state: ^GameState) {
            state.active_tool = .BRUSH}},
    {.ICON_BOX, {{.R, .PRESSED}}, "Rectangle tool", proc(state: ^GameState) {
            state.active_tool = .RECTANGLE}},
    {.ICON_PLAYER_RECORD, {{.C, .PRESSED}}, "Circle tool", proc(state: ^GameState) {
            state.active_tool = .CIRCLE}},
    {.ICON_BOX_GRID_BIG, {{.W, .PRESSED}}, "Wall tool", proc(state: ^GameState) {
            state.active_tool = .WALL}},
    {.ICON_PLAYER, {{.S, .PRESSED}}, "Edit tokens tool", proc(state: ^GameState) {
            state.active_tool = .EDIT_TOKEN}},
    {.ICON_LAYERS, {{.B, .PRESSED}}, "Edit background tool", proc(state: ^GameState) {
            state.active_tool = .EDIT_BG}},
    {.ICON_TARGET_MOVE, {{.M, .PRESSED}}, "Move tokens tool", proc(state: ^GameState) {
            state.active_tool = .MOVE_TOKEN}},
    {nil, {{.I, .PRESSED}}, "Toggle initiative drawing", proc(state: ^GameState) {
            state.draw_initiative = !state.draw_initiative}},
    {nil, {{.G, .PRESSED}}, "Toggle grid drawing", proc(state: ^GameState) {
            state.draw_grid = !state.draw_grid}},
    {.ICON_FILE_SAVE, {{.V, .RELEASED}, {.LEFT_CONTROL, .DOWN}}, "Save game", proc(state: ^GameState) {
            state.save = .REQUESTED}},
    {nil, {{.D, .PRESSED}}, "Toggle debug info", proc(state: ^GameState) {
            if state.debug {
                // When exiting debug mode ensure all actions are done, we don't want to get into inconsistent state
                for state.undone > 0 {
                    redo_action(state, tile_map, &state.undo_history[len(state.undo_history) - state.undone])
                    state.undone -= 1
                }
                state.debug = false
            } else {
                state.debug = true
            }
        }},
    {.ICON_UNDO, {{.Z, .RELEASED}, {.LEFT_CONTROL, .DOWN}}, "Undo last action", proc(state: ^GameState) {
            #reverse for &action in state.undo_history {
                if action.mine && !action.reverted {
                    undo_action(state, tile_map, &action)
                    action.reverted = true
                    append(&state.undo_history, action)
                    undo_action: ^Action = &state.undo_history[len(state.undo_history) - 1]
                    undo_action.undo = true
                    state.needs_sync = true
                    break
                }
            }
        }},
    {.ICON_REDO, {{.A, .RELEASED}, {.LEFT_CONTROL, .DOWN}}, "Redo all actions", proc(state: ^GameState) {
            tokens_reset(state)
            tilemap_clear(tile_map)

            for &action in state.undo_history {
                redo_action(state, tile_map, &action)
            }
            fmt.println("redone all")
        }},
    {.ICON_COLOR_PICKER, {{.LEFT_CONTROL, .PRESSED}}, "Active colorpicker", proc(state: ^GameState) {
            if state.previous_tool == nil {
                state.previous_tool = state.active_tool
                state.active_tool = .COLOR_PICKER
            }}},
    {nil, {{.LEFT_CONTROL, .RELEASED}}, "Deactive colorpicker", proc(state: ^GameState) {
            if state.previous_tool != nil {
                state.active_tool = state.previous_tool.?
                state.previous_tool = nil
            }}},
    {.ICON_HELP, {{.SLASH, .PRESSED}}, "Active help", proc(state: ^GameState) {
            if state.previous_tool == nil {
                state.previous_tool = state.active_tool
                state.active_tool = .HELP
            }}},
    {nil, {{.SLASH, .RELEASED}}, "Deactive help", proc(state: ^GameState) {
            if state.previous_tool != nil {
                state.active_tool = state.previous_tool.?
                state.previous_tool = nil
            }}},
    {.ICON_CURSOR_SCALE_LEFT, {{.L, .PRESSED}}, "Light source tool", proc(state: ^GameState) {
            state.active_tool = .LIGHT_SOURCE}},
    {.ICON_CURSOR_POINTER, {{.O, .PRESSED}}, "Cone tool", proc(state: ^GameState) {
            state.active_tool = .CONE}},
    {nil, {{.E, .PRESSED}}, "Print all actions to console", proc(state: ^GameState) {
            for &action, index in state.undo_history {
                fmt.println(index, ". ", action)
            }
        }},
}
