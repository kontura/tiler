#version 330

// Input vertex attributes (from vertex shader)
in vec3 vertexPos;
in vec2 fragTexCoord;
in vec4 fragColor;

// Input uniform values
uniform sampler2D texture0;
uniform sampler2D mask;
uniform sampler2D tiles;
uniform vec4 wall_color;
uniform int tile_pix_size;
uniform vec2 camera_offset;

// Output fragment color
out vec4 finalColor;

void main()
{
    vec4 texelColor = texture(texture0, (fragTexCoord));
    vec4 maskColor = texture(mask, (fragTexCoord));
    vec4 tilesColor = texture(tiles, (fragTexCoord));

    if (maskColor.r > 0.0 && tilesColor.a == 0) {
        finalColor = maskColor * fragColor * texelColor;
    } else {
        discard;
    }

}
