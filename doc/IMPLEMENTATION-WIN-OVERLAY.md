# Windows Overlay Diagnostics (Native)

This document describes the Windows-only diagnostics overlay that renders text into the map texture. The overlay is drawn in the upper-right corner and indicates which renderer and transfer path are in use (zero-copy vs CPU copy). It is designed to be easily extensible for custom messages.

## Goals

- Provide a clear, in-frame indicator of the active rendering path.
- Render at the native layer using OpenGL so the overlay is visible regardless of Flutter UI state.
- Make it easy for developers to add custom lines without touching unrelated code.

## Where It Lives

- Implementation: [src/AgusWglContextFactory.cpp](src/AgusWglContextFactory.cpp)
- Public API: [src/AgusWglContextFactory.hpp](src/AgusWglContextFactory.hpp)

## What It Shows

Default overlay lines:

- Renderer: OpenGL (WGL)
- Transfer: Zero-copy (WGL_NV_DX_interop) or Transfer: CPU copy (glReadPixels)
- Keyed mutex: On or Off

The transfer line reflects the actual path taken in the frame copy stage:

- Zero-copy if WGL interop is active and usable.
- CPU copy if interop is unavailable or fails.

## How It Renders

The overlay is drawn by OpenGL into the map render FBO before the frame blit or before the CPU readback.

- Zero-copy path: Drawn into the source render FBO, then included in the Y-flip blit into the interop FBO.
- CPU path: Drawn into the readback FBO before glReadPixels.

This means the overlay appears inside the map content itself and does not require any Flutter-side UI changes.

### Coordinate Orientation

The zero-copy path **flips Y** during the blit to match the D3D texture orientation. Because the overlay is drawn into the source render FBO before the blit, it uses the standard OpenGL **bottom-left origin** in both paths, and the blit flip corrects it for D3D.

Implementation details:
- Both paths use the standard bottom-left projection: `glOrtho(0, w, 0, h, -1, 1)`.

## Enable/Disable

Enabled by default. To disable it:

- Set environment variable AGUS_MAPS_WIN_OVERLAY=0

Example (PowerShell):

$env:AGUS_MAPS_WIN_OVERLAY = "0"

## Custom Overlay Lines

You can add your own diagnostic messages in native code:

- Method: AgusWglContextFactory::SetOverlayCustomLines(std::vector<std::string> lines)

This appends your lines to the default overlay content. You can call it after the factory is created, for example in the Windows surface creation path.

Recommendations for custom lines:

- Keep lines short.
- Avoid high-frequency updates unless necessary.
- Include only values that help debug render path or texture state.

## Styling and Positioning

- Location: upper-right corner
- Background: semi-transparent black rectangle
- Text: white, monospaced-ish bitmap glyphs
- Padding: small, consistent padding for readability

Text is drawn using WGL font bitmaps created once per process. This avoids per-frame font creation overhead.

## Known Limitations

- Windows-only by design.
- Uses OpenGL bitmap font rendering; appearance depends on system font availability.
- Not intended for production UX; it is a diagnostics overlay.

## Troubleshooting

If the overlay does not appear:

- Ensure AGUS_MAPS_WIN_OVERLAY is not set to 0.
- Verify the OpenGL context is created successfully.
- Confirm frames are being copied (the overlay renders during CopyToSharedTexture()).

If the overlay appears mirrored or in the wrong corner:
- Ensure you are on the **zero-copy** path and the overlay is using the **top-left origin** projection.
- If you are on the CPU path, the standard bottom-left OpenGL origin is expected.

If you need additional diagnostics, add custom lines with SetOverlayCustomLines and log them in your render loop.
