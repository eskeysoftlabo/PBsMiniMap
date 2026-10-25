# Compass frame

Original asset created for PB's MiniMap using the built-in image_gen tool.

- `compass-frame-source.png`: original generated RGBA artwork.
- `compass-frame.png`: 512×512 RGBA preview, resized from the source with Pillow (Lanczos).
- `compass-frame.dds`: runtime BC3/DXT5 texture, 512×512 with a full 8-level mip chain,
  alpha preserved, about 341 KiB.

It was 1024×1024 with no mip chain (1 MiB). The frame is drawn at roughly 300px, so without
mips it shimmered as the minimap was resized, and the extra size bought nothing.

Listed in `PBsMiniMap.addon`. A file not named in the manifest is inaccessible at runtime and
`SetTexture` yields the engine's 1×1 placeholder, measured on PS5 (PBsJanken 1.0.7); PS5 paths
are case sensitive, so the manifest entry must match the real casing.

The geometry uses a centred clip of radius 0.42 × texture width. Re-measured on the 512×512
file at 360 angular samples: the metal annulus is opaque from 0.40 to 0.47 × width, so the cut
lies beneath metal all the way round. The compass is fixed north-up, matching the game's map.
No pointer or map is baked into the artwork.

Generation prompt (built-in tool; transparent_background=true):

> Use case: stylized-concept. Asset type: production game HUD compass bezel texture, square 1024x1024 RGBA with actual transparent background. An original sophisticated aged gunmetal and brushed antique brass circular compass FRAME ONLY, perfectly front facing orthographic, concentric, exact center (512,512). Outer radius 490 pixels, perfectly circular open transparent hole radius 410 pixels. Narrow substantial metal annulus with engraved radial tick marks, restrained filigree and four small inset rivets. Clearly engraved legible cardinal letters N at top, E at right, S at bottom, W at left, within the metal ring, gold lettering in dark steel. North has a tiny red enamel accent. Premium weathered exploration instrument, realistic subtle bevel highlights from upper left, restrained shadows contained on ring. Interior completely transparent, exterior completely transparent. No map, no compass needle, no glass, no background, no perspective, no extra text, no protruding ornaments. Crisp at 300px display size. Exact centered circular geometry for use over a live circular minimap.
