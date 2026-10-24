# Hiro panorama source

Asset: `HIRO-panorama.webp` (768 × 384), downloaded unchanged from the stretched reconstruction published by KulaQuest Wiki:

https://wiki.kula.quest/_next/static/media/skybox-stretched.0o_w7jnjq_53z.webp

Technical description and reconstruction: Brandon Gardenhire / KulaQuest Wiki, https://wiki.kula.quest/graphics/tgi/ . The page documents the game's sky as 24 latitude bands × 48 longitude segments, with packed indexed textures, variable samples near the poles and 24 palettes. The artwork belongs to the game's rights holders; wiki documentation does not transfer ownership of the original game artwork.

The native renderer uses the published reconstructed panorama, a 24 × 48 camera-centred sphere, nearest sampling and affine UV interpolation to approximate PlayStation texturing. It does not contain an independently decoded original TGI payload. Exact source-byte colours, integer projection, yaw phase and all regional differences have not been verified against the original executable. The reused image is the wiki's WebP representation, not an assertion of a lossless original texture dump.
