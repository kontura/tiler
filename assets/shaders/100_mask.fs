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

void main()
{
    vec4 texelColor = texture2D(texture0, fragTexCoord);
    vec4 maskColor = texture2D(mask, fragTexCoord);
    vec4 tilesColor = texture2D(tiles, fragTexCoord);

    if (maskColor.r > 0.0 && tilesColor.a == 0.0) {
        gl_FragColor = maskColor * fragColor * texelColor;
    } else {
        discard;
    }

}
