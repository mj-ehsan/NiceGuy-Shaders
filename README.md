# NiceGuy-Shaders
A collection of my ReShade shaders.

1- NiceGuy Lighting: can be used to either add GI/AO or Specular Reflections. You don't need ScatterFX for this one. It still requires DRME (or ReShade_MotionVectors/qUINT_MotionVectors) as it uses temporal denoising. Still in Beta so expect bugs.

2- NiceGuy Lamps: can be used to add custom point lights to your screenshots. Add up to 4 point lights with customizable color, brightness, location, optional fog, and optional screen space shadows with customizable soft shadows. Fog intensity, Specular reflection intensity, and Specular reflection roughness are fully customizable. Reflection uses GGX (all credit to LVutner) and Diffuse light uses Lambert model. Fog is fake. Not suitable for gameplay as the lights are in view space and will follow the camera movement instead of sticking to the world.

2- ScatterFX (deprecated - using NiceGuy Lighting instead is strongly recommended) is a shader to add roughness to qUINT_SSR or to denoise DH_RTGI. If you want to do both, make a copy of the shader file so you have two pairs of it in your stack. or put both of them between one pair (lower quality / higher performance)

3- Volumetric Fog 1-2 try to simulate physical aspects of fog and adaptively change it's color to match the tone of the scene. No use of ray marching.

4- Rim simulates rim lighting around objects. 

5- FastSharp as the name says, is a simple and fast adaptive sharpening filter.

6- SlowSharp is more of an artistic effect rathen than a utility. You can change the width of the filter to whatever you want. Beware of performance cost tho...

7- HoleFiller is made to assist AA shaders handle trees better. Fills harsh holes between tree leaves.
