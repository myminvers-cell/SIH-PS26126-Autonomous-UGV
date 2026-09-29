# Road texture drop-in

Put seamless maps in this folder. The game looks for these exact names:

- `road_albedo.jpg` — sRGB asphalt color.
- `road_normal.png` — optional OpenGL tangent-space normal map (+Y green channel).
- `road_roughness.png` — optional grayscale roughness map.

Maps repeat every 9 metres in world space. Add the albedo alone to replace the asphalt color; add either optional map for additional PBR detail. Godot's resource importer loads maps in both editor and standalone builds. Use actual PNG normal/roughness images; renaming EXR files to `.png` does not convert their encoding. `road_normal.png` in this folder is a compatible normal map generated from the albedo texture.
