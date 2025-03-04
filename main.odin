package tiler

import "core:math"
import "core:fmt"
import "core:mem"
import "core:strings"
import "core:os"
import "core:path/filepath"

import rl "vendor:raylib"

INIT_SCREEN_WIDTH: i32 : 1280
INIT_SCREEN_HEIGHT: i32 : 720

INITIATIVE_COUNT : i32 : 50

GameState :: struct {
    screen_width: i32,
    screen_height: i32,
    camera_pos: TileMapPosition,
    selected_color: [4]u8,
    selected_alpha: f32,
    gui_rectangles: map[Widget]rl.Rectangle,
    draw_grid: bool,
    draw_initiative: bool,
    active_tool: Tool,
    previous_tool: Maybe(Tool),
    tool_start_position: Maybe([2]f32),
    selected_token: u64,
    max_entity_id: u64,
    //TODO(amatej): check if the tool actually does any color change before recoding
    //              undoing non-color changes does nothing
    undo_history: [dynamic]Action,
    tokens: map[u64]Token,
    initiative_to_tokens: map[i32][dynamic]u64,
    // Valid only for one loop
    temp_actions: [dynamic]Action,
    key_consumed: bool,
    textures: map[string]rl.Texture2D,
}

Widget :: enum {
    MAP,
    COLORPICKER,
    COLORBARHUE,
    COLORBARALPHA,
    INITIATIVE,
}

u64_to_cstring :: proc(num: u64) -> cstring{
    builder := strings.builder_make(context.temp_allocator)
    strings.write_u64(&builder, num)
    return strings.to_cstring(&builder)
}

screen_coord_to_tile_map :: proc(pos: rl.Vector2, state: ^GameState, tile_map: ^TileMap) -> TileMapPosition {
    res: TileMapPosition = state.camera_pos

    delta: rl.Vector2 = pos

    screen_center : rl.Vector2 = {f32(state.screen_width), f32(state.screen_height)} * 0.5
    delta -= screen_center

    res.rel_tile.x += delta.x * f32(tile_map.pixels_to_feet)
    res.rel_tile.y += delta.y * f32(tile_map.pixels_to_feet)

    res = recanonicalize_position(tile_map, res)

    return res
}

find_token_at_screen :: proc(tile_map: ^TileMap, state: ^GameState, pos: rl.Vector2) -> ^Token {
    for _, &token in state.tokens {
        if rl.CheckCollisionPointCircle(pos, get_token_circle(tile_map, state, token)) {
            return &token
        }
    }

    return nil
}

// Snaps to grid (ignores rel_tile part)
tile_map_to_screen_coord :: proc(pos: TileMapPosition, state: ^GameState, tile_map: ^TileMap) -> rl.Vector2 {
    res : rl.Vector2 = {f32(state.screen_width), f32(state.screen_height)} * 0.5

    delta: [2]i32 = {i32(pos.abs_tile.x), i32(pos.abs_tile.y)}
    delta -= {i32(state.camera_pos.abs_tile.x), i32(state.camera_pos.abs_tile.y)}

    res.x += f32(delta.x * tile_map.tile_side_in_pixels)
    res.y += f32(delta.y * tile_map.tile_side_in_pixels)

    res -= state.camera_pos.rel_tile * tile_map.feet_to_pixels

    return res
}

state: ^GameState
tile_map: ^TileMap

// Beware the returned data are temp only by default
serialize_to_bytes :: proc(allocator := context.temp_allocator) -> []byte {
    s: Serializer
    serializer_init_writer(&s, allocator=allocator)
    serialize(&s, tile_map)
    fmt.println(len(s.data[:]))
    serialize(&s, state)
    fmt.println(len(s.data[:]))
    compressed_chunks: CompressedTileChunks
    compressed_chunks.tile_chunks = make(map[[2]u32]CompressedTileChunk, context.temp_allocator)
    for key, &value in tile_map.tile_chunks {
        compressed_chunks.tile_chunks[key] = compress_tile_chunk(&value)
    }
    //fmt.println(compressed_chunks)
    serialize(&s, &compressed_chunks)
    fmt.println(len(s.data[:]))
    return s.data[:]
}

load_from_serialized :: proc(data: []byte) {
    s: Serializer
    serializer_init_reader(&s, data)
    serialize(&s, tile_map)
    serialize(&s, state)
    compressed_chunks: CompressedTileChunks
    serialize(&s, &compressed_chunks)
    for key, &value in compressed_chunks.tile_chunks {
        tile_map.tile_chunks[key] = TileChunk{}
        decompress_tile_chunk_into(&value, &tile_map.tile_chunks[key])
        delete(value.tiles)
        delete(value.counts)
    }
    delete(compressed_chunks.tile_chunks)
}

init :: proc() {
    rl.SetConfigFlags({.WINDOW_RESIZABLE, .VSYNC_HINT})
    rl.InitWindow(INIT_SCREEN_WIDTH, INIT_SCREEN_HEIGHT, "Tiler")

    // Since we don't run any simulation we don't have to run when there is not user input
    rl.EnableEventWaiting()

    state = new(GameState)
    state.camera_pos.abs_tile.x = 100
    state.camera_pos.abs_tile.y = 100
    state.camera_pos.rel_tile.x = 0.0
    state.camera_pos.rel_tile.y = 0.0
    state.screen_height = rl.GetScreenHeight()
    state.screen_width = rl.GetScreenWidth()
    state.draw_grid = true
    state.draw_initiative = true
    state.active_tool = Tool.RECTANGLE
    state.selected_color.a = 255
    state.selected_alpha = 1
    // entity id 0 is reserved for temporary preview entity
    state.max_entity_id = 1

    tile_map = new(TileMap)
    tile_map.chunk_shift = 8
    tile_map.chunk_mask = (1 << tile_map.chunk_shift) - 1
    tile_map.chunk_dim = (1 << tile_map.chunk_shift)

    tile_map.tile_side_in_feet = 5
    tile_map.tile_side_in_pixels = 30
    tile_map.feet_to_pixels = f32(tile_map.tile_side_in_pixels) / tile_map.tile_side_in_feet
    tile_map.pixels_to_feet = tile_map.tile_side_in_feet / f32(tile_map.tile_side_in_pixels)

    // Load all tokens from assets dir
    for file_name in list_files_in_dir("assets") {
        split := strings.split(file_name, ".", allocator=context.temp_allocator)
        join := strings.join({"assets/", file_name}, "", allocator=context.temp_allocator)
        state.textures[strings.clone(split[0])] = rl.LoadTexture(strings.clone_to_cstring(join, context.temp_allocator))
    }

    data, ok := os.read_entire_file("./save", context.temp_allocator)
    if ok {
        load_from_serialized(data)
    }
}

update :: proc() {
    rl.BeginDrawing()
    rl.ClearBackground(rl.BLACK)

    state.screen_height = rl.GetScreenHeight()
    state.screen_width = rl.GetScreenWidth()
    state.gui_rectangles[.COLORPICKER] = {f32(state.screen_width - 230), 10, 200, 200}
    state.gui_rectangles[.COLORBARHUE] = {f32(state.screen_width - 30), 5, 30, 205}
    state.gui_rectangles[.COLORBARALPHA] = {f32(state.screen_width - 230), 215, 200, 20}
    if state.draw_initiative {
        state.gui_rectangles[.INITIATIVE] = {0,0,120, f32(state.screen_height)}
    }

    state.temp_actions = make([dynamic]Action, context.temp_allocator)
    state.key_consumed = false

    //TODO(amatej): somehow use the icons configured from config.odin,
    //              but it is complicated by colorpicker
    icon : rl.GuiIconName
    //TODO(amatej): convert to temp action
    highligh_current_tile := false
    highligh_current_tile_intersection := false
    token := find_token_at_screen(tile_map, state, rl.GetMousePosition())
    mouse_tile_pos : TileMapPosition = screen_coord_to_tile_map(rl.GetMousePosition(), state, tile_map)
    tooltip: Maybe(cstring) = nil

    selected_widget : Widget= .MAP
    for widget, &rec in state.gui_rectangles {
        if (rl.CheckCollisionPointRec(rl.GetMousePosition(), rec)) {
            selected_widget = widget
        }
    }

    // Mouse clicks
    if rl.IsMouseButtonPressed(.LEFT) {
        if (state.tool_start_position == nil) {
            state.tool_start_position = rl.GetMousePosition()
            append(&state.undo_history, Action{})
        }
    } else if rl.IsMouseButtonDown(.RIGHT) {
        state.camera_pos.rel_tile -= rl.GetMouseDelta()
    }

    switch state.active_tool {
    case .BRUSH: {
        if selected_widget == .MAP {
            if rl.IsMouseButtonDown(.LEFT) {
                action : ^Action = &state.undo_history[len(state.undo_history)-1]
                if (!(mouse_tile_pos.abs_tile in action.tile_history)) {
                    action.tile_history[mouse_tile_pos.abs_tile] = get_tile(tile_map, mouse_tile_pos.abs_tile)
                }
                set_tile(tile_map, mouse_tile_pos.abs_tile, tile_make(state.selected_color))
            }
        }
        icon = .ICON_PENCIL
        highligh_current_tile = true
    }
    case .RECTANGLE: {
        if rl.IsMouseButtonDown(.LEFT) {
            append(&state.temp_actions, make_action(context.temp_allocator))
            temp_action : ^Action = &state.temp_actions[len(state.temp_actions)-1]
            tooltip = rectangle_tool(state, tile_map, rl.GetMousePosition(), temp_action)
        } else if rl.IsMouseButtonReleased(.LEFT) {
            if (state.tool_start_position != nil) {
                action : ^Action = &state.undo_history[len(state.undo_history)-1]
                tooltip = rectangle_tool(state, tile_map, rl.GetMousePosition(), action)
            }
        }
        icon = .ICON_BOX
        highligh_current_tile = true
    }
    case .CIRCLE: {
        if rl.IsMouseButtonDown(.LEFT) {
            append(&state.temp_actions, make_action(context.temp_allocator))
            temp_action : ^Action = &state.temp_actions[len(state.temp_actions)-1]
            tooltip = circle_tool(state, tile_map, rl.GetMousePosition(), temp_action)
        } else if rl.IsMouseButtonReleased(.LEFT) {
            if (state.tool_start_position != nil) {
                action : ^Action = &state.undo_history[len(state.undo_history)-1]
                tooltip = circle_tool(state, tile_map, rl.GetMousePosition(), action)
            }
        } else {
            highligh_current_tile_intersection = true
        }
        icon = .ICON_PLAYER_RECORD
    }
    case .MOVE_TOKEN: {
        if rl.IsMouseButtonDown(.LEFT) {
            append(&state.temp_actions, make_action(context.temp_allocator))
            temp_action : ^Action = &state.temp_actions[len(state.temp_actions)-1]
            move_token_tool(state, tile_map, rl.GetMousePosition(), temp_action, true)
        } else if rl.IsMouseButtonReleased(.LEFT) {
            if (state.tool_start_position != nil) {
                action : ^Action = &state.undo_history[len(state.undo_history)-1]
                move_token_tool(state, tile_map, rl.GetMousePosition(), action, false)
            }
        }
        icon = .ICON_TARGET_MOVE
    }
    case .COLOR_PICKER: {
        if selected_widget == .MAP {
            if rl.IsMouseButtonPressed(.LEFT) {
                mouse_tile : Tile = get_tile(tile_map, mouse_tile_pos.abs_tile)
                state.selected_color = mouse_tile.color
            }
            icon = .ICON_COLOR_PICKER
        }
    }
    case .WALL: {
        if rl.IsMouseButtonDown(.LEFT) {
            append(&state.temp_actions, make_action(context.temp_allocator))
            temp_action : ^Action = &state.temp_actions[len(state.temp_actions)-1]
            tooltip = wall_tool(state, tile_map, rl.GetMousePosition(), temp_action)
        } else if rl.IsMouseButtonReleased(.LEFT) {
            if (state.tool_start_position != nil) {
                action : ^Action = &state.undo_history[len(state.undo_history)-1]
                tooltip = wall_tool(state, tile_map, rl.GetMousePosition(), action)
            }
        } else {
            highligh_current_tile_intersection = true
        }
        icon = .ICON_BOX_GRID_BIG
    }
    case .EDIT_TOKEN: {
        #partial switch selected_widget {
        case .MAP: {
            if rl.IsKeyPressed(.TAB) {
                ids := make([dynamic]u64, context.temp_allocator)
                for token_id in state.tokens {
                    append(&ids, token_id)
                }

                if token != nil {
                    for token_id, index in ids {
                        if token.id == token_id {
                            if index + 1 >= len(ids) {
                                // if we have gone to the end, focus the first one
                                next_token_pos := tile_map_to_screen_coord(state.tokens[ids[0]].position, state, tile_map)
                                rl.SetMousePosition(i32(next_token_pos.x), i32(next_token_pos.y))
                            } else {
                                next_token_pos := tile_map_to_screen_coord(state.tokens[ids[index+1]].position, state, tile_map)
                                rl.SetMousePosition(i32(next_token_pos.x), i32(next_token_pos.y))
                            }
                            break
                        }
                    }
                } else {
                    // if we don't have a token selected focus the first one
                    next_token_pos := tile_map_to_screen_coord(state.tokens[ids[0]].position, state, tile_map)
                    rl.SetMousePosition(i32(next_token_pos.x), i32(next_token_pos.y))
                }
            } else if token != nil {
                key := rl.GetKeyPressed()
                if key == .DELETE {
                    remove_token_by_id_from_initiative(state, token.id)
                    delete_key(&state.tokens, token.id)
                    append(&state.undo_history, Action{})
                    action : ^Action = &state.undo_history[len(state.undo_history)-1]
                    append(&action.token_deleted, token^)
                } else {
                    if rl.IsKeyDown(.BACKSPACE) {
                        key = .BACKSPACE
                    }
                    byte : u8 = u8(key)
                    if byte != 0 {
                        builder : strings.Builder
                        strings.write_string(&builder, token.name)
                        #partial switch key {
                        case .BACKSPACE:
                            strings.pop_rune(&builder)
                        case .MINUS: {
                            if token.size > 1 {
                                token.size -= 1
                            }
                        }
                        case .EQUAL: {
                            if token.size < 10 && (rl.IsKeyDown(.RIGHT_SHIFT) || rl.IsKeyDown(.LEFT_SHIFT)) {
                                token.size += 1
                            }
                        }
                        case .RIGHT_SHIFT, .LEFT_SHIFT: {
                        }
                        case:
                            strings.write_byte(&builder, byte)
                        }
                        delete(token.name)
                        token.name = strings.to_string(builder)
                        state.key_consumed = true
                        lowercase_name := strings.to_lower(token.name, context.temp_allocator)
                        for key, &value in state.textures {
                            if strings.has_prefix(lowercase_name, key) {
                                token.texture = &value
                            }
                        }
                    }
                }
            } else if rl.IsMouseButtonPressed(.LEFT) {
                t := make_token(state.max_entity_id, mouse_tile_pos, state.selected_color)
                state.tokens[t.id] =  t
                if state.initiative_to_tokens[t.initiative] == nil {
                    state.initiative_to_tokens[t.initiative] = make([dynamic]u64)
                }
                append(&state.initiative_to_tokens[t.initiative], t.id)
                append(&state.undo_history, Action{})
                action : ^Action = &state.undo_history[len(state.undo_history)-1]
                append(&action.token_created, state.max_entity_id)
                state.max_entity_id += 1
            } else {
                c := state.selected_color
                c.a = 90
                state.tokens[0] = make_token(0, mouse_tile_pos, c, " ")
                append(&state.temp_actions, make_action(context.temp_allocator))
                temp_action : ^Action = &state.temp_actions[len(state.temp_actions)-1]
                append(&temp_action.token_created, 0)
            }
            icon = .ICON_PLAYER
        }
        case .INITIATIVE: {
            if rl.IsMouseButtonDown(.LEFT) {
                move_initiative_token_tool(state, rl.GetMousePosition(), nil)
            } else if rl.IsMouseButtonReleased(.LEFT) {
                if (state.tool_start_position != nil) {
                    action : ^Action = &state.undo_history[len(state.undo_history)-1]
                    move_initiative_token_tool(state, rl.GetMousePosition(), action)
                }
                state.selected_token = 0
            }
            icon = .ICON_SHUFFLE
        }
        }
    }
    case .HELP: {
    }
    }

    if rl.IsMouseButtonReleased(.LEFT) {
        if (state.tool_start_position != nil) {
            state.tool_start_position = nil
        }
    }

    if !state.key_consumed {
        for c in config {
            triggered : bool = true
            for trigger in c.key_triggers {
                trigger_proc : proc "c" (rl.KeyboardKey) -> bool
                switch trigger.action {
                case .DOWN: {
                    trigger_proc = rl.IsKeyDown
                }
                case .RELEASED: {
                    trigger_proc = rl.IsKeyReleased
                }
                case .PRESSED: {
                    trigger_proc = rl.IsKeyPressed
                }
                }
                triggered = triggered && trigger_proc(trigger.binding)
            }
            if triggered {
                c.action(state)
                break
            }
        }
    }

    state.camera_pos = recanonicalize_position(tile_map, state.camera_pos)

    tile_map.tile_side_in_pixels += i32(rl.GetMouseWheelMove())
    tile_map.tile_side_in_pixels = math.max(5, tile_map.tile_side_in_pixels)
    tile_map.feet_to_pixels = f32(tile_map.tile_side_in_pixels) / tile_map.tile_side_in_feet
    tile_map.pixels_to_feet = tile_map.tile_side_in_feet / f32(tile_map.tile_side_in_pixels)

    screen_center : rl.Vector2 = {f32(state.screen_width), f32(state.screen_height)} * 0.5

    // draw tile map
    tiles_needed_to_fill_half_of_screen := screen_center / f32(tile_map.tile_side_in_pixels)
    for row_offset : i32 = i32(math.floor(-tiles_needed_to_fill_half_of_screen.y)); row_offset <= i32(math.ceil(tiles_needed_to_fill_half_of_screen.y)); row_offset += 1 {
        cen_y : f32 = screen_center.y - tile_map.feet_to_pixels * state.camera_pos.rel_tile.y + f32(row_offset * tile_map.tile_side_in_pixels)
        min_y : f32 = cen_y - 0.5 * f32(tile_map.tile_side_in_pixels)

        for column_offset : i32 = i32(math.floor(-tiles_needed_to_fill_half_of_screen.x)); column_offset <= i32(math.ceil(tiles_needed_to_fill_half_of_screen.x)); column_offset += 1 {
            current_tile: [2]u32
            current_tile.x = (state.camera_pos.abs_tile.x) + u32(column_offset)
            current_tile.y = (state.camera_pos.abs_tile.y) + u32(row_offset)

            current_tile_value : Tile = get_tile(tile_map, current_tile)

            if highligh_current_tile {
                if (current_tile.y == mouse_tile_pos.abs_tile.y) && (current_tile.x == mouse_tile_pos.abs_tile.x) {
                    current_tile_value = tile_make(color_over(state.selected_color, current_tile_value.color))
                }
            }

            // Calculate tile position on screen
            cen_x : f32 = screen_center.x - tile_map.feet_to_pixels * state.camera_pos.rel_tile.x + f32(column_offset * tile_map.tile_side_in_pixels)
            min_x : f32 = cen_x - 0.5 * f32(tile_map.tile_side_in_pixels)
            rl.DrawRectangleV({min_x, min_y},
                             {f32(tile_map.tile_side_in_pixels), f32(tile_map.tile_side_in_pixels)},
                             current_tile_value.color.xyzw)

            if Direction.TOP in current_tile_value.walls {
                //TODO(amatej): use DrawLineEx if we want to do diagonals
                rl.DrawRectangleV({min_x, min_y},
                                 {f32(tile_map.tile_side_in_pixels), f32(2)},
                                 current_tile_value.wall_colors[Direction.TOP].xyzw)
            }
            if Direction.LEFT in current_tile_value.walls {
                rl.DrawRectangleV({min_x, min_y},
                                 {f32(2), f32(tile_map.tile_side_in_pixels)},
                                 current_tile_value.wall_colors[Direction.LEFT].xyzw)
            }
        }

        if (state.draw_grid) {
            rl.DrawLineV({0, min_y}, {f32(state.screen_width), min_y}, {0,0,0,20})
        }
    }

    // draw tokens on map
    for _, &token in state.tokens {
        pos: rl.Vector2 = tile_map_to_screen_coord(token.position, state, tile_map)
        if (token.texture != nil) {
            tex_pos, scale := get_token_texture_pos_size(tile_map, state, token)
            rl.DrawTextureEx(token.texture^, tex_pos, 0, scale, rl.WHITE)
        } else {
            rl.DrawCircleV(get_token_circle(tile_map, state, token), token.color.xyzw)
        }
        rl.DrawText(get_token_name_temp(&token), i32(pos.x)-tile_map.tile_side_in_pixels/2, i32(pos.y)+tile_map.tile_side_in_pixels/2, 18, rl.WHITE)
        if (token.moved != 0) {
            rl.DrawText(u64_to_cstring(u64(f32(token.moved) * tile_map.tile_side_in_feet)), i32(pos.x)-tile_map.tile_side_in_pixels, i32(pos.y)-tile_map.tile_side_in_pixels, 28, rl.WHITE)
        }
    }

    if highligh_current_tile_intersection {
        half := tile_map.tile_side_in_feet/2
        m := mouse_tile_pos
        m.rel_tile.x = m.rel_tile.x >= 0 ? half : -half
        m.rel_tile.y = m.rel_tile.y >= 0 ? half : -half
        size : f32 = f32(tile_map.tile_side_in_pixels)
        cross_pos := tile_map_to_screen_coord(m, state, tile_map)
        cross_pos += m.rel_tile * tile_map.feet_to_pixels
        rl.DrawRectangleV(cross_pos - {1, size/2},
                         {2, size},
                         {255, 255, 255, 255})
        rl.DrawRectangleV(cross_pos - {size/2, 1},
                         {size, 2},
                         {255, 255, 255, 255})
    }

    // draw initiative tracker
    if (state.draw_initiative) {
        rl.DrawRectangleGradientEx(state.gui_rectangles[.INITIATIVE], {40,40,40,45}, {40,40,40,45}, {0,0,0,0}, {0,0,0,0})
        row_offset : i32 = 10
        for i : i32 = 1; i < INITIATIVE_COUNT; i += 1 {
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
                    token_size :=  f32(token.size) * 4 + 10
                    half_of_this_row := i32(token_size + 3)
                    if (token.texture != nil) {
                        pos : rl.Vector2 = {20, f32(row_offset)}
                        // We assume token textures are squares
                        scale := f32(22 + token.size*8)/f32(token.texture.width)
                        rl.DrawTextureEx(token.texture^, pos, 0, scale, rl.WHITE)
                    } else {
                        rl.DrawCircleV({30 + token_size/2, f32(row_offset + half_of_this_row)}, f32(token_size), token.color.xyzw)
                    }
                    rl.DrawText(get_token_name_temp(&token), i32(30 + token_size + 15), row_offset + i32(token_size) - 4, 18, rl.WHITE)
                    row_offset += 2 * half_of_this_row
                }
            }
            rl.DrawRectangleGradientH(0, row_offset, 100, 2, {40,40,40,155}, {0,0,0,0})
        }
    }

    if (state.draw_grid) {
        for column_offset : i32 = i32(math.floor(-tiles_needed_to_fill_half_of_screen.x)); column_offset <= i32(math.ceil(tiles_needed_to_fill_half_of_screen.x)); column_offset += 1 {
            cen_x : f32 = screen_center.x - tile_map.feet_to_pixels * state.camera_pos.rel_tile.x + f32(column_offset * tile_map.tile_side_in_pixels)
            min_x : f32 = cen_x - 0.5 * f32(tile_map.tile_side_in_pixels)
            min_x = math.max(0, min_x)
            rl.DrawLineV({min_x, 0}, {min_x, f32(state.screen_height)}, {0,0,0,20})
        }
    }

    if state.active_tool == .COLOR_PICKER {
        rl.GuiColorBarAlpha(state.gui_rectangles[.COLORBARALPHA], "color picker alpha", &state.selected_alpha)
        rl.GuiColorPicker(state.gui_rectangles[.COLORPICKER], "color picker", (^rl.Color)(&state.selected_color))
        state.selected_color = rl.ColorAlpha(state.selected_color.xyzw, state.selected_alpha).xyzw
    }

    if state.active_tool == .HELP {
        rl.DrawRectangleV({30, 30},
                         {f32(state.screen_width) - 60, f32(state.screen_height) - 60},
                         {0, 0, 0, 155})
        offset : i32 = 100
        for c in config {
            builder := strings.builder_make(context.temp_allocator)
            for trigger in c.key_triggers {
                strings.write_string(&builder, fmt.aprintf("%s (%s) + ", trigger.binding, trigger.action, allocator=context.temp_allocator))
            }
            strings.pop_rune(&builder)
            strings.pop_rune(&builder)
            rl.DrawText(strings.to_cstring(&builder), 100, offset, 18, rl.WHITE)
            if c.icon != nil {
                rl.GuiDrawIcon(c.icon, 500, offset, 1, rl.WHITE)
            }
            rl.DrawText(strings.clone_to_cstring(c.help, context.temp_allocator), 540, offset, 18, rl.WHITE)
            offset += 30

        }
    }

    mouse_pos: [2]f32 = rl.GetMousePosition()
    rl.GuiDrawIcon(icon, i32(mouse_pos.x) - 4, i32(mouse_pos.y) - 30, 2, rl.WHITE)
    if (tooltip != nil) {
        rl.DrawText(tooltip.?, i32(mouse_pos.x) + 10, i32(mouse_pos.y) + 30, 28, rl.WHITE)
    }

    // Before ending the loop revert the last action from history if it is temp
    for _, index in state.temp_actions {
        undo_action(state, tile_map, &state.temp_actions[index])
    }
    clear(&state.temp_actions)

    rl.EndDrawing()
    free_all(context.temp_allocator)
}

shutdown :: proc() {
    os.write_entire_file("./save", serialize_to_bytes())

    rl.CloseWindow()
    for name, _ in state.textures {
        delete(name)
    }
    delete(state.textures)
    delete(state.gui_rectangles)
    for _, &token_ids in state.initiative_to_tokens {
        delete(token_ids)
    }
    delete(state.initiative_to_tokens)
    for _, &token in state.tokens {
        delete_token(&token)
    }
    delete(state.tokens)
    for _, index in state.undo_history {
        delete_action(&state.undo_history[index])
    }
    delete(state.undo_history)
    for key, _ in tile_map.tile_chunks {
        delete(tile_map.tile_chunks[key].tiles)
    }
    delete(tile_map.tile_chunks)

    free(state)
    free(tile_map)

}

// In a web build, this is called when browser changes size. Remove the
// `rl.SetWindowSize` call if you don't want a resizable game.
parent_window_size_changed :: proc(w, h: int) {
	rl.SetWindowSize(i32(w), i32(h))
}

list_files_in_dir :: proc(path: string) -> []string {
    f, err := os.open(path)
    defer os.close(f)
    if err != os.ERROR_NONE {
        fmt.eprintln("Could not open directory for reading", err)
        os.exit(1)
    }
    fis: []os.File_Info
    defer os.file_info_slice_delete(fis)
    fis, err = os.read_dir(f, -1) // -1 reads all file infos
    if err != os.ERROR_NONE {
        fmt.eprintln("Could not read directory", err)
        os.exit(2)
    }

    res := make([dynamic]string, context.temp_allocator)

    for fi in fis {
        _, name := filepath.split(fi.fullpath)
        if !fi.is_dir {
            append(&res, strings.clone(name, allocator=context.temp_allocator))
        }
    }

    return res[:]
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
    for !rl.WindowShouldClose() {
        update()
    }
    shutdown()
}
