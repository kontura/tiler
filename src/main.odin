package tiler

import "core:fmt"
import "core:math"
import "core:math/rand"
import "core:mem"
import "core:slice"
import "core:strings"
import "core:time"

import rl "vendor:raylib"

INIT_SCREEN_WIDTH: i32 : 1280
INIT_SCREEN_HEIGHT: i32 : 720

BUILDER_FAILED :: "Builder failed"
EMPTY_COLOR: [4]u8 : {77, 77, 77, 255}
TRANSPARENT_COLOR: [4]u8 : {0, 0, 0, 0}
SELECTED_COLOR: [4]u8 : {0, 255, 0, 255}
SELECTED_TRANSPARENT_COLOR: [4]u8 : {0, 255, 0, 180}

INITIATIVE_COUNT: i32 : 50

SaveStatus :: enum {
    NONE,
    REQUESTED,
    DONE,
}

//TODO(amatej): make GameState and TileMap not global
GameState :: struct {
    screen_width:           i32,
    screen_height:          i32,
    camera_pos:             TileMapPosition,
    selected_color:         [4]u8,
    selected_alpha:         f32,
    selected_tokens:        [dynamic]u64,
    last_selected_token_id: u64,
    draw_grid:              bool,
    draw_initiative:        bool,
    active_tool:            Tool,
    previous_tool:          Maybe(Tool),
    tool_start_position:    Maybe([2]f32),
    temp_actions:           [dynamic]Action,
    key_consumed:           bool,
    needs_sync:             bool,
    mobile:                 bool,
    previous_touch_dist:    f32,
    previous_touch_pos:     [2]f32,
    previous_touch_count:   i32,
    save:                   SaveStatus,
    bytes_count:            uint,
    timeout:                uint,
    //TODO(amatej): debug should be a tool
    debug:                  bool,
    should_run:             bool,
    undone:                 int,
    light_source:           [2]f32,
    shadow_color:           [4]u8,
    bg:                     rl.Texture2D,
    bg_pos:                 TileMapPosition,
    bg_scale:               f32,

    // permanent state
    textures:               map[string]rl.Texture2D,
    gui_rectangles:         map[Widget]rl.Rectangle,

    //TODO(amatej): check if the tool actually does any color change before recoding
    //              undoing non-color changes does nothing
    undo_history:           [dynamic]Action,
    tokens:                 map[u64]Token,
    initiative_to_tokens:   map[i32][dynamic]u64,
}

Widget :: enum {
    MAP,
    COLORPICKER,
    COLORBARHUE,
    COLORBARALPHA,
    INITIATIVE,
}

draw_quad :: proc(v1, v2, v3, v4: [2]f32, color: [4]u8) {
    area := (v2.x - v1.x) * (v3.y - v1.y) - (v3.x - v1.x) * (v2.y - v1.y)
    if area > 0 {
        rl.DrawTriangle(v3, v2, v1, color.xyzw)
    } else {
        rl.DrawTriangle(v3, v1, v2, color.xyzw)
    }

    area = (v3.x - v2.x) * (v4.y - v2.y) - (v4.x - v2.x) * (v3.y - v2.y)
    if area > 0 {
        rl.DrawTriangle(v2, v4, v3, color.xyzw)
    } else {
        rl.DrawTriangle(v2, v3, v4, color.xyzw)
    }
}


u64_to_cstring :: proc(num: u64) -> cstring {
    builder := strings.builder_make(context.temp_allocator)
    strings.write_u64(&builder, num)
    return strings.to_cstring(&builder) or_else BUILDER_FAILED
}

screen_coord_to_tile_map :: proc(pos: rl.Vector2, state: ^GameState, tile_map: ^TileMap) -> TileMapPosition {
    res: TileMapPosition = state.camera_pos

    delta: rl.Vector2 = pos

    screen_center: rl.Vector2 = {f32(state.screen_width), f32(state.screen_height)} * 0.5
    delta -= screen_center

    res.rel_tile.x += delta.x * f32(tile_map.pixels_to_feet)
    res.rel_tile.y += delta.y * f32(tile_map.pixels_to_feet)

    res = recanonicalize_position(tile_map, res)

    return res
}

find_token_at_screen :: proc(tile_map: ^TileMap, state: ^GameState, pos: rl.Vector2) -> ^Token {
    closest_token: ^Token = nil
    closest_dist := f32(tile_map.tile_side_in_pixels * 2)
    for _, &token in state.tokens {
        if token.alive {
            center, _ := get_token_circle(tile_map, state, token)
            dist := dist(pos, center)
            if dist < closest_dist {
                closest_token = &token
                closest_dist = dist
            }
        }
    }

    return closest_token
}

// Snaps to grid (ignores rel_tile part)
tile_map_to_screen_coord :: proc(pos: TileMapPosition, state: ^GameState, tile_map: ^TileMap) -> rl.Vector2 {
    res: rl.Vector2 = {f32(state.screen_width), f32(state.screen_height)} * 0.5

    delta: [2]i32 = {i32(pos.abs_tile.x), i32(pos.abs_tile.y)}
    delta -= {i32(state.camera_pos.abs_tile.x), i32(state.camera_pos.abs_tile.y)}

    res.x += f32(delta.x * tile_map.tile_side_in_pixels)
    res.y += f32(delta.y * tile_map.tile_side_in_pixels)

    res -= state.camera_pos.rel_tile * tile_map.feet_to_pixels

    return res
}

tile_map_to_screen_coord_full :: proc(pos: TileMapPosition, state: ^GameState, tile_map: ^TileMap) -> rl.Vector2 {
    res: rl.Vector2 = {f32(state.screen_width), f32(state.screen_height)} * 0.5

    delta: [2]i32 = {i32(pos.abs_tile.x), i32(pos.abs_tile.y)}
    delta -= {i32(state.camera_pos.abs_tile.x), i32(state.camera_pos.abs_tile.y)}

    res.x += f32(delta.x * tile_map.tile_side_in_pixels)
    res.y += f32(delta.y * tile_map.tile_side_in_pixels)

    res -= state.camera_pos.rel_tile * tile_map.feet_to_pixels

    res += pos.rel_tile * tile_map.feet_to_pixels

    return res
}

state: ^GameState
tile_map: ^TileMap


add_background :: proc(data: [^]u8, width: i32, height: i32) {
    d := data[:width * height]
    fmt.println(d)
    image: rl.Image
    image.data = data
    image.width = width
    image.height = height
    image.mipmaps = 1
    image.format = .UNCOMPRESSED_R8G8B8A8 // or appropriate format
    fmt.println(image)
    state.bg = rl.LoadTextureFromImage(image)
}

game_state_init :: proc(state: ^GameState, mobile: bool, width: i32, height: i32) {
    state.camera_pos.abs_tile.x = 100
    state.camera_pos.abs_tile.y = 100
    state.camera_pos.rel_tile.x = 0.0
    state.camera_pos.rel_tile.y = 0.0
    state.screen_height = height
    state.screen_width = width
    state.draw_grid = true
    state.draw_initiative = true
    state.active_tool = Tool.MOVE_TOKEN
    state.selected_color.a = 255
    rand.reset(u64(time.time_to_unix(time.now())))
    state.selected_color.r = u8(rand.int_max(255))
    state.selected_color.g = u8(rand.int_max(255))
    state.selected_color.b = u8(rand.int_max(255))
    state.selected_alpha = 1
    state.needs_sync = true
    state.debug = true
    state.mobile = mobile
    state.bg_scale = 1
    state.should_run = true
    state.light_source = {0.06, 0.09}
    state.shadow_color = {0, 0, 0, 65}
    // Token 0 is reserved, it is a temp token used for previews
    state.tokens[0] = Token {
        id   = 0,
        name = strings.clone(" "),
        size = 1,
    }
}

tile_map_init :: proc(tile_map: ^TileMap, mobile: bool) {
    tile_map.chunk_shift = 8
    tile_map.chunk_mask = (1 << tile_map.chunk_shift) - 1
    tile_map.chunk_dim = (1 << tile_map.chunk_shift)
    tile_map.tile_side_in_feet = 5
    if mobile {
        tile_map.tile_side_in_pixels = 80
    } else {
        tile_map.tile_side_in_pixels = 30
    }
    tile_map.feet_to_pixels = f32(tile_map.tile_side_in_pixels) / tile_map.tile_side_in_feet
    tile_map.pixels_to_feet = tile_map.tile_side_in_feet / f32(tile_map.tile_side_in_pixels)
}

init :: proc(mobile := false) {
    rl.SetConfigFlags({.WINDOW_RESIZABLE, .VSYNC_HINT})
    rl.InitWindow(INIT_SCREEN_WIDTH, INIT_SCREEN_HEIGHT, "Tiler")

    state = new(GameState)
    game_state_init(state, mobile, rl.GetScreenWidth(), rl.GetScreenHeight())

    tile_map = new(TileMap)
    tile_map_init(tile_map, mobile)

    // Load all tokens from assets dir
    for file_name in list_files_in_dir("assets") {
        split := strings.split(file_name, ".", allocator = context.temp_allocator)
        join := strings.join({"assets/", file_name}, "", allocator = context.temp_allocator)
        state.textures[strings.clone(split[0])] = rl.LoadTexture(
            strings.clone_to_cstring(join, context.temp_allocator),
        )
    }
}

draw_connections :: proc(my_id: string, socket_ready: bool, peers: map[string]bool) {
    offset: i32 = 30
    id := fmt.caprint("my_id: ", my_id, allocator = context.temp_allocator)
    rl.DrawText(id, state.screen_width - 230, offset, 18, rl.BLUE)
    offset += 30
    rl.DrawText("Signaling status", state.screen_width - 230, offset, 18, socket_ready ? rl.GREEN : rl.RED)
    for peer, peer_status in peers {
        offset += 30
        rl.DrawText(
            strings.clone_to_cstring(peer, context.temp_allocator),
            state.screen_width - 230,
            offset,
            18,
            peer_status ? rl.GREEN : rl.RED,
        )
    }
}

update :: proc() {
    rl.BeginDrawing()
    rl.ClearBackground(EMPTY_COLOR.xyzw)

    state.screen_height = rl.GetScreenHeight()
    state.screen_width = rl.GetScreenWidth()
    state.gui_rectangles[.COLORPICKER] = {f32(state.screen_width - 230), 10, 200, 200}
    state.gui_rectangles[.COLORBARHUE] = {f32(state.screen_width - 30), 5, 30, 205}
    state.gui_rectangles[.COLORBARALPHA] = {f32(state.screen_width - 230), 215, 200, 20}
    if state.draw_initiative {
        state.gui_rectangles[.INITIATIVE] = {0, 0, 120, f32(state.screen_height)}
    }

    state.temp_actions = make([dynamic]Action, context.temp_allocator)
    state.key_consumed = false

    //TODO(amatej): somehow use the icons configured from config.odin,
    //              but it is complicated by colorpicker
    icon: rl.GuiIconName
    //TODO(amatej): convert to temp action
    highligh_current_tile := false
    highligh_current_tile_intersection := false
    mouse_pos: [2]f32 = rl.GetMousePosition()

    mouse_tile_pos: TileMapPosition = screen_coord_to_tile_map(mouse_pos, state, tile_map)
    tooltip: Maybe(cstring) = nil

    selected_widget: Widget = .MAP
    for widget, &rec in state.gui_rectangles {
        if (rl.CheckCollisionPointRec(mouse_pos, rec)) {
            selected_widget = widget
        }
    }

    if !state.mobile {
        // Mouse clicks
        if rl.IsMouseButtonPressed(.LEFT) {
            if (state.tool_start_position == nil) {
                state.tool_start_position = mouse_pos
            }
        } else if rl.IsMouseButtonDown(.RIGHT) {
            state.camera_pos.rel_tile -= rl.GetMouseDelta()
        }
        tile_map.tile_side_in_pixels += i32(rl.GetMouseWheelMove())
    }
    touch_count := rl.GetTouchPointCount()

    switch state.active_tool {
    case .LIGHT_SOURCE:
        {
            if selected_widget == .MAP {
                if rl.IsMouseButtonDown(.LEFT) {
                    state.light_source = (state.tool_start_position.? - mouse_pos) / 100
                }
            }
            icon = .ICON_CURSOR_SCALE_LEFT
        }
    case .BRUSH:
        {
            if selected_widget == .MAP {
                if rl.IsMouseButtonDown(.LEFT) {
                    append(&state.undo_history, make_action(.BRUSH))
                    action: ^Action = &state.undo_history[len(state.undo_history) - 1]
                    if (!(mouse_tile_pos.abs_tile in action.tile_history)) {
                        old_tile := get_tile(tile_map, mouse_tile_pos.abs_tile)
                        new_tile := old_tile
                        new_tile.color = state.selected_color
                        action.tile_history[mouse_tile_pos.abs_tile] = tile_subtract(&old_tile, &new_tile)
                        action.performed = true
                        set_tile(tile_map, mouse_tile_pos.abs_tile, new_tile)
                    }
                }
            }
            icon = .ICON_PENCIL
            highligh_current_tile = true
        }
    case .CONE:
        {
            if rl.IsMouseButtonDown(.LEFT) {
                append(&state.temp_actions, make_action(.CONE, context.temp_allocator))
                temp_action: ^Action = &state.temp_actions[len(state.temp_actions) - 1]
                tooltip = cone_tool(state, tile_map, mouse_pos, temp_action)
            } else if rl.IsMouseButtonReleased(.LEFT) {
                if (state.tool_start_position != nil) {
                    append(&state.undo_history, make_action(.CONE))
                    action: ^Action = &state.undo_history[len(state.undo_history) - 1]
                    action.performed = true
                    tooltip = cone_tool(state, tile_map, mouse_pos, action)
                    state.needs_sync = true
                }
            } else {
                highligh_current_tile_intersection = true
            }
            icon = .ICON_CURSOR_POINTER
        }
    case .RECTANGLE:
        {
            if rl.IsMouseButtonDown(.LEFT) {
                append(&state.temp_actions, make_action(.RECTANGLE, context.temp_allocator))
                temp_action: ^Action = &state.temp_actions[len(state.temp_actions) - 1]
                start_mouse_tile: TileMapPosition = screen_coord_to_tile_map(
                    state.tool_start_position.?,
                    state,
                    tile_map,
                )
                end_mouse_tile: TileMapPosition = screen_coord_to_tile_map(mouse_pos, state, tile_map)
                tooltip = rectangle_tool(start_mouse_tile, end_mouse_tile, state.selected_color, tile_map, temp_action)
            } else if rl.IsMouseButtonReleased(.LEFT) {
                if (state.tool_start_position != nil) {
                    append(&state.undo_history, make_action(.RECTANGLE))
                    action: ^Action = &state.undo_history[len(state.undo_history) - 1]
                    start_mouse_tile: TileMapPosition = screen_coord_to_tile_map(
                        state.tool_start_position.?,
                        state,
                        tile_map,
                    )
                    end_mouse_tile: TileMapPosition = screen_coord_to_tile_map(mouse_pos, state, tile_map)
                    action.performed = true
                    tooltip = rectangle_tool(start_mouse_tile, end_mouse_tile, state.selected_color, tile_map, action)
                    state.needs_sync = true
                }
            }
            icon = .ICON_BOX
            highligh_current_tile = true
        }
    case .CIRCLE:
        {
            if rl.IsMouseButtonDown(.LEFT) {
                append(&state.temp_actions, make_action(.CIRCLE, context.temp_allocator))
                temp_action: ^Action = &state.temp_actions[len(state.temp_actions) - 1]
                tooltip = circle_tool(state, tile_map, mouse_pos, temp_action)
            } else if rl.IsMouseButtonReleased(.LEFT) {
                if (state.tool_start_position != nil) {
                    append(&state.undo_history, make_action(.CIRCLE))
                    action: ^Action = &state.undo_history[len(state.undo_history) - 1]
                    tooltip = circle_tool(state, tile_map, mouse_pos, action)
                    state.needs_sync = true
                }
            } else {
                highligh_current_tile_intersection = true
            }
            icon = .ICON_PLAYER_RECORD
        }
    case .MOVE_TOKEN:
        {
            if len(state.selected_tokens) > 0 {
                if rl.IsMouseButtonPressed(.LEFT) || rl.IsKeyPressed(.ENTER) {
                    for token_id in state.selected_tokens {
                        token := &state.tokens[token_id]
                        if mouse_tile_pos.abs_tile != token.position.abs_tile {
                            append(&state.undo_history, make_action(.MOVE_TOKEN))
                            action: ^Action = &state.undo_history[len(state.undo_history) - 1]
                            move_token_tool(state, token, tile_map, mouse_pos, action, false)
                            action.performed = true
                            state.needs_sync = true
                        }
                    }
                    if rl.IsMouseButtonPressed(.LEFT) {
                        clear_selected_tokens(state)
                    }
                } else {
                    if rl.IsMouseButtonReleased(.LEFT) {
                        moved: bool = false
                        for token_id in state.selected_tokens {
                            token := &state.tokens[token_id]
                            if mouse_tile_pos.abs_tile != token.position.abs_tile {
                                append(&state.undo_history, make_action(.MOVE_TOKEN))
                                action: ^Action = &state.undo_history[len(state.undo_history) - 1]
                                move_token_tool(state, token, tile_map, mouse_pos, action, true)
                                moved = true
                                action.performed = true
                                state.needs_sync = true
                            }
                        }
                        if moved {
                            clear_selected_tokens(state)
                        }
                    }
                    for token_id in state.selected_tokens {
                        append(&state.temp_actions, make_action(.MOVE_TOKEN, context.temp_allocator))
                        temp_action: ^Action = &state.temp_actions[len(state.temp_actions) - 1]
                        move_token_tool(state, &state.tokens[token_id], tile_map, mouse_pos, temp_action, true)
                    }
                }
            } else {
                if rl.IsMouseButtonPressed(.LEFT) {
                    token := find_token_at_screen(tile_map, state, mouse_pos)
                    if token != nil {
                        append(&state.selected_tokens, token.id)
                    }
                }
            }
            icon = .ICON_TARGET_MOVE
        }
    case .COLOR_PICKER:
        {
            if selected_widget == .MAP {
                if rl.IsMouseButtonPressed(.LEFT) {
                    mouse_tile: Tile = get_tile(tile_map, mouse_tile_pos.abs_tile)
                    state.selected_color = mouse_tile.color
                }
                icon = .ICON_COLOR_PICKER
            }
        }
    case .WALL:
        {
            if rl.IsMouseButtonDown(.LEFT) {
                append(&state.temp_actions, make_action(.WALL, context.temp_allocator))
                temp_action: ^Action = &state.temp_actions[len(state.temp_actions) - 1]
                tooltip = wall_tool(state, tile_map, mouse_pos, temp_action)
            } else if rl.IsMouseButtonReleased(.LEFT) {
                if (state.tool_start_position != nil) {
                    append(&state.undo_history, make_action(.WALL))
                    action: ^Action = &state.undo_history[len(state.undo_history) - 1]
                    tooltip = wall_tool(state, tile_map, mouse_pos, action)
                    action.performed = true
                }
            } else {
                highligh_current_tile_intersection = true
            }
            icon = .ICON_BOX_GRID_BIG
        }
    case .EDIT_TOKEN, .EDIT_TOKEN_INITIATIVE:
        {
            #partial switch selected_widget {
            case .MAP:
                {
                    token: ^Token = nil
                    if len(state.selected_tokens) > 0 {
                        token = &state.tokens[state.selected_tokens[0]]
                    }
                    if token != nil && !rl.IsKeyPressed(.TAB) {
                        key := rl.GetKeyPressed()
                        // Trigger only once for each press
                        if rl.IsKeyPressed(key) {
                            if key == .DELETE {
                                init, init_index, ok := remove_token_by_id_from_initiative(state, token.id)
                                assert(ok)
                                token.alive = false
                                state.needs_sync = true
                                append(&state.undo_history, make_action(.EDIT_TOKEN))
                                action: ^Action = &state.undo_history[len(state.undo_history) - 1]
                                action.token_life[token.id] = false
                                action.performed = true
                                action.token_initiative_history[token.id] = {init, init_index}
                                clear_selected_tokens(state)
                            } else {
                                if rl.IsKeyDown(.BACKSPACE) {
                                    key = .BACKSPACE
                                }
                                byte: u8 = u8(key)
                                if byte != 0 {
                                    builder: strings.Builder
                                    strings.write_string(&builder, token.name)
                                    #partial switch key {
                                    case .BACKSPACE:
                                        strings.pop_rune(&builder)
                                    case .MINUS:
                                        {
                                            if token.size > 1 {
                                                token.size -= 1
                                                append(&state.undo_history, make_action(.EDIT_TOKEN))
                                                action: ^Action = &state.undo_history[len(state.undo_history) - 1]
                                                action.performed = true
                                                action.token_size[token.id] = -1
                                            }
                                        }
                                    case .EQUAL:
                                        {
                                            if token.size < 10 &&
                                               (rl.IsKeyDown(.RIGHT_SHIFT) || rl.IsKeyDown(.LEFT_SHIFT)) {
                                                token.size += 1
                                                append(&state.undo_history, make_action(.EDIT_TOKEN))
                                                action: ^Action = &state.undo_history[len(state.undo_history) - 1]
                                                action.performed = true
                                                action.token_size[token.id] = 1
                                            }
                                        }
                                    case .RIGHT_SHIFT, .LEFT_SHIFT:
                                        {
                                        }
                                    case:
                                        strings.write_byte(&builder, byte)
                                    }

                                    append(&state.undo_history, make_action(.EDIT_TOKEN))
                                    action: ^Action = &state.undo_history[len(state.undo_history) - 1]
                                    action.performed = true
                                    action.token_history[token.id] = {0, 0}
                                    action.old_names[token.id] = strings.clone(token.name)
                                    action.new_names[token.id] = strings.clone(strings.to_string(builder))

                                    delete(token.name)
                                    token.name = strings.to_string(builder)

                                    state.key_consumed = true
                                    set_texture_based_on_name(state, token)
                                }
                            }
                        }
                    } else if rl.IsMouseButtonPressed(.LEFT) {
                        token := find_token_at_screen(tile_map, state, mouse_pos)
                        if token != nil {
                            append(&state.selected_tokens, token.id)
                        } else if rl.IsKeyDown(.LEFT_SHIFT) {
                            players := [?]string{"Wesley", "AR100", "Daren", "Max", "Mardun", "Rodion"}
                            append(&state.undo_history, make_action(.EDIT_TOKEN))
                            action: ^Action = &state.undo_history[len(state.undo_history) - 1]
                            pos_offset: u32 = 0
                            for name in players {
                                token_pos := mouse_tile_pos
                                token_pos.rel_tile = {0, 0}
                                token_pos.abs_tile.y += pos_offset

                                token_spawn(state, action, token_pos, state.selected_color, name)
                                pos_offset += 2
                            }
                            action.performed = true
                            state.needs_sync = true
                        } else {
                            action := make_action(.EDIT_TOKEN)
                            token_pos := mouse_tile_pos
                            token_pos.rel_tile = {0, 0}
                            token_spawn(state, &action, token_pos, state.selected_color)
                            append(&state.undo_history, action)
                        }
                    } else {
                        c := state.selected_color
                        c.a = 90
                        token, ok := &state.tokens[0]
                        if ok {
                            token.alive = true
                            token.position = mouse_tile_pos
                            token.color = c
                        }
                        append(&state.temp_actions, make_action(.EDIT_TOKEN, context.temp_allocator))
                        temp_action: ^Action = &state.temp_actions[len(state.temp_actions) - 1]
                        temp_action.token_life[0] = true
                    }
                    icon = .ICON_PLAYER
                }
            case .INITIATIVE:
                {
                    if rl.IsMouseButtonDown(.LEFT) {
                        append(&state.temp_actions, make_action(.EDIT_TOKEN_INITIATIVE, context.temp_allocator))
                        temp_action: ^Action = &state.temp_actions[len(state.temp_actions) - 1]
                        move_initiative_token_tool(state, state.tool_start_position.?.y, mouse_pos.y, temp_action)
                    } else if rl.IsMouseButtonReleased(.LEFT) {
                        if (state.tool_start_position != nil) {
                            append(&state.undo_history, make_action(.EDIT_TOKEN_INITIATIVE))
                            action: ^Action = &state.undo_history[len(state.undo_history) - 1]
                            move_initiative_token_tool(state, state.tool_start_position.?.y, mouse_pos.y, action)
                            action.performed = true
                            state.needs_sync = true
                        }
                    }
                    icon = .ICON_SHUFFLE
                }
            }
        }
    case .TOUCH_MOVE:
        {
            if state.previous_touch_pos != 0 {
                d := state.previous_touch_pos - mouse_pos
                state.camera_pos.rel_tile += d / 5
            }

            state.previous_touch_pos = mouse_pos
        }
    case .TOUCH_ZOOM:
        {
            if touch_count >= 2 {
                touch1 := rl.GetTouchPosition(0)
                touch2 := rl.GetTouchPosition(1)
                dist := dist(touch1, touch2)

                if state.previous_touch_dist != 0 {
                    zoom_amount := i32((state.previous_touch_dist - dist) * 0.1)
                    tile_map.tile_side_in_pixels -= zoom_amount
                    tile_map.tile_side_in_pixels = math.max(20, tile_map.tile_side_in_pixels)
                }

                state.previous_touch_dist = dist
            }
        }
    case .EDIT_BG:
        {
            if rl.IsKeyPressed(.MINUS) {
                state.bg_scale -= 0.01
                state.key_consumed = true
            }
            if rl.IsKeyPressed(.EQUAL) {
                state.bg_scale += 0.01
                state.key_consumed = true
            }
            if rl.IsKeyDown(.LEFT) {
                state.bg_pos.rel_tile.x -= 0.1
                state.bg_pos = recanonicalize_position(tile_map, state.bg_pos)
                state.key_consumed = true
            }
            if rl.IsKeyDown(.RIGHT) {
                state.bg_pos.rel_tile.x += 0.1
                state.bg_pos = recanonicalize_position(tile_map, state.bg_pos)
                state.key_consumed = true
            }
            if rl.IsKeyDown(.UP) {
                state.bg_pos.rel_tile.y -= 0.1
                state.bg_pos = recanonicalize_position(tile_map, state.bg_pos)
                state.key_consumed = true
            }
            if rl.IsKeyDown(.DOWN) {
                state.bg_pos.rel_tile.y += 0.1
                state.bg_pos = recanonicalize_position(tile_map, state.bg_pos)
                state.key_consumed = true
            }
            icon = .ICON_LAYERS
        }
    case .HELP:
        {
        }
    }

    if rl.IsMouseButtonReleased(.LEFT) {
        if (state.tool_start_position != nil) {
            state.tool_start_position = nil
        }
    }


    if state.mobile {
        if touch_count > state.previous_touch_count {
            //TODO(amatej): this overrides any other active tool...
            if len(state.selected_tokens) != 0 {
                state.active_tool = .MOVE_TOKEN
            } else if touch_count >= 2 {
                state.active_tool = .TOUCH_ZOOM
            } else if touch_count == 1 {
                state.active_tool = .TOUCH_MOVE
            }
        } else if state.previous_touch_count > touch_count {
            state.previous_touch_pos = 0
            state.previous_touch_dist = 0
            state.active_tool = .MOVE_TOKEN
        }
        state.previous_touch_count = touch_count
    } else {
        if !state.key_consumed {
            for c in config {
                triggered: bool = true
                for trigger in c.key_triggers {
                    trigger_proc: proc "c" (_: rl.KeyboardKey) -> bool
                    switch trigger.action {
                    case .DOWN:
                        {
                            trigger_proc = rl.IsKeyDown
                        }
                    case .RELEASED:
                        {
                            trigger_proc = rl.IsKeyReleased
                        }
                    case .PRESSED:
                        {
                            trigger_proc = rl.IsKeyPressed
                        }
                    }
                    triggered = triggered && trigger_proc(trigger.binding)
                }
                if triggered {
                    for binding in c.bindings {
                        picked_binding := true
                        tool, tool_ok := binding.tool.?
                        if tool_ok {
                            picked_binding = picked_binding && tool == state.active_tool
                        }
                        cond_proc, cond_ok := binding.condition.?
                        if cond_ok {
                            picked_binding = picked_binding && cond_proc(state)
                        }
                        if picked_binding {
                            binding.action(state)
                            break
                        }
                    }
                }
            }
        }
    }

    state.camera_pos = recanonicalize_position(tile_map, state.camera_pos)

    tile_map.tile_side_in_pixels = math.max(5, tile_map.tile_side_in_pixels)
    tile_map.feet_to_pixels = f32(tile_map.tile_side_in_pixels) / tile_map.tile_side_in_feet
    tile_map.pixels_to_feet = tile_map.tile_side_in_feet / f32(tile_map.tile_side_in_pixels)

    screen_center: rl.Vector2 = {f32(state.screen_width), f32(state.screen_height)} * 0.5

    // draw bg
    pos: rl.Vector2 = tile_map_to_screen_coord(state.bg_pos, state, tile_map)
    pos += state.bg_pos.rel_tile * tile_map.feet_to_pixels
    rl.DrawTextureEx(state.bg, pos, 0, state.bg_scale * tile_map.feet_to_pixels, rl.WHITE)

    // draw tile map
    tiles_needed_to_fill_half_of_screen := screen_center / f32(tile_map.tile_side_in_pixels)
    for row_offset: i32 = i32(math.floor(-tiles_needed_to_fill_half_of_screen.y));
        row_offset <= i32(math.ceil(tiles_needed_to_fill_half_of_screen.y));
        row_offset += 1 {
        cen_y: f32 =
            screen_center.y -
            tile_map.feet_to_pixels * state.camera_pos.rel_tile.y +
            f32(row_offset * tile_map.tile_side_in_pixels)
        min_y: f32 = cen_y - 0.5 * f32(tile_map.tile_side_in_pixels)

        for column_offset: i32 = i32(math.floor(-tiles_needed_to_fill_half_of_screen.x));
            column_offset <= i32(math.ceil(tiles_needed_to_fill_half_of_screen.x));
            column_offset += 1 {
            current_tile: [2]u32
            current_tile.x = (state.camera_pos.abs_tile.x) + u32(column_offset)
            current_tile.y = (state.camera_pos.abs_tile.y) + u32(row_offset)

            current_tile_value: Tile = get_tile(tile_map, current_tile)

            if highligh_current_tile {
                if (current_tile.y == mouse_tile_pos.abs_tile.y) && (current_tile.x == mouse_tile_pos.abs_tile.x) {
                    current_tile_value = tile_make(color_over(state.selected_color, current_tile_value.color))
                }
            }

            // Calculate tile position on screen
            cen_x: f32 =
                screen_center.x -
                tile_map.feet_to_pixels * state.camera_pos.rel_tile.x +
                f32(column_offset * tile_map.tile_side_in_pixels)
            min_x: f32 = cen_x - 0.5 * f32(tile_map.tile_side_in_pixels)
            if current_tile_value.color != {77, 77, 77, 255} {
                rl.DrawRectangleV(
                    {min_x, min_y},
                    {f32(tile_map.tile_side_in_pixels), f32(tile_map.tile_side_in_pixels)},
                    current_tile_value.color.xyzw,
                )
            }

            if Direction.TOP in current_tile_value.walls {
                if current_tile_value.wall_colors[Direction.TOP].w != 0 {
                    //TODO(amatej): use DrawLineEx if we want to do diagonals
                    rl.DrawRectangleV(
                        {min_x, min_y},
                        {f32(tile_map.tile_side_in_pixels), f32(2)},
                        current_tile_value.wall_colors[Direction.TOP].xyzw,
                    )
                }
            }
            if current_tile_value.wall_colors[Direction.LEFT].w != 0 {
                if Direction.LEFT in current_tile_value.walls {
                    rl.DrawRectangleV(
                        {min_x, min_y},
                        {f32(2), f32(tile_map.tile_side_in_pixels)},
                        current_tile_value.wall_colors[Direction.LEFT].xyzw,
                    )
                }
            }
        }

        if (state.draw_grid) {
            rl.DrawLineV({0, min_y}, {f32(state.screen_width), min_y}, {0, 0, 0, 20})
        }
    }

    // Draw wall shadows, has to be done after all TILEs are drawn, because the shadows can
    // extend beyond its TILE
    for row_offset: i32 = i32(math.floor(-tiles_needed_to_fill_half_of_screen.y));
        row_offset <= i32(math.ceil(tiles_needed_to_fill_half_of_screen.y));
        row_offset += 1 {
        cen_y: f32 =
            screen_center.y -
            tile_map.feet_to_pixels * state.camera_pos.rel_tile.y +
            f32(row_offset * tile_map.tile_side_in_pixels)
        min_y: f32 = cen_y - 0.5 * f32(tile_map.tile_side_in_pixels)

        for column_offset: i32 = i32(math.floor(-tiles_needed_to_fill_half_of_screen.x));
            column_offset <= i32(math.ceil(tiles_needed_to_fill_half_of_screen.x));
            column_offset += 1 {
            current_tile: [2]u32
            current_tile.x = (state.camera_pos.abs_tile.x) + u32(column_offset)
            current_tile.y = (state.camera_pos.abs_tile.y) + u32(row_offset)
            current_tile_value: Tile = get_tile(tile_map, current_tile)

            // Calculate tile position on screen
            cen_x: f32 =
                screen_center.x -
                tile_map.feet_to_pixels * state.camera_pos.rel_tile.x +
                f32(column_offset * tile_map.tile_side_in_pixels)
            min_x: f32 = cen_x - 0.5 * f32(tile_map.tile_side_in_pixels)

            shadow := state.light_source * f32(tile_map.tile_side_in_pixels) * 3
            if Direction.TOP in current_tile_value.walls {
                if current_tile_value.wall_colors[Direction.TOP].w != 0 {
                    draw_quad(
                        {min_x, min_y},
                        {min_x + f32(tile_map.tile_side_in_pixels), min_y},
                        {min_x, min_y} + shadow,
                        {min_x + f32(tile_map.tile_side_in_pixels), min_y} + shadow,
                        state.shadow_color,
                    )
                }
            }
            if current_tile_value.wall_colors[Direction.LEFT].w != 0 {
                if Direction.LEFT in current_tile_value.walls {
                    draw_quad(
                        {min_x, min_y},
                        {min_x, min_y} + shadow,
                        {min_x, min_y + f32(tile_map.tile_side_in_pixels)},
                        {min_x, min_y + f32(tile_map.tile_side_in_pixels)} + shadow,
                        state.shadow_color,
                    )
                }
            }
        }

        if (state.draw_grid) {
            rl.DrawLineV({0, min_y}, {f32(state.screen_width), min_y}, {0, 0, 0, 20})
        }
    }

    // draw tokens on map
    for _, &token in state.tokens {
        if token.alive {
            pos: rl.Vector2 = tile_map_to_screen_coord(token.position, state, tile_map)
            token_pos, token_radius := get_token_circle(tile_map, state, token)
            // Draw shadows only for real tokens, skip temp 0 token
            if token.id != 0 {
                token_base_from: [4]u8 = {0, 0, 0, 30}
                rl.DrawCircleGradient(
                    i32(token_pos.x),
                    i32(token_pos.y),
                    token_radius + 0.2 * f32(tile_map.tile_side_in_pixels),
                    token_base_from.xyzw,
                    TRANSPARENT_COLOR.xyzw,
                )
                rl.DrawCircleV(
                    token_pos + state.light_source * f32(tile_map.tile_side_in_pixels),
                    token_radius,
                    state.shadow_color.xyzw,
                )
                for selected_id in state.selected_tokens {
                    if selected_id == token.id {
                        rl.DrawCircleGradient(
                            i32(token_pos.x),
                            i32(token_pos.y),
                            token_radius + 0.1 * f32(tile_map.tile_side_in_pixels),
                            SELECTED_COLOR.xyzw,
                            SELECTED_TRANSPARENT_COLOR.xyzw,
                        )
                    }
                }
            }
            if (token.texture != nil) {
                tex_pos, scale := get_token_texture_pos_size(tile_map, state, token)
                rl.DrawTextureEx(token.texture^, tex_pos, 0, scale, rl.WHITE)
            } else {
                rl.DrawCircleV(token_pos, token_radius, token.color.xyzw)
            }
            rl.DrawText(
                get_token_name_temp(&token),
                i32(pos.x) - tile_map.tile_side_in_pixels / 2,
                i32(pos.y) + tile_map.tile_side_in_pixels / 2,
                18,
                rl.WHITE,
            )
            if (token.moved != 0) {
                for selected_id in state.selected_tokens {
                    if selected_id == token.id {
                        text_size: i32 = 28
                        text_pos: [2]f32 = pos - 50
                        if state.mobile {
                            text_size = 98
                            text_pos = pos - 250
                        }

                        rl.DrawText(
                            u64_to_cstring(u64(f32(token.moved) * tile_map.tile_side_in_feet)),
                            i32(text_pos.x),
                            i32(text_pos.y),
                            text_size,
                            rl.WHITE,
                        )
                    }
                    break
                }
            }
        }
    }

    if highligh_current_tile_intersection {
        half := tile_map.tile_side_in_feet / 2
        m := mouse_tile_pos
        m.rel_tile.x = m.rel_tile.x >= 0 ? half : -half
        m.rel_tile.y = m.rel_tile.y >= 0 ? half : -half
        size: f32 = f32(tile_map.tile_side_in_pixels)
        cross_pos := tile_map_to_screen_coord(m, state, tile_map)
        cross_pos += m.rel_tile * tile_map.feet_to_pixels
        rl.DrawRectangleV(cross_pos - {1, size / 2}, {2, size}, {255, 255, 255, 255})
        rl.DrawRectangleV(cross_pos - {size / 2, 1}, {size, 2}, {255, 255, 255, 255})
    }

    // draw initiative tracker
    if (state.draw_initiative) {
        rl.DrawRectangleGradientEx(
            state.gui_rectangles[.INITIATIVE],
            {40, 40, 40, 45},
            {40, 40, 40, 45},
            {0, 0, 0, 0},
            {0, 0, 0, 0},
        )
        row_offset: i32 = 10
        for i: i32 = 1; i < INITIATIVE_COUNT; i += 1 {
            tokens := state.initiative_to_tokens[i]
            if (tokens == nil || len(tokens) == 0) {
                if state.active_tool == .EDIT_TOKEN {
                    rl.DrawText(u64_to_cstring(u64(i)), 10, row_offset, 10, rl.GRAY)
                    row_offset += 13
                } else {
                    continue
                }
            } else {
                row_offset += 3
                rl.DrawText(u64_to_cstring(u64(i)), 10, row_offset, 10, rl.GRAY)
                for token_id in tokens {
                    token := state.tokens[token_id]
                    token_size := f32(token.size) * 4 + 10
                    half_of_this_row := i32(token_size + 3)

                    circle_pos: rl.Vector2 = {30 + token_size / 2, f32(row_offset + half_of_this_row)}
                    for selected_id in state.selected_tokens {
                        if selected_id == token.id {
                            rl.DrawCircleGradient(
                                i32(circle_pos.x),
                                i32(circle_pos.y),
                                token_size + 0.1 * f32(tile_map.tile_side_in_pixels),
                                SELECTED_COLOR.xyzw,
                                SELECTED_TRANSPARENT_COLOR.xyzw,
                            )
                        }
                    }
                    if (token.texture != nil) {
                        pos: rl.Vector2 = {23, f32(row_offset)}
                        // We assume token textures are squares
                        scale := f32(22 + token.size * 8) / f32(token.texture.width)
                        rl.DrawTextureEx(token.texture^, pos, 0, scale, rl.WHITE)
                    } else {
                        rl.DrawCircleV(circle_pos, f32(token_size), token.color.xyzw)
                    }
                    rl.DrawText(
                        get_token_name_temp(&token),
                        i32(30 + token_size + 15),
                        row_offset + i32(token_size) - 4,
                        18,
                        rl.WHITE,
                    )
                    row_offset += 2 * half_of_this_row
                }
            }
            rl.DrawRectangleGradientH(0, row_offset, 100, 2, {40, 40, 40, 155}, {0, 0, 0, 0})
        }
    }

    if state.save == .DONE {
        msg := fmt.caprint("Saved! (byte count: ", state.bytes_count, ")", allocator = context.temp_allocator)
        rl.DrawText(msg, 100, 100, 100, rl.BLUE)
        if state.timeout > 0 {
            state.timeout -= 1
        } else {
            state.save = .NONE
        }
    }
    // draw debug info
    if state.debug {
        live_t := 0
        keys := make([dynamic]u64, len(state.tokens), allocator = context.temp_allocator)
        i := 0
        for key, _ in state.tokens {
            keys[i] = key
            i += 1
        }
        slice.sort(keys[:])
        for token_id in keys {
            t := &state.tokens[token_id]
            if t.alive {
                live_t += 1
            }
            token_text := fmt.caprint(get_token_name_temp(t), ": ", t.position, allocator = context.temp_allocator)
            rl.DrawText(token_text, 530, 60 + 30 * (i32(live_t)), 15, rl.BLUE)
        }
        total_tokens_live := fmt.caprint("Total live tokens: ", live_t, allocator = context.temp_allocator)
        total_tokens := fmt.caprint("Total tokens: ", len(state.tokens), allocator = context.temp_allocator)
        rl.DrawText(total_tokens_live, 430, 30, 18, rl.BLUE)
        rl.DrawText(total_tokens, 430, 50, 18, rl.BLUE)
        total_actions := fmt.caprint("Total actions: ", len(state.undo_history), allocator = context.temp_allocator)
        rl.DrawText(total_actions, 30, 30, 18, rl.GREEN)
        for action_index := len(state.undo_history) - 1; action_index >= 0; action_index -= 1 {
            a := &state.undo_history[action_index]
            a_text := fmt.caprint(
                action_index == len(state.undo_history) - 1 - state.undone ? " -> " : "    ",
                action_index,
                ": ",
                a.tool,
                ", tile_history: ",
                len(a.tile_history),
                a.token_history,
                a.token_initiative_history,
                allocator = context.temp_allocator,
            )
            rl.DrawText(
                a_text,
                30,
                30 + 30 * (i32(len(state.undo_history)) - i32(action_index)),
                15,
                a.performed ? rl.GREEN : rl.RED,
            )
        }
    }

    if (state.draw_grid) {
        for column_offset: i32 = i32(math.floor(-tiles_needed_to_fill_half_of_screen.x));
            column_offset <= i32(math.ceil(tiles_needed_to_fill_half_of_screen.x));
            column_offset += 1 {
            cen_x: f32 =
                screen_center.x -
                tile_map.feet_to_pixels * state.camera_pos.rel_tile.x +
                f32(column_offset * tile_map.tile_side_in_pixels)
            min_x: f32 = cen_x - 0.5 * f32(tile_map.tile_side_in_pixels)
            min_x = math.max(0, min_x)
            rl.DrawLineV({min_x, 0}, {min_x, f32(state.screen_height)}, {0, 0, 0, 20})
        }
    }

    if state.active_tool == .COLOR_PICKER {
        rl.GuiColorBarAlpha(state.gui_rectangles[.COLORBARALPHA], "color picker alpha", &state.selected_alpha)
        rl.GuiColorPicker(state.gui_rectangles[.COLORPICKER], "color picker", (^rl.Color)(&state.selected_color))
        state.selected_color = rl.ColorAlpha(state.selected_color.xyzw, state.selected_alpha).xyzw
    }

    if state.active_tool == .HELP {
        rl.DrawRectangleV({30, 30}, {f32(state.screen_width) - 60, f32(state.screen_height) - 60}, {0, 0, 0, 155})
        offset: i32 = 100
        for c in config {
            builder := strings.builder_make(context.temp_allocator)
            for trigger in c.key_triggers {
                strings.write_string(
                    &builder,
                    fmt.aprintf("%s (%s) + ", trigger.binding, trigger.action, allocator = context.temp_allocator),
                )
            }
            strings.pop_rune(&builder)
            strings.pop_rune(&builder)
            rl.DrawText(strings.to_cstring(&builder) or_else BUILDER_FAILED, 100, offset, 18, rl.WHITE)
            //TODO(amatej): fix help
            //if c.icon != nil {
            //    rl.GuiDrawIcon(c.icon, 500, offset, 1, rl.WHITE)
            //}
            //rl.DrawText(strings.clone_to_cstring(c.help, context.temp_allocator), 540, offset, 18, rl.WHITE)
            offset += 30

        }
    }

    rl.GuiDrawIcon(icon, i32(mouse_pos.x) - 4, i32(mouse_pos.y) - 30, 2, rl.WHITE)
    if (tooltip != nil) {
        rl.DrawText(tooltip.?, i32(mouse_pos.x) + 10, i32(mouse_pos.y) + 30, 28, rl.WHITE)
    }

    // Before ending the loop revert all temp actions
    for _, index in state.temp_actions {
        undo_action(state, tile_map, &state.temp_actions[index])
    }
    clear(&state.temp_actions)

    rl.EndDrawing()
    free_all(context.temp_allocator)
}

tokens_reset :: proc(state: ^GameState) {
    for _, &token_ids in state.initiative_to_tokens {
        delete(token_ids)
    }
    clear(&state.initiative_to_tokens)
    clear(&state.selected_tokens)
    for _, &token in state.tokens {
        delete_token(&token)
    }
    clear(&state.tokens)
    state.tokens[0] = Token {
        id   = 0,
        name = strings.clone(" "),
        size = 1,
    }
}

shutdown :: proc() {
    rl.CloseWindow()
    for name, _ in state.textures {
        delete(name)
    }
    delete(state.textures)
    delete(state.gui_rectangles)

    tokens_reset(state)
    delete_token(&state.tokens[0])
    delete(state.initiative_to_tokens)
    delete(state.selected_tokens)
    delete(state.tokens)

    for _, index in state.undo_history {
        delete_action(&state.undo_history[index])
    }
    delete(state.undo_history)

    tilemap_clear(tile_map)
    delete(tile_map.tile_chunks)

    free(state)
    free(tile_map)

}

// In a web build, this is called when browser changes size. Remove the
// `rl.SetWindowSize` call if you don't want a resizable game.
parent_window_size_changed :: proc(w, h: int) {
    rl.SetWindowSize(i32(w), i32(h))
}

main :: proc() {
    when ODIN_DEBUG {
        track: mem.Tracking_Allocator
        mem.tracking_allocator_init(&track, context.allocator)
        context.allocator = mem.tracking_allocator(&track)
        defer {
            if len(track.allocation_map) > 0 {
                fmt.eprintf("=== %v allocations not freed: ===\n", len(track.allocation_map))
                for _, entry in track.allocation_map {
                    fmt.eprintf("- %v bytes @ %v\n", entry.size, entry.location)
                }
            }
            if len(track.bad_free_array) > 0 {
                fmt.eprintf("=== %v incorrect frees: ===\n", len(track.bad_free_array))
                for entry in track.bad_free_array {
                    fmt.eprintf("- %p @ %v\n", entry.memory, entry.location)
                }
            }
            mem.tracking_allocator_destroy(&track)
        }
    }
    init()
    for should_run(state) {
        update()
    }
    shutdown()
}

should_run :: proc(state: ^GameState) -> bool {
    return state.should_run
}
