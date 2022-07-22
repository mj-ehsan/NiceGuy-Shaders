# NiceGuy-Shaders
A collection of my ReShade shaders.
1- NiceGuy Lighting can be used to either add GI/AO or Specular Reflections.
You don't need ScatterFX for this one. It still requires DRME as it uses
temporal denoising. Still in Beta so expect major bugs. One known bug is
dilating black patches on the GI (can be seen in Reflection debug mode).
Select a PreProcessor Definition and press Enter to fix it. This bug happens
rarely tho.

2- ScatterFX is a shader to add roughness to qUINT_SSR or to denoise DH_RTGI.
If you want to do both, make a copy of the shader file so you have two pairs of it in your stack.
or put both of them between one pair (lower quality / higher performance)

3- Volumetric Fog 1-2 tries to simulate physical aspects of fog and adaptively change it's color to
match the tone of the scene

4- Rim simulates rim lighting around objects

5- FastSharp as the name says, is a simple and fast adaptive sharpening filter

6- SlowSharp is more of an artistic effect rathen than a utility. You can
change the width of the filter to whatever you want. Beware of performance cost tho...

7- HoleFiller is made to assist AA shaders handle trees better. Fills harsh holes between
tree leaves
