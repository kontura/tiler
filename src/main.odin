package tiler

import "base:runtime"
import "core:fmt"
import "core:hash/xxhash"
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

HOVER_COLOR: [4]u8 : {200, 0, 0, 255}
HOVER_TRANSPARENT_COLOR: [4]u8 : {200, 0, 0, 180}

INITIATIVE_COUNT: i32 : 50
PLAYERS := [?]string{"Wesley", "AR100", "Daren", "Max", "Mardun", "Rodion"}

PLATFORM_WEB :: #config(PLATFORM_WEB, false)

when PLATFORM_WEB {
    GLSL_VERSION :: "100"
} else {
    GLSL_VERSION :: "330"
}

DebugMode :: enum {
    OFF,
    ACTIONS,
    TOKENS,
    PERF,
}

when ODIN_DEBUG {
    GRAPHS_LEN :: 256

    GraphType :: enum {
        UPDATE,
        RENDER,
    }

    GraphTypeToColor: [GraphType][4]u8 = {
        .UPDATE = {0, 255, 0, 255},
        .RENDER = {255, 0, 0, 255},
    }

    Graphs :: struct {
        frame_index: i32,
        values:      [GraphType][GRAPHS_LEN]time.Duration,
    }

    graphs: Graphs
}

//TODO(amatej): make GameState and TileMap not global
GameState :: struct {
    tile_map:                   ^TileMap,
    last_tile_side_in_pixels:   i32,
    screen_width:               i32,
    screen_height:              i32,
    camera_pos:                 TileMapPosition,
    selected_color:             [4]u8,
    selected_wall_color:        [4]u8,
    selected_alpha:             f32,
    selected_tokens:            [dynamic]u64,
    last_selected_token_id:     u64,
    draw_grid:                  bool,
    draw_grid_mask:             bool,
    grid_mask:                  rl.RenderTexture,
    grid_tex:                   rl.RenderTexture,
    tiles_tex:                  rl.RenderTexture,
    grid_shader:                rl.Shader,
    //TODO(amatej): Improve shader management, these locations are not nice
    mask_loc:                   i32,
    wall_color_loc:             i32,
    tiles_loc:                  i32,
    tile_pix_size_loc:          i32,
    camera_offsret_loc:         i32,
    draw_initiative:            bool,
    active_tool:                Tool,
    selected_options:           ToolOptionsSet,
    previous_tool:              Maybe(Tool),
    last_left_button_press_pos: Maybe([2]f32),
    move_start_position:        Maybe(TileMapPosition),
    temp_actions:               [dynamic]Action,
    needs_sync:                 bool,
    // We need image name "string" from peer with id "u64"
    needs_images:               map[u64]string,
    mobile:                     bool,
    previous_touch_dist:        f32,
    previous_touch_pos:         [2]f32,
    previous_touch_count:       i32,
    timeout:                    uint,
    timeout_string:             string,
    debug:                      DebugMode,
    should_run:                 bool,
    undone:                     int,
    bg_id:                      string,
    bg_pos:                     TileMapPosition,
    bg_scale:                   f32,
    bg_snap:                    [3]Maybe([2]f32),

    // permanent state
    textures:                   map[string]rl.Texture2D,
    images:                     map[string]rl.Image,
    done_circle_actions:        [dynamic]int,

    //TODO(amatej): check if the tool actually does any color change before recoding
    //              undoing non-color changes does nothing
    undo_history:               [dynamic]Action,
    tokens:                     map[u64]Token,
    initiative_to_tokens:       map[i32][dynamic]u64,
    path:                       string,
    room_id:                    u64,
    offline:                    bool,
    particles:                  [1024]Particle,
    particle_index:             u32,
    id:                         u64,
    menu_items:                 [dynamic]string,
    selected_index:             int,

    // light
    light:                      LightInfo,
    light_pos:                  TileMapPosition,
    light_mask:                 rl.RenderTexture,

    // network
    socket_ready:               bool,
    peers:                      map[u64]PeerState,

    // UI
    root:                       ^UIWidget,
    widget_cache:               map[string]UIWidget,

    // This random generator is used to generate the same random info
    // each frame
    frame_deterministic_rng:    runtime.Random_Generator,
    frame_deterministic_state:  runtime.Default_Random_State,
}

Widget :: enum {
    MAP,
    COLORPICKER,
    COLORBARHUE,
    COLORBARALPHA,
    INITIATIVE,
    TOOLMENU,
    TOOLMENU_OPTIONS,
}

draw_quad_ordered :: proc(v1, v2, v3, v4: [2]f32, color: [4]u8) {
    rl.DrawTriangle(v1, v2, v3, color.xyzw)
    rl.DrawTriangle(v3, v4, v1, color.xyzw)
}

draw_triangle :: proc(v1, v2, v3: [2]f32, color: [4]u8) {
    area := (v2.x - v1.x) * (v3.y - v1.y) - (v3.x - v1.x) * (v2.y - v1.y)
    if area > 0 {
        rl.DrawTriangle(v3, v2, v1, color.xyzw)
    } else {
        rl.DrawTriangle(v3, v1, v2, color.xyzw)
    }
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

show_message :: proc(state: ^GameState, str: string, timeout: uint) {
    state.timeout = timeout
    delete(state.timeout_string)
    state.timeout_string = strings.clone(str)
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
    closest_dist := f32(tile_map.tile_side_in_pixels)
    if state.mobile {
        closest_dist *= 2
    }
    for _, &token in state.tokens {
        if token.alive && token.id != 0 {
            center, _ := get_token_circle(tile_map, state, &token)
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

load_save_override :: proc(state: ^GameState, path := "./tiler_save") -> bool {
    data, ok := read_entire_file(path, context.temp_allocator)
    if ok {
        s: Serializer
        serializer_init_reader(&s, data)
        actions := make([dynamic]Action, allocator = context.allocator)
        serialize(&s, &s.version)
        serialize(&s, &actions)
        images: map[string][dynamic]u8
        serialize(&s, &images)
        for img_id, img_data in images {
            save_image(state, img_id, img_data[:])
            delete(img_data)
            delete(img_id)
        }
        delete(images)

        if len(actions) > 0 {
            // undo and delete current actions
            for i := len(state.undo_history) - 1; i >= 0; i -= 1 {
                action := &state.undo_history[i]
                undo_action(state, tile_map, action)
            }
            for i := 0; i < len(state.undo_history); i += 1 {
                delete_action(&state.undo_history[i])
            }
            delete(state.undo_history)
            tokens_reset(state)

            // set and redo loaded actions
            state.undo_history = actions
            for i := 0; i < len(state.undo_history); i += 1 {
                action := &state.undo_history[i]
                redo_action(state, tile_map, action)
            }

            return true
        }
    }

    return false
}

store_save :: proc(state: ^GameState, path := "./tiler_save") -> bool {
    save_data := serialize_actions(state.undo_history[:], context.temp_allocator)
    s: Serializer
    serializer_init_writer(&s, allocator = context.temp_allocator)
    actions := state.undo_history[:]
    serialize(&s, &s.version)
    serialize(&s, &actions)
    images := make(map[string][dynamic]u8, allocator = context.temp_allocator)
    for img_id, _ in state.images {
        image_data := serialize_image(state, img_id, context.temp_allocator)
        images[img_id] = image_data
    }
    serialize(&s, &images)

    return write_entire_file(path, s.data[:])
}

serialize_image :: proc(state: ^GameState, img_id: string, allocator: mem.Allocator) -> [dynamic]u8 {
    img, ok := state.images[img_id]
    if ok {
        size: i32
        data_ptr := rl.ExportImageToMemory(img, ".png", &size)
        data_slice := slice.bytes_from_ptr(data_ptr, int(size))
        defer rl.MemFree(data_ptr)
        return slice.clone_to_dynamic(data_slice, allocator = allocator)
    }

    return {}
}

save_image :: proc(state: ^GameState, img_id: string, img_data: []u8) {
    state.images[strings.clone(img_id)] = rl.LoadImageFromMemory(".png", raw_data(img_data), i32(len(img_data)))
    state.textures[strings.clone(img_id)] = rl.LoadTextureFromImage(state.images[img_id])
}

set_background :: proc(state: ^GameState, image_id: string, author_id: u64) {
    delete(state.bg_id)
    state.bg_id = strings.clone(image_id)
    _, ok := state.images[image_id]
    if !ok {
        if len(image_id) > 0 {
            state.needs_images[author_id] = strings.clone(image_id)
        }
    }
}

add_background :: proc(data: [^]u8, data_len, width: i32, height: i32) {
    d: []u8 = data[:data_len]
    append(&state.undo_history, make_action(.LOAD_BACKGROUND))
    action: ^Action = &state.undo_history[len(state.undo_history) - 1]
    action.new_name = strings.clone("bg")
    state.images[strings.clone(action.new_name)] = rl.LoadImageFromMemory(".png", raw_data(d), data_len)
    state.textures[strings.clone(action.new_name)] = rl.LoadTextureFromImage(state.images[action.new_name])
    set_background(state, action.new_name, state.id)
    finish_last_undo_history_action(state)
    state.needs_sync = true
}

set_selected_token_texture :: proc(data: [^]u8, data_len, width: i32, height: i32) {
    if len(state.selected_tokens) == 1 {
        token := &state.tokens[state.selected_tokens[0]]
        if len(token.name) > 0 {
            append(&state.undo_history, make_action(.EDIT_TOKEN_TEXTURE))
            action: ^Action = &state.undo_history[len(state.undo_history) - 1]
            // Move lowecase_name ownership to action
            action.new_name = strings.to_lower(token.name)
            action.token_id = token.id
            finish_last_undo_history_action(state)

            d: []u8 = data[:data_len]
            save_image(state, action.new_name, d)
        } else {
            show_message(state, "To set token image it needs a name.", 60)
        }
    }
}

highlight_current_tile :: proc(state: ^GameState, tile_map: ^TileMap, mouse_tile_pos: TileMapPosition) {
    append(&state.temp_actions, make_action(.BRUSH, context.temp_allocator))
    temp_action: ^Action = &state.temp_actions[len(state.temp_actions) - 1]
    old_tile := get_tile(tile_map, mouse_tile_pos.abs_tile)
    new_tile := old_tile
    new_tile.color = state.selected_color
    temp_action.tile_history[mouse_tile_pos.abs_tile] = tile_xor(&old_tile, &new_tile)
    set_tile(tile_map, mouse_tile_pos.abs_tile, new_tile)
}

game_state_init :: proc(state: ^GameState, mobile: bool, width: i32, height: i32, path: string) {
    state.camera_pos.abs_tile.x = 100
    state.camera_pos.abs_tile.y = 100
    state.camera_pos.rel_tile.x = 0.0
    state.camera_pos.rel_tile.y = 0.0
    state.screen_height = height
    state.screen_width = width
    state.draw_grid = true
    state.draw_grid_mask = !mobile
    state.draw_initiative = true
    state.active_tool = Tool.MOVE_TOKEN
    // Ensure different peers have different ids, without
    // this reset all peers would have the same id
    // and we would always start with the same colors
    // (on the web).
    rand.reset(u64(time.time_to_unix(time.now())))
    state.selected_color.a = 255
    state.selected_color.r = u8(rand.int_max(255))
    state.selected_color.g = u8(rand.int_max(255))
    state.selected_color.b = u8(rand.int_max(255))
    state.selected_wall_color = state.selected_color + 90
    state.selected_wall_color.a = 255
    for state.id == 0 {
        state.id = rand.uint64()
    }
    state.selected_alpha = 1
    state.needs_sync = true
    state.mobile = mobile
    state.bg_scale = 1
    state.should_run = true
    // Token 0 is reserved, it is a temp token used for previews
    state.tokens[0] = Token {
        id        = 0,
        name      = strings.clone(" "),
        size      = 1,
        draw_size = 1,
    }
    state.path = path
    room_hash_state: xxhash.XXH3_state
    xxhash.XXH3_init_state(&room_hash_state)
    xxhash.XXH3_64_update(&room_hash_state, transmute([]u8)(state.path))
    state.room_id = xxhash.XXH3_64_digest(&room_hash_state)

    state.bg_pos.rel_tile = 2.5
    state.bg_pos.abs_tile = 100

    // light
    state.light = {
        rl.LoadRenderTexture(width, height),
        rl.LoadRenderTexture(width, height),
        2000000,
        true,
        true,
        1,
        0.2,
    }
    state.light_mask = rl.LoadRenderTexture(width, height)
    state.grid_mask = rl.LoadRenderTexture(width, height)
    state.grid_tex = rl.LoadRenderTexture(width, height)
    state.tiles_tex = rl.LoadRenderTexture(width, height)

    builder := strings.builder_make(context.temp_allocator)
    strings.write_string(&builder, "assets/shaders/")
    strings.write_string(&builder, GLSL_VERSION)
    strings.write_string(&builder, "_mask.fs")

    state.grid_shader = rl.LoadShader(nil, strings.to_cstring(&builder))
    state.mask_loc = rl.GetShaderLocation(state.grid_shader, "mask")
    state.wall_color_loc = rl.GetShaderLocation(state.grid_shader, "wall_color")
    state.tiles_loc = rl.GetShaderLocation(state.grid_shader, "tiles")
    state.tile_pix_size_loc = rl.GetShaderLocation(state.grid_shader, "tile_pix_size")
    state.camera_offsret_loc = rl.GetShaderLocation(state.grid_shader, "camera_offset")

    state.frame_deterministic_state = rand.create(u64(time.time_to_unix(time.now())))
    state.frame_deterministic_rng = rand.default_random_generator(&state.frame_deterministic_state)
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
    tile_map.dirty = true
}

init :: proc(path: string = "root", mobile := false) {
    rl.SetConfigFlags({.WINDOW_RESIZABLE, .VSYNC_HINT})
    rl.InitWindow(INIT_SCREEN_WIDTH, INIT_SCREEN_HEIGHT, "Tiler")

    state = new(GameState)
    game_state_init(state, mobile, rl.GetScreenWidth(), rl.GetScreenHeight(), path)

    tile_map = new(TileMap)
    tile_map_init(tile_map, mobile)
    state.last_tile_side_in_pixels = tile_map.tile_side_in_pixels
    state.tile_map = tile_map

    // Load all tokens from assets dir
    for file_name in list_files_in_dir("assets/textures") {
        split := strings.split(file_name, ".", allocator = context.temp_allocator)
        if split[1] == "png" {
            join := strings.join({"assets/textures/", file_name}, "", allocator = context.temp_allocator)
            state.textures[strings.clone(split[0])] = rl.LoadTexture(
                strings.clone_to_cstring(join, context.temp_allocator),
            )
        }
    }
}

update :: proc() {
    mouse_pos: [2]f32 = rl.GetMousePosition()
    mouse_tile_pos: TileMapPosition = screen_coord_to_tile_map(mouse_pos, state, tile_map)
    tooltip: Maybe(cstring) = nil
    highligh_current_tile_intersection := false
    //TODO(amatej): somehow use the icons configured from config.odin,
    //              but it is complicated by colorpicker
    icon: rl.GuiIconName

    update_duration: time.Duration
    {
        time.SCOPED_TICK_DURATION(&update_duration)
        if state.screen_height != rl.GetScreenHeight() || state.screen_width != rl.GetScreenWidth() {
            state.screen_height = rl.GetScreenHeight()
            state.screen_width = rl.GetScreenWidth()
            state.light.light_wall_mask = rl.LoadRenderTexture(state.screen_width, state.screen_height)
            state.light.light_token_mask = rl.LoadRenderTexture(state.screen_width, state.screen_height)
            state.light_mask = rl.LoadRenderTexture(state.screen_width, state.screen_height)
            state.grid_mask = rl.LoadRenderTexture(state.screen_width, state.screen_height)
            state.grid_tex = rl.LoadRenderTexture(state.screen_width, state.screen_height)
            state.tiles_tex = rl.LoadRenderTexture(state.screen_width, state.screen_height)
            for _, &token in state.tokens {
                l, ok := &token.light.?
                if ok {
                    l.light_wall_mask = rl.LoadRenderTexture(state.screen_width, state.screen_height)
                    l.light_token_mask = rl.LoadRenderTexture(state.screen_width, state.screen_height)
                }
            }
            set_dirty_token_for_all_lights(state)
            tile_map.dirty = true
        }

        state.temp_actions = make([dynamic]Action, context.temp_allocator)
        key_consumed := false

        particles_update(state, tile_map, rl.GetFrameTime())

        if !state.mobile && state.bg_snap[0] == nil {
            // Mouse clicks
            if rl.IsMouseButtonPressed(.LEFT) {
                state.last_left_button_press_pos = mouse_pos
            } else if rl.IsMouseButtonDown(.RIGHT) {
                if rl.GetMouseDelta() / f32(tile_map.tile_side_in_pixels) != 0 {
                    state.camera_pos.rel_tile -= rl.GetMouseDelta() / f32(tile_map.tile_side_in_pixels) * 8
                    set_dirty_token_for_all_lights(state)
                    tile_map.dirty = true
                }
            }
            if rl.GetMouseWheelMoveV().y * 1.5 != 0 {
                if len(state.selected_tokens) == 1 && state.active_tool == .EDIT_TOKEN {
                    clear_selected_tokens(state)
                } else {
                    if math.abs(f32(tile_map.tile_side_in_pixels) - f32(state.last_tile_side_in_pixels)) < EPS {
                        tile_map.tile_side_in_pixels += i32(rl.GetMouseWheelMoveV().y * 1.5)
                        state.last_tile_side_in_pixels = tile_map.tile_side_in_pixels
                        set_dirty_token_for_all_lights(state)
                        tile_map.dirty = true
                    }
                }
            }
        }
        touch_count := rl.GetTouchPointCount()

        if len(state.selected_tokens) == 1 && state.active_tool == .EDIT_TOKEN {
            token := &state.tokens[state.selected_tokens[0]]

            current_dist := tile_pos_distance(tile_map, token.position, state.camera_pos)
            new_dist := exponential_smoothing(0, current_dist)
            tile_vec := tile_pos_difference(token.position, state.camera_pos)
            tile_vec_normal := tile_vec_div(tile_vec, current_dist)
            tile_vec_multed := tile_vec_mul(tile_vec_normal, current_dist - new_dist)
            state.camera_pos = recanonicalize_position(
                tile_map,
                tile_pos_add_tile_vec(state.camera_pos, tile_vec_multed),
            )

            tile_map.tile_side_in_pixels = i32(exponential_smoothing(200, f32(tile_map.tile_side_in_pixels)))

            set_dirty_token_for_all_lights(state)
            tile_map.dirty = true
        } else if math.abs(f32(tile_map.tile_side_in_pixels) - f32(state.last_tile_side_in_pixels)) > EPS {
            tile_map.tile_side_in_pixels = i32(
                exponential_smoothing(f32(state.last_tile_side_in_pixels), f32(tile_map.tile_side_in_pixels)),
            )
            set_dirty_token_for_all_lights(state)
            tile_map.dirty = true
        }


        // Build UI widgets
        {
            state.root = ui_make_widget(state, nil, {.HOVERABLE}, "tile_map")
            state.root.rect = {0, 0, f32(state.screen_width), f32(state.screen_height)}

            if state.draw_initiative {
                initiative_widget := ui_make_widget(
                    state,
                    state.root,
                    {.DRAWBACKGROUNDGRADIENT, .HOVERABLE},
                    "initiative",
                )
                initiative_widget.rect = {0, 0, 120, f32(state.screen_height)}
                if ui_widget_interaction(initiative_widget, mouse_pos).hovering && state.active_tool == .EDIT_TOKEN {
                    if rl.IsMouseButtonDown(.LEFT) {
                        append(&state.temp_actions, make_action(.EDIT_TOKEN_INITIATIVE, context.temp_allocator))
                        temp_action: ^Action = &state.temp_actions[len(state.temp_actions) - 1]
                        move_initiative_token_tool(
                            state,
                            state.last_left_button_press_pos.?.y,
                            mouse_pos.y,
                            temp_action,
                        )
                    } else if rl.IsMouseButtonReleased(.LEFT) {
                        if (state.last_left_button_press_pos != nil) {
                            append(&state.undo_history, make_action(.EDIT_TOKEN_INITIATIVE))
                            action: ^Action = &state.undo_history[len(state.undo_history) - 1]
                            move_initiative_token_tool(
                                state,
                                state.last_left_button_press_pos.?.y,
                                mouse_pos.y,
                                action,
                            )
                            state.needs_sync = true
                            finish_last_undo_history_action(state)
                        }
                    }
                    icon = .ICON_SHUFFLE
                }
            }

            allow_editing_tool_type_actions(state, tile_map, .CONE, .CONE, mouse_pos)
            allow_editing_tool_type_actions(state, tile_map, .CIRCLE, .CIRCLE, mouse_pos)
            allow_editing_tool_type_actions(state, tile_map, .RECTANGLE, .RECTANGLE, mouse_pos)

            if state.active_tool == .COLOR_PICKER {
                //TODO(amatej): remove this hack
                target_color: ^[4]u8
                if state.previous_tool.? == .WALL {
                    target_color = &state.selected_wall_color
                } else {
                    target_color = &state.selected_color
                }
                target_color^ = rl.ColorAlpha(target_color^.xyzw, state.selected_alpha).xyzw

                color_picker_widget := ui_make_widget(state, state.root, {.DRAWCOLORPICKER}, "colorpicker")
                color_picker_widget.rect = {f32(state.screen_width - 230), 10, 200, 200}
                color_picker_widget.colorpicker_color = target_color

                color_bar_hue_widget := ui_make_widget(state, state.root, {}, "colorbar_hue")
                color_bar_hue_widget.rect = {f32(state.screen_width - 30), 5, 30, 205}

                color_bar_alpha_widget := ui_make_widget(state, state.root, {.DRAWCOLORBARALPHA}, "colorbar_alpha")
                color_bar_alpha_widget.rect = {f32(state.screen_width - 230), 215, 200, 20}
                color_bar_alpha_widget.colorpicker_alpha = &state.selected_alpha
            }

            tool_menu_widget := ui_make_widget(state, state.root, {}, "tool_menu")
            for &tool, i in config_tool_menu {
                is_active_proc, is_active_ok := tool.is_active.?
                if is_active_ok {
                    id := fmt.aprint("tool menu button", i, allocator = context.temp_allocator)
                    rect := get_tool_tool_menu_rect(state, &config_tool_menu, i)
                    _, inter := ui_radio_button(state, tool_menu_widget, id, is_active_proc(state), tool.icon, rect)
                    if inter.clicked {
                        tool.action(state)
                    }
                }
                for &config, ii in tool.options {
                    cond_proc, cond_ok := config.condition.?
                    if cond_ok {
                        if !cond_proc(state) {
                            continue
                        }
                    }
                    is_active_proc, is_active_ok := config.is_active.?
                    if is_active_ok {
                        id := fmt.aprint("tool config menu button", i, ii, allocator = context.temp_allocator)
                        rect := get_tool_tool_menu_rect(state, &config_tool_menu, i, ii)
                        _, inter_inter := ui_radio_button(
                            state,
                            tool_menu_widget,
                            id,
                            is_active_proc(state),
                            config.icon,
                            rect,
                        )
                        if inter_inter.clicked {
                            config.action(state)
                        }
                    }
                }
            }

            draw_selected_color, draw_selected_wall_color: bool
            #partial switch state.active_tool {
            case .RECTANGLE, .CIRCLE:
                {
                    draw_selected_color = true
                    if .ADD_WALLS in state.selected_options {
                        draw_selected_wall_color = true
                    }
                }
            case .COLOR_PICKER:
                {
                    if state.previous_tool.? == .WALL {
                        draw_selected_wall_color = true
                    } else {
                        draw_selected_color = true
                    }
                }
            case .WALL:
                {
                    draw_selected_wall_color = true
                }
            case .BRUSH, .EDIT_TOKEN, .CONE:
                {
                    draw_selected_color = true
                }
            }

            if draw_selected_color {
                selected_color_widget := ui_make_widget(state, state.root, {.DRAWBACKGROUND}, "selected_color")
                selected_color_widget.background_color = state.selected_color
                rect := get_tool_tool_menu_rect(state, &config_tool_menu, 8)
                selected_color_widget.rect = {rect[0], rect[1], rect[2], rect[3]}
            }
            if draw_selected_wall_color {
                selected_wall_color_widget := ui_make_widget(
                    state,
                    state.root,
                    {.DRAWBACKGROUND},
                    "selected_wall_color",
                )
                selected_wall_color_widget.background_color = state.selected_wall_color
                rect := get_tool_tool_menu_rect(state, &config_tool_menu, 9)
                selected_wall_color_widget.rect = {rect[0], rect[1], rect[2], rect[3]}
            }

            // We are zoomed in on a token
            if len(state.selected_tokens) == 1 && state.active_tool == .EDIT_TOKEN {
                button_pos: [2]f32 = {f32(state.screen_width) - 400, 100}
                button_size: [2]f32 = {140, 50}
                token := &state.tokens[state.selected_tokens[0]]

                li_widget, light_toggle := ui_button(
                    state,
                    state.root,
                    "light",
                    .ICON_EXPLOSION,
                    {button_pos.x, button_pos.y, button_size.x, button_size.y},
                )
                li_widget.background_color = token.light != nil ? {255, 255, 255, 95} : {0, 0, 0, 255}
                if light_toggle.clicked {
                    append(&state.undo_history, make_action(.EDIT_TOKEN_LIGHT))
                    action: ^Action = &state.undo_history[len(state.undo_history) - 1]
                    action.radius = TOKEN_DEFAULT_LIGHT_RADIUS
                    action.token_id = token.id
                    if token.light != nil {
                        l := token.light.?
                        rl.UnloadRenderTexture(l.light_wall_mask)
                        rl.UnloadRenderTexture(l.light_token_mask)
                        token.light = nil
                        action.token_life = false
                    } else {
                        token.light = LightInfo {
                            rl.LoadRenderTexture(state.screen_width, state.screen_height),
                            rl.LoadRenderTexture(state.screen_width, state.screen_height),
                            TOKEN_DEFAULT_LIGHT_RADIUS,
                            true,
                            true,
                            TOKEN_SHADOW_LEN,
                            1,
                        }
                        set_dirty_token_for_all_lights(state)
                        set_dirty_wall_for_token(token)
                        action.token_life = true
                    }
                    state.needs_sync = true
                    finish_last_undo_history_action(state)
                }
                button_pos.y += 70

                // Kill button
                {
                    _, kill_widget := ui_button(
                        state,
                        state.root,
                        "kill!!",
                        .ICON_DEMON,
                        {button_pos.x, button_pos.y, button_size.x, button_size.y},
                    )
                    if kill_widget.clicked {
                        // TODO(amatej): extract this into a tool or actions?
                        l, ok := token.light.?
                        if ok {
                            rl.UnloadRenderTexture(l.light_wall_mask)
                            rl.UnloadRenderTexture(l.light_token_mask)
                            token.light = nil
                        }
                        append(&state.undo_history, make_action(.EDIT_TOKEN_LIFE))
                        action: ^Action = &state.undo_history[len(state.undo_history) - 1]
                        token_kill(state, tile_map, token, action)
                        clear_selected_tokens(state)
                        state.needs_sync = true
                        finish_last_undo_history_action(state)
                        set_dirty_token_for_all_lights(state)
                        set_dirty_wall_for_token(token)
                    }
                }
                button_pos.y += 70

                // Size buttons
                {
                    _, size_plus_widget := ui_button(
                        state,
                        state.root,
                        "size++",
                        .ICON_NONE,
                        {
                            button_pos.x + (button_size.x / 2) + 10,
                            button_pos.y,
                            (button_size.x / 2) - 10,
                            button_size.y,
                        },
                    )
                    if size_plus_widget.clicked {
                        edit_token_size(state, token, 1)
                    }
                    _, size_minus_widget := ui_button(
                        state,
                        state.root,
                        "size--",
                        .ICON_NONE,
                        {button_pos.x, button_pos.y, (button_size.x / 2) - 10, button_size.y},
                    )
                    if size_minus_widget.clicked {
                        edit_token_size(state, token, -1)
                    }
                }
                button_pos.y += 70

                img_id := len(token.texture_id) > 0 ? token.texture_id : token.name
                img_id_text := fmt.aprintf("texture_id: %s", img_id, allocator = context.temp_allocator)
                texture_id := ui_make_widget(state, state.root, {.DRAWTEXT, .DRAWBACKGROUND}, img_id_text)
                texture_id.rect = {button_pos.x, button_pos.y, button_size.x, button_size.y / 2}
                texture_id.background_color = {0, 0, 0, 255}

                button_pos.y += 70 / 2

                secs := time.time_to_unix(time.now())
                name_text: string
                if secs % 2 == 0 {
                    name_text = fmt.aprintf("name: %s|", token.name, allocator = context.temp_allocator)
                } else {
                    name_text = fmt.aprintf("name: %s", token.name, allocator = context.temp_allocator)
                }
                name_widget := ui_make_widget(state, state.root, {.DRAWTEXT, .DRAWBACKGROUND}, name_text)
                name_widget.rect = {button_pos.x, button_pos.y, button_size.x, button_size.y / 2}
                name_widget.background_color = {0, 0, 0, 255}
            }
        }

        if ui_widget_interaction(state.root, mouse_pos).hovering {
            switch state.active_tool {
            case .LIGHT_SOURCE:
                {
                    if rl.IsKeyDown(.EQUAL) {
                        state.light.radius += 1
                        state.light.dirty_wall = true
                        state.light.dirty_token = true
                    }
                    if rl.IsKeyDown(.MINUS) {
                        state.light.radius -= 1
                        state.light.dirty_wall = true
                        state.light.dirty_token = true
                    }
                    if rl.IsMouseButtonDown(.LEFT) {
                        state.light_pos = screen_coord_to_tile_map(mouse_pos, state, tile_map)
                        state.light.dirty_wall = true
                        state.light.dirty_token = true
                    }
                    icon = .ICON_CURSOR_SCALE_LEFT
                }
            case .BRUSH:
                {
                    if rl.IsMouseButtonPressed(.LEFT) {
                        append(&state.undo_history, make_action(.BRUSH))
                    } else if rl.IsMouseButtonDown(.LEFT) {
                        action: ^Action = &state.undo_history[len(state.undo_history) - 1]
                        if (!(mouse_tile_pos.abs_tile in action.tile_history)) {
                            old_tile := get_tile(tile_map, mouse_tile_pos.abs_tile)
                            new_tile := old_tile
                            new_tile.color = state.selected_color
                            action.tile_history[mouse_tile_pos.abs_tile] = tile_xor(&old_tile, &new_tile)
                            set_tile(tile_map, mouse_tile_pos.abs_tile, new_tile)
                        }
                    } else if rl.IsMouseButtonReleased(.LEFT) {
                        finish_last_undo_history_action(state)
                    }
                    icon = .ICON_PENCIL
                    highlight_current_tile(state, tile_map, mouse_tile_pos)
                }
            case .CONE:
                {
                    if rl.IsMouseButtonDown(.LEFT) {
                        append(&state.temp_actions, make_action(.CONE, context.temp_allocator))
                        temp_action: ^Action = &state.temp_actions[len(state.temp_actions) - 1]
                        tooltip = cone_tool(
                            state,
                            tile_map,
                            state.last_left_button_press_pos.?,
                            mouse_pos,
                            temp_action,
                        )
                    } else if rl.IsMouseButtonReleased(.LEFT) {
                        append(&state.undo_history, make_action(.CONE))
                        action: ^Action = &state.undo_history[len(state.undo_history) - 1]
                        tooltip = cone_tool(state, tile_map, state.last_left_button_press_pos.?, mouse_pos, action)
                        finish_last_undo_history_action(state)
                        state.needs_sync = true
                    } else {
                        highligh_current_tile_intersection = true
                    }
                    icon = .ICON_CURSOR_POINTER
                }
            case .RECTANGLE:
                {
                    icon = .ICON_BOX
                    if .ADD_WALLS in state.selected_options {
                        icon = .ICON_BOX_GRID_BIG
                    }
                    if rl.IsMouseButtonDown(.LEFT) {
                        append(&state.temp_actions, make_action(.RECTANGLE, context.temp_allocator))
                        temp_action: ^Action = &state.temp_actions[len(state.temp_actions) - 1]
                        start_mouse_tile: TileMapPosition = screen_coord_to_tile_map(
                            state.last_left_button_press_pos.?,
                            state,
                            tile_map,
                        )
                        end_mouse_tile: TileMapPosition = screen_coord_to_tile_map(mouse_pos, state, tile_map)
                        tooltip = rectangle_tool(
                            start_mouse_tile,
                            end_mouse_tile,
                            state.selected_color,
                            .ADD_WALLS in state.selected_options,
                            state.selected_wall_color,
                            .DITHERING in state.selected_options,
                            tile_map,
                            temp_action,
                        )
                    } else if rl.IsMouseButtonReleased(.LEFT) {
                        if (state.last_left_button_press_pos != nil) {
                            append(&state.undo_history, make_action(.RECTANGLE))
                            action: ^Action = &state.undo_history[len(state.undo_history) - 1]
                            start_mouse_tile: TileMapPosition = screen_coord_to_tile_map(
                                state.last_left_button_press_pos.?,
                                state,
                                tile_map,
                            )
                            end_mouse_tile: TileMapPosition = screen_coord_to_tile_map(mouse_pos, state, tile_map)
                            tooltip = rectangle_tool(
                                start_mouse_tile,
                                end_mouse_tile,
                                state.selected_color,
                                .ADD_WALLS in state.selected_options,
                                state.selected_wall_color,
                                .DITHERING in state.selected_options,
                                tile_map,
                                action,
                            )
                            state.needs_sync = true
                            finish_last_undo_history_action(state)
                        }
                    }
                    highlight_current_tile(state, tile_map, mouse_tile_pos)
                }
            case .CIRCLE:
                {
                    if rl.IsMouseButtonDown(.LEFT) {
                        append(&state.temp_actions, make_action(.CIRCLE, context.temp_allocator))
                        temp_action: ^Action = &state.temp_actions[len(state.temp_actions) - 1]
                        tooltip = circle_tool(
                            state,
                            tile_map,
                            state.last_left_button_press_pos.?,
                            mouse_pos,
                            .ADD_WALLS in state.selected_options,
                            state.selected_wall_color,
                            .DITHERING in state.selected_options,
                            temp_action,
                        )
                    } else if rl.IsMouseButtonReleased(.LEFT) {
                        if screen_coord_to_tile_map(mouse_pos, state, tile_map) !=
                           screen_coord_to_tile_map(state.last_left_button_press_pos.?, state, tile_map) {
                            append(&state.undo_history, make_action(.CIRCLE))
                            action: ^Action = &state.undo_history[len(state.undo_history) - 1]
                            tooltip = circle_tool(
                                state,
                                tile_map,
                                state.last_left_button_press_pos.?,
                                mouse_pos,
                                .ADD_WALLS in state.selected_options,
                                state.selected_wall_color,
                                .DITHERING in state.selected_options,
                                action,
                            )
                            state.needs_sync = true
                            finish_last_undo_history_action(state)
                        }
                    } else {
                        highligh_current_tile_intersection = true
                    }
                    icon = .ICON_PLAYER_RECORD
                }
            case .MOVE_TOKEN:
                {
                    // We have 3 workflows here:
                    // 1. drag and drop: no selected - press -> mouse move -> selected - release
                    // 2. pick and move: no selected - press + release -> mouse move -> selected - press + release
                    // 3. tab and move:  no selected - tab -> mouse move -> selected - press + release
                    if len(state.selected_tokens) > 0 {
                        if rl.IsMouseButtonPressed(.LEFT) || rl.IsKeyPressed(.ENTER) {
                            for token_id in state.selected_tokens {
                                token := &state.tokens[token_id]
                                start_mouse_tile, ok := state.move_start_position.?
                                if !ok {
                                    start_mouse_tile = token.position
                                }
                                token_pos_delta: [2]i32 = {
                                    i32(start_mouse_tile.abs_tile.x) - i32(mouse_tile_pos.abs_tile.x),
                                    i32(start_mouse_tile.abs_tile.y) - i32(mouse_tile_pos.abs_tile.y),
                                }
                                if mouse_tile_pos.abs_tile != token.position.abs_tile {
                                    append(&state.undo_history, make_action(.EDIT_TOKEN_POSITION))
                                    action: ^Action = &state.undo_history[len(state.undo_history) - 1]
                                    move_token_tool(state, token, tile_map, token_pos_delta, action, false)
                                    state.needs_sync = true
                                    finish_last_undo_history_action(state)
                                }
                            }
                            state.move_start_position = nil
                            if rl.IsMouseButtonPressed(.LEFT) {
                                clear_selected_tokens(state)
                            }
                        } else {
                            if rl.IsMouseButtonReleased(.LEFT) {
                                moved: bool = false
                                for token_id in state.selected_tokens {
                                    token := &state.tokens[token_id]
                                    start_mouse_tile := screen_coord_to_tile_map(
                                        state.last_left_button_press_pos.?,
                                        state,
                                        tile_map,
                                    )
                                    token_pos_delta: [2]i32 = {
                                        i32(start_mouse_tile.abs_tile.x) - i32(mouse_tile_pos.abs_tile.x),
                                        i32(start_mouse_tile.abs_tile.y) - i32(mouse_tile_pos.abs_tile.y),
                                    }
                                    if mouse_tile_pos.abs_tile != token.position.abs_tile &&
                                       start_mouse_tile.abs_tile != mouse_tile_pos.abs_tile {
                                        append(&state.undo_history, make_action(.EDIT_TOKEN_POSITION))
                                        action: ^Action = &state.undo_history[len(state.undo_history) - 1]
                                        move_token_tool(state, token, tile_map, token_pos_delta, action, true)
                                        moved = true
                                        state.needs_sync = true
                                        finish_last_undo_history_action(state)
                                        token.moved = 0
                                        // This works for only one selected token
                                        state.move_start_position = nil
                                    }
                                }
                                if moved {
                                    clear_selected_tokens(state)
                                }
                            }

                            // Temp move
                            for token_id in state.selected_tokens {
                                token := &state.tokens[token_id]
                                start_mouse_tile, ok := state.move_start_position.?
                                if !ok {
                                    start_mouse_tile = token.position
                                }
                                append(&state.temp_actions, make_action(.EDIT_TOKEN_POSITION, context.temp_allocator))
                                temp_action: ^Action = &state.temp_actions[len(state.temp_actions) - 1]
                                token_pos_delta: [2]i32 = {
                                    i32(start_mouse_tile.abs_tile.x) - i32(mouse_tile_pos.abs_tile.x),
                                    i32(start_mouse_tile.abs_tile.y) - i32(mouse_tile_pos.abs_tile.y),
                                }
                                move_token_tool(
                                    state,
                                    &state.tokens[token_id],
                                    tile_map,
                                    token_pos_delta,
                                    temp_action,
                                    true,
                                )
                            }
                        }
                    } else {
                        if rl.IsMouseButtonPressed(.LEFT) {
                            token := find_token_at_screen(tile_map, state, mouse_pos)
                            state.move_start_position = mouse_tile_pos
                            if token != nil {
                                append(&state.selected_tokens, token.id)
                            }
                        }
                    }
                    icon = .ICON_TARGET_MOVE
                }
            case .COLOR_PICKER:
                {
                    picked_color: Maybe([4]u8)
                    if rl.IsMouseButtonPressed(.LEFT) {
                        token := find_token_at_screen(tile_map, state, mouse_pos)
                        if token != nil {
                            picked_color = token.color
                        } else {
                            mouse_tile: Tile = get_tile(tile_map, mouse_tile_pos.abs_tile)
                            picked_color = mouse_tile.color
                        }
                    }

                    c, ok := picked_color.?
                    if ok {
                        if state.previous_tool.? == .WALL {
                            state.selected_wall_color = c
                        } else {
                            state.selected_color = c
                        }
                    }

                    icon = .ICON_COLOR_PICKER
                }
            case .WALL:
                {
                    if rl.IsMouseButtonDown(.LEFT) {
                        append(&state.temp_actions, make_action(.WALL, context.temp_allocator))
                        temp_action: ^Action = &state.temp_actions[len(state.temp_actions) - 1]
                        start_mouse_tile: TileMapPosition = screen_coord_to_tile_map(
                            state.last_left_button_press_pos.?,
                            state,
                            tile_map,
                        )
                        end_mouse_tile: TileMapPosition = screen_coord_to_tile_map(mouse_pos, state, tile_map)
                        tooltip = wall_tool(
                            tile_map,
                            start_mouse_tile,
                            end_mouse_tile,
                            state.selected_wall_color,
                            temp_action,
                        )
                    } else if rl.IsMouseButtonReleased(.LEFT) {
                        if (state.last_left_button_press_pos != nil) {
                            append(&state.undo_history, make_action(.WALL))
                            action: ^Action = &state.undo_history[len(state.undo_history) - 1]
                            start_mouse_tile: TileMapPosition = screen_coord_to_tile_map(
                                state.last_left_button_press_pos.?,
                                state,
                                tile_map,
                            )
                            end_mouse_tile: TileMapPosition = screen_coord_to_tile_map(mouse_pos, state, tile_map)
                            tooltip = wall_tool(
                                tile_map,
                                start_mouse_tile,
                                end_mouse_tile,
                                state.selected_wall_color,
                                action,
                            )
                            state.needs_sync = true
                            finish_last_undo_history_action(state)
                        }
                    } else if rl.IsKeyPressed(.DELETE) {
                        tile_pos: TileMapPosition = screen_coord_to_tile_map(mouse_pos, state, tile_map)
                        old_tile := get_tile(tile_map, tile_pos.abs_tile)
                        if old_tile.walls != {} {
                            new_tile := old_tile
                            new_tile.walls = {}
                            append(&state.undo_history, make_action(.WALL))
                            action: ^Action = &state.undo_history[len(state.undo_history) - 1]
                            action.tile_history[tile_pos.abs_tile] = tile_xor(&old_tile, &new_tile)
                            set_tile(tile_map, tile_pos.abs_tile, new_tile)
                            finish_last_undo_history_action(state, .DELETES)
                            state.needs_sync = true
                        }
                    } else {
                        highligh_current_tile_intersection = true
                    }
                    icon = .ICON_BOX_GRID_BIG
                }
            case .EDIT_TOKEN:
                {
                    token: ^Token = nil
                    if len(state.selected_tokens) > 0 {
                        token = &state.tokens[state.selected_tokens[0]]
                    }
                    key := rl.GetKeyPressed()
                    if token != nil && key != .KEY_NULL && key != .TAB && !rl.IsKeyDown(.LEFT_CONTROL) {
                        // Trigger only once for each press
                        if rl.IsKeyPressed(key) {
                            if key == .DELETE {
                                append(&state.undo_history, make_action(.EDIT_TOKEN_LIFE))
                                action: ^Action = &state.undo_history[len(state.undo_history) - 1]
                                token_kill(state, tile_map, token, action)
                                clear_selected_tokens(state)
                                state.needs_sync = true
                                finish_last_undo_history_action(state)
                                set_dirty_token_for_all_lights(state)
                            } else {
                                if rl.IsKeyDown(.BACKSPACE) {
                                    key = .BACKSPACE
                                }
                                byte: u8 = u8(key)
                                if byte != 0 {
                                    builder: strings.Builder
                                    strings.write_string(&builder, token.name)
                                    #partial switch key {
                                    case .MINUS:
                                        {
                                            edit_token_size(state, token, -1)
                                        }
                                    case .EQUAL:
                                        {
                                            if rl.IsKeyDown(.RIGHT_SHIFT) || rl.IsKeyDown(.LEFT_SHIFT) {
                                                edit_token_size(state, token, 1)
                                            }
                                        }
                                    case .RIGHT_SHIFT, .LEFT_SHIFT:
                                        {
                                        }
                                    case:
                                        if key == .BACKSPACE {
                                            strings.pop_rune(&builder)
                                        } else {
                                            strings.write_rune(&builder, rl.GetCharPressed())
                                        }
                                        append(&state.undo_history, make_action(.EDIT_TOKEN_NAME))
                                        action: ^Action = &state.undo_history[len(state.undo_history) - 1]
                                        action.token_id = token.id
                                        action.old_name = strings.clone(token.name)
                                        action.new_name = strings.clone(strings.to_string(builder))
                                        finish_last_undo_history_action(state)

                                        delete(token.name)
                                        token.name = strings.to_string(builder)

                                        key_consumed = true
                                    }

                                }
                            }
                        }
                    } else if rl.IsMouseButtonPressed(.LEFT) {
                        token := find_token_at_screen(tile_map, state, mouse_pos)
                        if token != nil {
                            clear(&state.selected_tokens)
                            append(&state.selected_tokens, token.id)
                        } else if token == nil && len(state.selected_tokens) > 0 {
                            clear(&state.selected_tokens)
                        } else if rl.IsKeyDown(.LEFT_SHIFT) {
                            pos_offset: u32 = 0
                            for name in PLAYERS {
                                append(&state.undo_history, make_action(.EDIT_TOKEN_LIFE))
                                action: ^Action = &state.undo_history[len(state.undo_history) - 1]
                                token_pos := mouse_tile_pos
                                token_pos.rel_tile = {0, 0}
                                token_pos.abs_tile.y += pos_offset

                                token_id := token_spawn(state, action, token_pos, state.selected_color, name)
                                new_token: ^Token = &state.tokens[token_id]
                                new_token.light = LightInfo(
                                    {
                                        rl.LoadRenderTexture(state.screen_width, state.screen_height),
                                        rl.LoadRenderTexture(state.screen_width, state.screen_height),
                                        TOKEN_DEFAULT_LIGHT_RADIUS,
                                        true,
                                        true,
                                        TOKEN_SHADOW_LEN,
                                        1,
                                    },
                                )
                                pos_offset += 2
                                finish_last_undo_history_action(state)
                                set_dirty_token_for_all_lights(state)
                            }
                            state.needs_sync = true
                        } else {
                            action := make_action(.EDIT_TOKEN_LIFE)
                            token_pos := mouse_tile_pos
                            token_pos.rel_tile = {0, 0}
                            token_spawn(state, &action, token_pos, state.selected_color)
                            append(&state.undo_history, action)
                            finish_last_undo_history_action(state)
                            set_dirty_token_for_all_lights(state)
                        }
                    } else if len(state.selected_tokens) == 0 {
                        // Show temp token
                        c := state.selected_color
                        c.a = 90
                        token, ok := &state.tokens[0]
                        if ok {
                            token.alive = true
                            token.position = mouse_tile_pos
                            token.position.rel_tile = {0, 0}
                            token.target_position = token.position
                            token.color = c
                        }
                        append(&state.temp_actions, make_action(.EDIT_TOKEN_LIFE, context.temp_allocator))
                        temp_action: ^Action = &state.temp_actions[len(state.temp_actions) - 1]
                        temp_action.token_id = 0
                        temp_action.token_life = true
                        set_dirty_token_for_all_lights(state)
                    }
                    icon = .ICON_PLAYER
                }
            case .TOUCH_MOVE:
                {
                    if state.previous_touch_pos != 0 {
                        d := state.previous_touch_pos - mouse_pos
                        state.camera_pos.rel_tile += d / 5
                        tile_map.dirty = true
                        set_dirty_token_for_all_lights(state)
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
                            tile_map.dirty = true
                            set_dirty_token_for_all_lights(state)
                        }

                        state.previous_touch_dist = dist
                    }
                }
            case .EDIT_BG:
                {
                    if state.bg_snap[0] != nil && state.bg_snap[1] != nil && state.bg_snap[2] != nil {
                        state.bg_snap[0] = nil
                        state.bg_snap[1] = nil
                        state.bg_snap[2] = nil
                    }
                    if rl.IsMouseButtonPressed(.LEFT) {
                        if state.bg_snap[0] == nil {
                            state.bg_snap[0] = mouse_pos
                        } else if state.bg_snap[1] == nil {
                            state.bg_snap[1] = mouse_pos
                        } else if state.bg_snap[2] == nil {
                            state.bg_snap[2] = mouse_pos

                            bg_tile_side_in_pixels_approx :=
                                (state.bg_snap[0].?.x - state.bg_snap[1].?.x) / state.bg_scale
                            big_dist := (state.bg_snap[0].?.x - state.bg_snap[2].?.x) / state.bg_scale
                            tiles_far := math.round(big_dist / bg_tile_side_in_pixels_approx)
                            bg_tile_side_in_pixels_approx = big_dist / tiles_far
                            new_scale := f32(tile_map.tile_side_in_pixels) / bg_tile_side_in_pixels_approx
                            append(&state.undo_history, make_action(.SET_BACKGROUND_SCALE))
                            action: ^Action = &state.undo_history[len(state.undo_history) - 1]
                            action.radius = f64(state.bg_scale - new_scale)
                            state.needs_sync = true
                            finish_last_undo_history_action(state)
                            state.bg_scale = new_scale
                        }
                    }
                    icon = .ICON_LAYERS
                }
            case .NEW_SAVE_GAME:
                {
                    key := rl.GetKeyPressed()
                    // Trigger only once for each press
                    if rl.IsKeyPressed(key) {
                        byte: u8 = u8(key)
                        if byte != 0 {
                            builder: strings.Builder
                            strings.write_string(&builder, state.menu_items[0])
                            #partial switch key {
                            case .BACKSPACE:
                                strings.pop_rune(&builder)
                                delete(state.menu_items[0])
                                state.menu_items[0] = strings.to_string(builder)
                                key_consumed = true
                            case .RIGHT_SHIFT, .LEFT_SHIFT, .ENTER, .ESCAPE:
                                {
                                }
                            case:
                                strings.write_byte(&builder, byte)
                                delete(state.menu_items[0])
                                state.menu_items[0] = strings.to_string(builder)
                                key_consumed = true
                            }

                        }
                    }

                }
            case .LOAD_GAME, .SAVE_GAME, .OPTIONS_MENU, .MAIN_MENU, .HELP:
                {}
            }
        }

        if state.mobile {
            // We support only move and touch tools for mobile
            if touch_count > state.previous_touch_count {
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
            if !key_consumed {
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

        tokens_animate(tile_map, state)
    }

    //TODO(amatej): extract into render method
    render_duration: time.Duration
    {
        time.SCOPED_TICK_DURATION(&render_duration)
        draw_light_mask(state, tile_map, &state.light, state.light_pos)
        for _, &token in state.tokens {
            l, ok := &token.light.?
            if ok {
                draw_light_mask(state, tile_map, l, token.position)
            }
        }
        merge_light_masks(state, tile_map)

        rl.BeginDrawing()

        rl.ClearBackground(EMPTY_COLOR.xyzw)

        // draw bg
        pos: rl.Vector2 = tile_map_to_screen_coord(state.bg_pos, state, tile_map)
        pos += state.bg_pos.rel_tile * tile_map.feet_to_pixels
        tex, ok := state.textures[state.bg_id]
        if ok {
            rl.DrawTextureEx(tex, pos, 0, state.bg_scale * tile_map.feet_to_pixels, rl.WHITE)
        }

        draw_tiles_to_tex(state, tile_map, &state.tiles_tex)
        rl.DrawTextureRec(
            state.tiles_tex.texture,
            {0, 0, f32(state.screen_width), f32(-state.screen_height)},
            {0, 0},
            {255, 255, 255, 255},
        )

        if (state.draw_grid || state.draw_grid_mask) {
            draw_grid_to_tex(state, tile_map, &state.grid_tex)

            if state.draw_grid {
                rl.DrawTextureRec(
                    state.grid_tex.texture,
                    {0, 0, f32(state.screen_width), f32(-state.screen_height)},
                    {0, 0},
                    {255, 255, 255, 25},
                )
            }

            if state.draw_grid_mask {
                draw_grid_mask_to_tex(state, tile_map, &state.grid_mask)
                rl.BeginShaderMode(state.grid_shader)
                {
                    //TODO(amatej): pass resolution?
                    rl.SetShaderValueTexture(state.grid_shader, state.mask_loc, state.grid_mask.texture)
                    //normalized_wall_color := rl.ColorNormalize(state.selected_wall_color.xyzw)
                    //TODO(amatej): For now do only black walls
                    normalized_wall_color := rl.ColorNormalize({0, 0, 0, 255})
                    rl.SetShaderValue(state.grid_shader, state.wall_color_loc, &normalized_wall_color, .VEC4)
                    rl.SetShaderValue(state.grid_shader, state.tile_pix_size_loc, &tile_map.tile_side_in_pixels, .INT)
                    camera_offset: [2]f32
                    camera_offset.x = f32(state.camera_pos.abs_tile.x) * f32(tile_map.tile_side_in_pixels)
                    camera_offset.y = f32(state.camera_pos.abs_tile.y) * f32(tile_map.tile_side_in_pixels)
                    camera_offset.x += state.camera_pos.rel_tile.x * tile_map.feet_to_pixels
                    camera_offset.y += state.camera_pos.rel_tile.y * tile_map.feet_to_pixels
                    camera_offset.x /= f32(state.screen_width)
                    camera_offset.x *= f32(-1)
                    camera_offset.y /= f32(state.screen_height)
                    rl.SetShaderValue(state.grid_shader, state.camera_offsret_loc, &camera_offset, .VEC2)
                    rl.SetShaderValueTexture(state.grid_shader, state.tiles_loc, state.tiles_tex.texture)
                    rl.DrawTextureRec(
                        state.grid_tex.texture,
                        {0, 0, f32(state.screen_width), f32(-state.screen_height)},
                        {0, 0},
                        {255, 255, 255, 155},
                    )
                }
                rl.EndShaderMode()
            }
        }

        // draw tokens on map
        for _, &token in state.tokens {
            if token.alive {
                token_pos, token_radius := get_token_circle(tile_map, state, &token)
                // Make tokens pop from background
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
                    if state.active_tool == .MOVE_TOKEN || state.active_tool == .EDIT_TOKEN {
                        hover_token := find_token_at_screen(tile_map, state, mouse_pos)
                        if hover_token != nil && hover_token == &token {
                            rl.DrawCircleGradient(
                                i32(token_pos.x),
                                i32(token_pos.y),
                                token_radius + 0.1 * f32(tile_map.tile_side_in_pixels),
                                HOVER_COLOR.xyzw,
                                HOVER_TRANSPARENT_COLOR.xyzw,
                            )
                        }
                    }
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
                tex_pos, tex_scale, texture := get_token_texture_tile_map_pos(tile_map, state, &token)
                if (texture != nil) {
                    rl.DrawTextureEx(texture^, tex_pos, 0, tex_scale, rl.WHITE)
                } else {
                    rl.DrawCircleV(token_pos, token_radius, token.color.xyzw)
                }
                pos: rl.Vector2 = tile_map_to_screen_coord_full(token.position, state, tile_map)
                rl.DrawText(
                    get_token_name_temp(&token),
                    i32(pos.x) - tile_map.tile_side_in_pixels / 2,
                    i32(pos.y) + tile_map.tile_side_in_pixels / 2,
                    tile_map.tile_side_in_pixels / 2,
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
        // draw particles
        for &particle in state.particles {
            if particle.lifetime_remaining <= 0 {
                continue
            }

            pos: rl.Vector2 = tile_map_to_screen_coord_full(particle.position, state, tile_map)
            color := particle.color_begin
            // particle lifetime is 0 to 1, multiply by 255 to get opacity
            color.w = u8(particle.lifetime_remaining / particle.lifetime * 255)
            rl.DrawCircleV(pos, particle.size, color.xyzw)
        }

        // Overlay the global shadow mask
        rl.DrawTextureRec(
            state.light_mask.texture,
            {0, 0, f32(state.screen_width), f32(-state.screen_height)},
            {0, 0},
            {255, 255, 255, 100},
        )

        // draw initiative tracker
        if (state.draw_initiative) {
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
                        token := &state.tokens[token_id]
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
                        texture := get_token_texture(state, token)
                        if texture != nil {
                            pos: rl.Vector2 = {23, f32(row_offset)}
                            // We assume token textures are squares
                            scale := f32(22 + token.size * 8) / f32(texture.width)
                            rl.DrawTextureEx(texture^, pos, 0, scale, rl.WHITE)
                        } else {
                            rl.DrawCircleV(circle_pos, f32(token_size), token.color.xyzw)
                        }
                        rl.DrawText(
                            get_token_name_temp(token),
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


        if state.timeout > 0 {
            msg := fmt.caprint(state.timeout_string, allocator = context.temp_allocator)
            rl.DrawText(msg, 100, 100, 100, rl.BLUE)
            state.timeout -= 1
        }
        if state.offline {
            msg := fmt.caprint("Offline", allocator = context.temp_allocator)
            rl.DrawText(msg, 10, 10, 18, rl.RED)
        }
        // draw debug info
        #partial switch state.debug {
        case .ACTIONS:
            {
                total_actions := fmt.caprint(
                    "Total actions: ",
                    len(state.undo_history),
                    allocator = context.temp_allocator,
                )
                rl.DrawText(total_actions, 30, 30, 18, rl.GREEN)
                count: i32 = 1
                for action_index := len(state.undo_history) - 1 - state.undone; action_index >= 0; action_index -= 1 {
                    a := &state.undo_history[action_index]
                    a_text := fmt.caprint(
                        action_index == len(state.undo_history) - 1 - state.undone ? " -> " : "    ",
                        action_index,
                        ": ",
                        to_string_action(a),
                        allocator = context.temp_allocator,
                    )
                    rl.DrawText(a_text, 50, 30 + 30 * count, 15, a.mine ? rl.GREEN : rl.RED)
                    count += 1
                    if count > 42 {
                        break
                    }
                }
            }
        case .TOKENS:
            {
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
                    token_text := fmt.caprint(
                        get_token_name_temp(t),
                        ": ",
                        t.position,
                        t.initiative,
                        allocator = context.temp_allocator,
                    )
                    rl.DrawText(token_text, 530, 60 + 30 * (i32(live_t)), 15, rl.BLUE)
                }
                total_tokens_live := fmt.caprint("Total live tokens: ", live_t, allocator = context.temp_allocator)
                total_tokens := fmt.caprint("Total tokens: ", len(state.tokens), allocator = context.temp_allocator)
                rl.DrawText(total_tokens_live, 430, 30, 18, rl.BLUE)
                rl.DrawText(total_tokens, 430, 50, 18, rl.BLUE)

                i = 0
                for init, &tokens in state.initiative_to_tokens {
                    init_tokens := fmt.caprint(init, ": ", tokens, allocator = context.temp_allocator)
                    rl.DrawText(init_tokens, 150, 60 + 30 * i32(i), 15, rl.BLUE)
                    i += 1
                }
            }
        case .PERF:
            {
                when ODIN_DEBUG {
                    //TODO(amatej): Do this only in one loop
                    for type in GraphType {
                        i := graphs.frame_index + 1
                        i %= GRAPHS_LEN
                        screen_index: i32 = 100
                        prev_val := math.log10(f32(time.duration_nanoseconds(graphs.values[type][i]))) * 100
                        for i != graphs.frame_index {
                            current_val := math.log10(f32(time.duration_nanoseconds(graphs.values[type][i]))) * 100
                            rl.DrawLine(
                                screen_index,
                                i32(prev_val),
                                screen_index + 1,
                                i32(current_val),
                                GraphTypeToColor[type].xyzw,
                            )
                            prev_val = current_val
                            i += 1
                            i %= GRAPHS_LEN
                            screen_index += 1
                        }
                    }
                }
            }
        }
        if state.debug != .OFF {
            offset: i32 = 30
            id := fmt.caprint("my_id: ", state.id, allocator = context.temp_allocator)
            rl.DrawText(id, state.screen_width - 330, offset, 18, rl.BLUE)
            offset += 30
            for peer, &peer_status in state.peers {
                peer_id := fmt.caprint(peer, allocator = context.temp_allocator)
                rl.DrawText(
                    peer_id,
                    state.screen_width - 330,
                    offset,
                    18,
                    peer_status.webrtc == .CONNECTED ? rl.GREEN : rl.RED,
                )
                offset += 30
            }
            rl.DrawFPS(state.screen_width - 200, state.screen_height - 100)
        }

        // DO UI

        rl.GuiDrawIcon(.ICON_BREAKPOINT_ON, state.screen_width - 20, 6, 1, state.socket_ready ? rl.GREEN : rl.RED)

        if state.active_tool == .LOAD_GAME ||
           state.active_tool == .SAVE_GAME ||
           state.active_tool == .NEW_SAVE_GAME ||
           state.active_tool == .MAIN_MENU ||
           state.active_tool == .OPTIONS_MENU {
            rl.DrawRectangleV({30, 30}, {f32(state.screen_width) - 60, f32(state.screen_height) - 60}, {0, 0, 0, 155})
            offset: i32 = 100
            for &item, i in state.menu_items {
                text := item
                if state.active_tool == .NEW_SAVE_GAME && i == 0 {
                    text = fmt.aprint(item, "|", sep = "", allocator = context.temp_allocator)
                }
                rl.DrawText(
                    strings.clone_to_cstring(text, context.temp_allocator) or_else BUILDER_FAILED,
                    100,
                    offset,
                    15,
                    i == state.selected_index ? rl.RED : rl.WHITE,
                )
                offset += 20
            }
        }

        if state.active_tool == .HELP {
            rl.DrawRectangleV({30, 30}, {f32(state.screen_width) - 60, f32(state.screen_height) - 60}, {0, 0, 0, 155})
            offset: i32 = 100
            for &c in config {
                builder := strings.builder_make(context.temp_allocator)
                for trigger in c.key_triggers {
                    strings.write_string(
                        &builder,
                        fmt.aprintf("%s (%s) + ", trigger.binding, trigger.action, allocator = context.temp_allocator),
                    )
                }
                strings.pop_rune(&builder)
                strings.pop_rune(&builder)
                rl.DrawText(strings.to_cstring(&builder) or_else BUILDER_FAILED, 100, offset, 15, rl.WHITE)
                for &bind in c.bindings {
                    if bind.icon != nil {
                        rl.GuiDrawIcon(bind.icon, 500, offset, 1, rl.WHITE)
                    }
                    rl.DrawText(strings.clone_to_cstring(bind.help, context.temp_allocator), 540, offset, 18, rl.WHITE)

                    offset += 20
                }
            }
        }

        ui_draw_tree(state.root)

        if state.active_tool == .EDIT_BG {
            if state.bg_snap[0] == nil {
                rl.DrawText("Select corner of any tile", i32(mouse_pos.x) + 20, i32(mouse_pos.y), 15, rl.WHITE)
            }
            if state.bg_snap[0] != nil && state.bg_snap[1] == nil {
                rl.DrawText(
                    "Select opposite corner of this tile",
                    i32(state.bg_snap[0].?.x),
                    i32(state.bg_snap[0].?.y),
                    15,
                    rl.WHITE,
                )
            }
            if state.bg_snap[0] != nil && state.bg_snap[1] != nil && state.bg_snap[2] == nil {
                rl.DrawText(
                    "Select tile corner as far horizontally as possible",
                    i32(state.bg_snap[1].?.x),
                    i32(state.bg_snap[1].?.y),
                    15,
                    rl.WHITE,
                )
            }
            for p in state.bg_snap {
                if p != nil {
                    rl.DrawLineV(p.? - {10, 0}, p.? + {10, 0}, {255, 0, 0, 255})
                    rl.DrawLineV(p.? - {0, 10}, p.? + {0, 10}, {255, 0, 0, 255})
                }
            }
        }

        rl.GuiDrawIcon(icon, i32(mouse_pos.x) - 4, i32(mouse_pos.y) - 30, 2, rl.WHITE)
        if (tooltip != nil) {
            rl.DrawText(tooltip.?, i32(mouse_pos.x) + 10, i32(mouse_pos.y) + 30, 28, rl.WHITE)
        }

        ui_update_widget_cache(state, state.root)

        tile_map.dirty = false

        // Before ending the loop revert all temp actions
        for _, index in state.temp_actions {
            undo_action(state, tile_map, &state.temp_actions[index])
        }
        clear(&state.temp_actions)

        rl.EndDrawing()
        free_all(context.temp_allocator)
    }
    when ODIN_DEBUG {
        graphs.values[.RENDER][graphs.frame_index] = render_duration
        graphs.values[.UPDATE][graphs.frame_index] = update_duration
        graphs.frame_index += 1
        graphs.frame_index %= GRAPHS_LEN
    }
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
    for name, _ in state.images {
        delete(name)
    }
    delete(state.images)
    for name, _ in state.textures {
        delete(name)
    }
    delete(state.textures)

    for name, _ in state.widget_cache {
        delete(name)
    }
    delete(state.widget_cache)

    tokens_reset(state)
    delete_token(&state.tokens[0])
    delete(state.initiative_to_tokens)
    delete(state.selected_tokens)
    delete(state.tokens)
    delete(state.bg_id)
    delete(state.timeout_string)

    for _, &item in state.needs_images {
        delete(item)
    }
    delete(state.needs_images)

    for &item in state.menu_items {
        delete(item)
    }
    delete(state.menu_items)
    for _, index in state.undo_history {
        delete_action(&state.undo_history[index])
    }
    delete(state.undo_history)

    tilemap_clear(tile_map)
    delete(tile_map.tile_chunks)

    // Delete peer states
    for peer, &peer_state in state.peers {
        delete_peer_state(&peer_state)
    }
    delete(state.peers)

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
