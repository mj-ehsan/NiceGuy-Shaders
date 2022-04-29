# NiceGuy-Shaders
A collection of my ReShade shaders.

1- ScatterFX is a shader to add roughness to qUINT_SSR or to denoise DH_RTGI.
If you want to do both, make a copy of the shader file so you have two pairs of it in your stack.
or put both of them between one pair (lower quality / higher performance)

2- Volumetric Fog tries to simulate physical aspects of fog and adaptively change it's color to
match the tone of the scene

3- Rim simulates rim lighting around objects

4- FastSharp as the name says, is a simple and fast adaptive sharpening filter

5- SlowSharp is more of an artistic effect rathen than a utility. You can
change the width of the filter to whatever you want. Beware of performance cost tho...

6- HoleFiller is made to assist AA shaders handle trees better. Fills harsh holes between
tree leaves
