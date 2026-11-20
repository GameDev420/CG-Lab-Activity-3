# CG-Lab-Activity-3

# AI Notice
I did heavily use Google's AI Overview feature when making the water shader due to not knowing the specific functions for SSR and probe reflections in HLSL, as well as sampling the depth buffer. However, the logical process was still developed solely individually, and I tried to fit comments both for myself to learn and to show references where I could.

# Desired Effect

The effect I tried to replicate is the water from Genshin Impact.

After hearing about the introduction of screen-space reflections and realtime GI in URP, I knew I wanted to do something with them. However, after several hours trying to get both SSR and depth coloring to work simultaneously, I opted to just make two near-identical shaders that demonstrate them both seperately.

<img width="600" height="333" alt="image" src="https://github.com/user-attachments/assets/9ea0a32b-2df7-4941-8f85-6e972b61f060" />

(Video reference if needed)
https://youtu.be/pyZqEkMDjUg?t=176

# My Implementation

(First shows the depth coloring with baked reflections, then the SSR version)
https://github.com/user-attachments/assets/fa241b6f-23fd-46b7-8061-9fb708ea4c5e

Compared to the basic water shader, I added reflections (SSR and through reflection probes, but not simultaneously), depth-based water coloring and transparency, specular highlights, and a tiling normal map to distort said reflections. There are also caustics on the surface below the water, but that was merely another shader to create an illusion rather than projecting decals or anything fancy.

Normal map was from online via:
https://blenderartists.org/t/animated-water-normal-map-tileable-looped/673140

Shader Graph (used for caustics):

<img width="2406" height="883" alt="image" src="https://github.com/user-attachments/assets/990be69e-74e6-4c44-8535-397a75df6c6d" />
<img width="2554" height="1315" alt="image" src="https://github.com/user-attachments/assets/4332599b-4b97-4624-b329-5ae26b14e21e" />
<img width="2521" height="1014" alt="image" src="https://github.com/user-attachments/assets/3ddbcdfe-7c75-4b07-84e4-6fbee07ee454" />
