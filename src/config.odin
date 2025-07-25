package tiler
import rl "vendor:raylib"

KeyAction :: enum {
    DOWN,
    RELEASED,
    PRESSED,
}

KeyTrigger :: struct {
    binding: rl.KeyboardKey,
    action: KeyAction,
}

Config :: struct {
    icon: rl.GuiIconName,
    key_triggers: []KeyTrigger,
    help: string,
    action: proc(^GameState),
}

move_left :: proc(state: ^GameState) {
    state.camera_pos.rel_tile.x -= 10
}

move_right :: proc(state: ^GameState) {
    state.camera_pos.rel_tile.x += 10
}

move_up :: proc(state: ^GameState) {
    state.camera_pos.rel_tile.y -= 10
}

move_down :: proc(state: ^GameState) {
    state.camera_pos.rel_tile.y += 10
}

config : []Config = {
    {.ICON_ARROW_LEFT, {{.LEFT, .DOWN}}, "Move to the left", move_left},
    {.ICON_ARROW_RIGHT, {{.RIGHT, .DOWN}}, "Move to the right", move_right},
    {.ICON_ARROW_UP, {{.UP, .DOWN}}, "Move up", move_up},
    {.ICON_ARROW_DOWN, {{.DOWN, .DOWN}}, "Move down", move_down},
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
        state.debug = !state.debug}},
    {.ICON_UNDO, {{.Z, .RELEASED}, {.LEFT_CONTROL, .DOWN}}, "Undo last action", proc(state: ^GameState) {
        #reverse for &action in state.undo_history {
            if action.mine && !action.reverted {
                undo_action(state, tile_map, &action)
                action.reverted = true
                append(&state.undo_history, action)
                undo_action : ^Action = &state.undo_history[len(state.undo_history)-1]
                undo_action.undo = true
                state.needs_sync = true
                break
            }
        }
        }},
    {.ICON_REDO, {{.A, .RELEASED}, {.LEFT_CONTROL, .DOWN}}, "Redo all actions", proc(state: ^GameState) {
        clear(&state.tokens)
        for _, &token_ids in state.initiative_to_tokens {
            clear(&token_ids)
        }
        clear(&state.initiative_to_tokens)
        for key, &arr in tile_map.tile_chunks {
            clear(&arr.tiles)
        }
        clear(&tile_map.tile_chunks)
        for &action in state.undo_history {
            redo_action(state, tile_map, &action)
        }
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
}
