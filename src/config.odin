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
    {.ICON_TARGET_MOVE, {{.M, .PRESSED}}, "Move tokens tool", proc(state: ^GameState) {
        state.active_tool = .MOVE_TOKEN}},
    {nil, {{.I, .PRESSED}}, "Toggle initiative drawing", proc(state: ^GameState) {
        state.draw_initiative = !state.draw_initiative}},
    {nil, {{.G, .PRESSED}}, "Toggle grid drawing", proc(state: ^GameState) {
        state.draw_grid = !state.draw_grid}},
    {.ICON_UNDO, {{.Z, .RELEASED}, {.LEFT_CONTROL, .DOWN}}, "Undo last action", proc(state: ^GameState) {
        if len(state.undo_history) > 0 {
            action : ^Action = &state.undo_history[len(state.undo_history)-1]
            undo_action(state, tile_map, action)
            pop_last_action(state, tile_map, &state.undo_history)
        }}},
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
    {.ICON_HELP, {{.RIGHT_SHIFT, .DOWN}, {.SLASH, .PRESSED}}, "Active help", proc(state: ^GameState) {
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
