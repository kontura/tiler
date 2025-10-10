package tiler

import "core:math/rand"
import "core:fmt"

Particle :: struct {
    position:           TileMapPosition,
    velocity:           [2]f32,
    color_begin:        [4]u8,
    color_end:          [4]u8,
    size:               f32,
    lifetime:           f32,
    lifetime_remaining: f32,
}

PARTICLE_SIZE: f32 : 3
PARTICLE_LIFETIME: f32 : 1
PARTICLE_BASE_VELOCITY: f32 : 10

particle_emit :: proc(state: ^GameState, pos: TileMapPosition, velocity: f32, lifetime: f32, color: [4]u8, size: f32) {
    p := &state.particles[state.particle_index]
    p.position = pos
    p.color_begin = color
    p.color_end = color
    p.size = size
    p.velocity.x = velocity * (rand.float32() - .5) * 2
    p.velocity.y = velocity * (rand.float32() - .5) * 2
    p.lifetime = lifetime
    p.lifetime_remaining = lifetime
    state.particle_index += 1
    state.particle_index = state.particle_index % len(state.particles)
}

particles_update :: proc(state: ^GameState, tile_map: ^TileMap, dt: f32) {
    for &p in state.particles {
        if p.lifetime_remaining <= 0 {
            continue
        }

        p.lifetime_remaining -= dt
        p.position.rel_tile += p.velocity * dt
        p.position = recanonicalize_position(tile_map, p.position)
    }
}
