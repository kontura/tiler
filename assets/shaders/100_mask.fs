#version 100

precision mediump float;

// Input vertex attributes (from vertex shader)
varying vec3 vertexPos;
varying vec2 fragTexCoord;
varying vec4 fragColor;

// Input uniform values
uniform sampler2D texture0;
uniform sampler2D mask;
uniform sampler2D tiles;
uniform vec4 wall_color;
uniform int tile_pix_size;
uniform vec2 camera_offset;

float hash(float n) {
    return fract(sin(n * 12.9898) * 43758.5453);
}

// Inspired/Copied from https://www.shadertoy.com/view/X33fz4

//--------------------------------------------------
// 1) A helper function returning a FLOAT for wiggle
//    This replicates the old macro's logic but ensures
//    we end up with a single float, not a vec2.
//--------------------------------------------------
float H(vec2 v)
{
    // This replicates roughly: sin( 6.3 * fract(1e4 * sin( (v)*mat2(...))) )
    // but ensures we collapse it down to a float in the end.
    vec2 t = v * mat2(47, -73, 91, -37); // multiply v by matrix => vec2
    vec2 s = sin(t);                    // sin => vec2
    vec2 f = fract(1e4 * s);            // fract => vec2
    vec2 r = sin(6.3 * f);      // sin => vec2
    // Return one component (e.g. .x) so we have a single float:
    return r.x;
}

//--------------------------------------------------
// 2) Utility functions (same as in your code)
//--------------------------------------------------
float lineDist(vec2 p, vec2 a, vec2 b)
{
    vec2 v = b - a;
    float t = clamp(dot(p - a, v)/dot(v,v), 0.0, 1.0);
    return length((a + v*t) - p);
}

float cross2D(vec2 a, vec2 b)
{
    return a.x*b.y - a.y*b.x;
}

bool insideTriangle(vec2 p, vec2 A, vec2 B, vec2 C)
{
    float c1 = cross2D(B - A, p - A);
    float c2 = cross2D(C - B, p - B);
    float c3 = cross2D(A - C, p - C);
    return (c1*c2 >= 0.0 && c2*c3 >= 0.0);
}

vec3 randColor(float seed)
{
    return vec3(
        fract(sin(seed*12.9898)*43758.5453),
        fract(sin(seed*78.233 )*43758.5453),
        fract(sin(seed*37.719 )*43758.5453)
    );
}

//--------------------------------------------------
// 3) Instead of the P(...) macro, define cornerPos()
//    which uses a float wiggle
//--------------------------------------------------
vec2 cornerPos(
    vec2 base,
    vec2 floorCell,
    int ix, int iy,
    int k,
    float waveAmp
){
    // integer corner offset
    vec2 cornerIndex = vec2(float(ix) + mod(float(k),float(2)), float(iy + (k/2)));

    // get a single float wiggle
    float wiggle = H(floorCell + cornerIndex);

    // shift the corner
    return base + cornerIndex + waveAmp * wiggle;
}

float compute_stripe(vec2 p, float seed) {
    float randomAngle = hash(seed) * 3.14159265;
    float c = cos(randomAngle);
    float s = sin(randomAngle);
    vec2 rotated = vec2(
        c * p.x - s * p.y,
        s * p.x + c * p.y
    );
    float spacing = 0.15;     // distance between lines
    float thickness = 0.12;  // line width

    float line = abs(fract(rotated.x / spacing) - 0.5);
    return step(line, thickness);
}


vec4 triangles() {
    ////-----------------------------------------
    //// B) map fragCoord -> "world" coords
    ////-----------------------------------------
    vec2 p = ((fragTexCoord - camera_offset - 0.5) / (float(tile_pix_size)* 0.001) + 0.5);

    //-----------------------------------------
    // C) scale wiggly amplitude so we don't get spikes
    //-----------------------------------------
    float waveAmp = 0.20;

    // track final color, min line-dist, etc.
    vec4  crossHatchColor = vec4(0.0);

    //-----------------------------------------
    // D) loop over local cells
    //-----------------------------------------
    ivec2 cellCenter = ivec2(floor(p));
    for(int j = -1; j <= 1; j++)
    {
        for(int i = -1; i <= 1; i++)
        {
            ivec2 ij = cellCenter + ivec2(i, j);

            vec2 base      = vec2(ij);
            vec2 floorCell = base;  // used for H(...)

            // each cell => 2x2 sub-squares => k=0..3
            for(int k=0; k<4; k++)
            {
                // corners with scaled float wiggle
                vec2 h0 = cornerPos(base, floorCell, 0,0, k, waveAmp);
                vec2 h1 = cornerPos(base, floorCell, 1,0, k, waveAmp);
                vec2 h2 = cornerPos(base, floorCell, 0,1, k, waveAmp);
                vec2 h3 = cornerPos(base, floorCell, 1,1, k, waveAmp);

                // pseudo-delaunay diagonal
                bool diag0 = (length(h0 - h3) < length(h1 - h2));

                // random colors
                float seedBase = dot(floorCell, vec2(13.721, 29.123)) + float(k)*3.97;

                if(diag0)
                {
                    // triangles: (h0,h1,h3) and (h0,h2,h3)
                    if(insideTriangle(p, h0, h1, h3))
                        crossHatchColor = wall_color * vec4(1, 1, 1, compute_stripe(p, seedBase + 0.1));
                    if(insideTriangle(p, h0, h2, h3))
                        crossHatchColor = wall_color * vec4(1, 1, 1, compute_stripe(p, seedBase + 7.9));
                }
                else
                {
                    // triangles: (h0,h1,h2) and (h1,h2,h3)
                    if(insideTriangle(p, h0, h1, h2))
                        crossHatchColor = wall_color * vec4(1, 1, 1, compute_stripe(p, seedBase + 0.1));
                    if(insideTriangle(p, h1, h2, h3))
                        crossHatchColor = wall_color * vec4(1, 1, 1, compute_stripe(p, seedBase + 7.9));
                }
            }
        }
    }

    return crossHatchColor;
}

void main()
{
    vec4 texelColor = texture2D(texture0, fragTexCoord);
    vec4 maskColor = texture2D(mask, fragTexCoord);
    vec4 tilesColor = texture2D(tiles, fragTexCoord);

    if (maskColor.r > 0.0 && tilesColor.a == 0.0) {
        gl_FragColor = triangles() + texelColor;
    } else {
        discard;
    }

}
