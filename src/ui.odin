package tiler

import "core:fmt"
import "core:math"
import "core:strings"
import rl "vendor:raylib"

// rfleury ui

SPEED :: 5

UIWidgetFlag :: enum {
    CLICKABLE,
    HOVERABLE,
    DRAGABLE,
    DRAWTEXT,
    DRAWICON,
    DRAWBORDER,
    DRAWBACKGROUND,
    DRAWBACKGROUNDGRADIENT,
    DRAWDROPSHADOW,
    DRAWCOLORPICKER,
    DRAWCOLORBARALPHA,
    HOTANIMATION,
    ACTIVEANIMATION,
    USETILEMAPPOS,
    // ...
}

UIWidgetFlags :: bit_set[UIWidgetFlag]

UIWidget :: struct {
    // first child
    first:                 ^UIWidget,
    // last child
    last:                  ^UIWidget,
    // next sibling
    next:                  ^UIWidget,
    // prev sibling
    prev:                  ^UIWidget,
    parent:                ^UIWidget,

    // per-frame info provided by builders
    string:                string,
    icon:                  rl.GuiIconName,
    flags:                 UIWidgetFlags,
    background_color:      [4]u8,
    colorpicker_color:     ^[4]u8,
    colorpicker_alpha:     ^f32,
    active:                bool,

    // computed every frame
    //TODO(amatej): for now I set these also by builders
    computed_rel_position: [2]f32,
    computed_size:         [2]f32,
    // final position on screen
    rect:                  rl.Rectangle,
    dragged:               bool,
    map_pos:               Maybe(TileMapPosition),

    // persistent data6
    hot_t:                 f32,
    active_t:              f32,

    state:                 ^GameState,
}

UIInteraction :: struct {
    widget:   ^UIWidget,
    clicked:  bool,
    hovering: bool,
    dragging: bool,
    released: bool,
}

exponential_smoothing :: proc(target, current: f32) -> f32 {
    return current + (target - current) * (1 - math.exp(-rl.GetFrameTime() * SPEED))
}

// We pass mouse_pos so it can be overriden
ui_widget_interaction :: proc(widget: ^UIWidget, mouse_pos: [2]f32) -> UIInteraction {
    interaction: UIInteraction

    stack := make([dynamic]^UIWidget, context.temp_allocator)
    current: ^UIWidget = widget
    last_visited: ^UIWidget

    widget_selected := false
    for current != nil || len(stack) != 0 {
        if current != nil {
            append(&stack, current)
            current = current.first
        } else {
            peek := stack[len(stack) - 1]

            if peek.next != nil && last_visited != peek.next {
                current = peek.next
            } else {
                // visiting peek
                if (rl.CheckCollisionPointRec(mouse_pos, ui_widget_get_rect(peek))) {
                    if (peek == widget) {
                        widget_selected = true
                    } else {
                        // we are howering some on top of our selected widget
                        break
                    }
                }
                last_visited = pop(&stack)
            }

        }
    }

    if (widget_selected) {
        if .HOVERABLE in widget.flags {
            interaction.hovering = true
        }

        if .CLICKABLE in widget.flags {
            if rl.IsMouseButtonPressed(.LEFT) {
                interaction.clicked = true
            }
        }

        if .DRAGABLE in widget.flags {
            if rl.IsMouseButtonPressed(.LEFT) {
                widget.dragged = true
            }
            if rl.IsMouseButtonReleased(.LEFT) {
                interaction.released = true
                widget.dragged = false
            }
            interaction.dragging = widget.dragged
        }
    }

    return interaction
}

ui_update_widget_cache :: proc(state: ^GameState, root: ^UIWidget) {
    stack := make([dynamic]^UIWidget, context.temp_allocator)
    append(&stack, root)

    for len(stack) > 0 {
        current := pop(&stack)

        widget, ok := &state.widget_cache[current.string]

        if ok {
            widget.computed_rel_position = current.computed_rel_position
            widget.computed_size = current.computed_size
            widget.rect = current.rect
            widget.hot_t = current.hot_t
            widget.active_t = current.active_t
            widget.dragged = current.dragged
            widget.map_pos = current.map_pos
        } else {
            state.widget_cache[strings.clone(current.string)] = current^
        }

        if current.next != nil {
            append(&stack, current.next)
        }

        if current.first != nil {
            append(&stack, current.first)
        }
    }

}

ui_make_widget :: proc {
    ui_make_widget_basic,
    ui_make_widget_rect,
}

ui_make_widget_rect :: proc(
    state: ^GameState,
    parent: ^UIWidget,
    flags: UIWidgetFlags,
    string: string,
    rect: [4]f32,
    allocator := context.temp_allocator,
) -> ^UIWidget {
    widget := new(UIWidget, allocator)
    widget.string = string
    widget.flags = flags
    widget.rect = {rect[0], rect[1], rect[2], rect[3]}
    widget.state = state

    widget_cached, ok := &state.widget_cache[string]
    if ok {
        widget.computed_rel_position = widget_cached.computed_rel_position
        widget.computed_size = widget_cached.computed_size
        widget.rect = widget_cached.rect
        widget.hot_t = widget_cached.hot_t
        widget.active_t = widget_cached.active_t
        widget.dragged = widget_cached.dragged
        widget.map_pos = widget_cached.map_pos
    }

    // Update widgets tree
    if parent != nil {
        widget.parent = parent
        if parent.last != nil {
            // parent already has children
            assert(parent.last.next == nil)
            widget.prev = parent.last
            parent.last.next = widget
            parent.last = widget
        } else {
            // no child
            assert(parent.first == nil)
            parent.first = widget
            parent.last = widget
        }
    }

    if widget.dragged {
        mouse_pos := rl.GetMousePosition()
        if .USETILEMAPPOS in widget.flags {
            mouse_tile_pos: TileMapPosition = screen_coord_to_tile_map(mouse_pos, state, state.tile_map)
            widget.map_pos = mouse_tile_pos
        } else {
            widget.rect.x = mouse_pos.x - widget.rect.width/2
            widget.rect.y = mouse_pos.y - widget.rect.height/2
        }
    }

    return widget
}

ui_make_widget_basic :: proc(
    state: ^GameState,
    parent: ^UIWidget,
    flags: UIWidgetFlags,
    string: string,
    allocator := context.temp_allocator,
) -> ^UIWidget {
    return ui_make_widget_rect(state, parent, flags, string, [4]f32{0, 0, 0, 0}, allocator)
}

ui_radio_button :: proc(
    state: ^GameState,
    parent: ^UIWidget,
    string: string,
    active: bool,
    icon: rl.GuiIconName,
    rect: [4]f32,
    allocator := context.temp_allocator,
) -> UIInteraction {
    radio := ui_make_widget(
        state,
        parent,
        {.CLICKABLE, .HOVERABLE, .DRAWICON, .DRAWBACKGROUND, .HOTANIMATION},
        string,
    )
    radio.icon = icon
    radio.background_color = active ? {255, 255, 255, 95} : {0, 0, 0, 95}
    radio.active = active
    radio.rect = {rect[0], rect[1], rect[2], rect[3]}

    return ui_widget_interaction(radio, rl.GetMousePosition())
}

ui_widget_get_rect :: proc(widget: ^UIWidget) -> rl.Rectangle {
    rect: rl.Rectangle
    if .USETILEMAPPOS in widget.flags {
        center := tile_map_to_screen_coord_full(widget.map_pos.?, state, tile_map)
        start := center - (f32(widget.state.tile_map.tile_side_in_pixels)/2)
        end := center + (f32(widget.state.tile_map.tile_side_in_pixels)/2)

        rect = {start.x, start.y, end.x - start.x, end.y - start.y}
    } else {
        rect = widget.rect
    }

    return rect
}

ui_draw_tree :: proc(root: ^UIWidget) {
    stack := make([dynamic]^UIWidget, context.temp_allocator)
    append(&stack, root)

    for len(stack) > 0 {
        current := pop(&stack)
        interaction := ui_widget_interaction(current, rl.GetMousePosition())

        rect: rl.Rectangle = ui_widget_get_rect(current)

        if .DRAWBACKGROUND in current.flags {
            if !current.active && interaction.hovering {
                current.hot_t = exponential_smoothing(1, current.hot_t)
                if .HOTANIMATION in current.flags {
                    rl.DrawRectangleRec(rect, {200, 0, 0, u8(255 * current.hot_t)})
                } else {
                    rl.DrawRectangleRec(rect, {100, 0, 0, 255})
                }
            } else {
                current.hot_t = 0
                rl.DrawRectangleRec(rect, current.background_color.xyzw)
            }
        }

        if .DRAWBACKGROUNDGRADIENT in current.flags {
            rl.DrawRectangleGradientEx(rect, {40, 40, 40, 45}, {40, 40, 40, 45}, {0, 0, 0, 0}, {0, 0, 0, 0})
        }

        if .DRAWBORDER in current.flags {
            rl.DrawRectangleLinesEx(rect, 3, {255, 0, 0, 255})
        }

        if .DRAWTEXT in current.flags {
            rl.DrawText(
                strings.clone_to_cstring(current.string, context.temp_allocator),
                i32(rect.x) + 4,
                i32(rect.y) + 4,
                18,
                rl.WHITE,
            )
        }

        if .DRAWICON in current.flags {
            rl.GuiDrawIcon(current.icon, i32(rect.x) + 7, i32(rect.y) + 7, 1, rl.WHITE)
        }

        if .DRAWCOLORPICKER in current.flags {
            rl.GuiColorPicker(rect, "color picker", (^rl.Color)(current.colorpicker_color))
        }
        if .DRAWCOLORBARALPHA in current.flags {
            rl.GuiColorBarAlpha(rect, "color picker alpha", current.colorpicker_alpha)
        }

        if current.next != nil {
            append(&stack, current.next)
        }

        if current.first != nil {
            append(&stack, current.first)
        }
    }
}
