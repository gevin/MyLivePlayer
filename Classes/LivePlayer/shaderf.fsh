varying lowp vec2 TexCoordOut;

uniform sampler2D SamplerY;
uniform sampler2D SamplerU;
uniform sampler2D SamplerV;

void main(void)
{
    mediump vec3 yuv;
    lowp vec3 rgb;
    
    // sampler2D 為一個 texture 的像素資料，透過 texture2D 給予座標，可取出該座標的像素資料
    yuv.x = texture2D(SamplerY, TexCoordOut).r;
    yuv.y = texture2D(SamplerU, TexCoordOut).r - 0.5;
    yuv.z = texture2D(SamplerV, TexCoordOut).r - 0.5;
    
    // yuv 轉換為 rgb 的矩陣
    rgb = mat3( 1,       1,         1,
               0,       -0.39465,  2.03211,
               1.13983, -0.58060,  0) * yuv;
    
    gl_FragColor = vec4(rgb, 1);
    
}
