"""
Remove tile seam lines from assets/maps/map_01.png.
Seams are at every 209px (tile boundaries). Outputs map_01_clean.png.

Strategy: for each 5px band around each seam, replace with linear interpolation
from the pixels just outside the band. This removes bright/dark edge artifacts
left by the tile assembly process.
"""
from PIL import Image
import numpy as np

TILE = 209
SEAM_COLS = [209, 418, 627, 836, 1045]
SEAM_ROWS = [209, 418, 627, 836, 1045]

BAND = 2     # replace ±BAND around seam center (5px total)
OUT  = 3     # sample from this many pixels outside the band edge (avg of OUT pixels)

img = Image.open('assets/maps/map_01.png').convert('RGB')
arr = np.array(img, dtype=np.float64)
h, w = arr.shape[:2]
result = arr.copy()

def avg_slice_cols(a, x0, x1):
    """Average a range of columns x0..x1-1 (clamped)."""
    x0, x1 = max(0, x0), min(w, x1)
    if x0 >= x1:
        return a[:, max(0, x0), :]
    return a[:, x0:x1, :].mean(axis=1)

def avg_slice_rows(a, y0, y1):
    """Average a range of rows y0..y1-1 (clamped)."""
    y0, y1 = max(0, y0), min(h, y1)
    if y0 >= y1:
        return a[max(0, y0), :, :]
    return a[y0:y1, :, :].mean(axis=0)

# --- Fix vertical seams: interpolate horizontally ---
for cx in SEAM_COLS:
    lo = cx - BAND   # first col to replace
    hi = cx + BAND   # last col to replace

    # Sample from OUT pixels just outside the band on each side
    left_ref  = avg_slice_cols(arr, lo - OUT, lo)      # cols [lo-OUT .. lo-1]
    right_ref = avg_slice_cols(arr, hi + 1, hi + 1 + OUT)  # cols [hi+1 .. hi+OUT]

    span = (hi + 1 + OUT) - (lo - OUT) - 1  # total span for t computation
    left_x  = lo - OUT / 2
    right_x = hi + 1 + OUT / 2

    for x in range(max(0, lo), min(w, hi + 1)):
        t = (x - left_x) / (right_x - left_x) if right_x != left_x else 0.5
        t = np.clip(t, 0, 1)
        result[:, x] = left_ref * (1 - t) + right_ref * t

    print(f"  col seam {cx}: replaced x={lo}–{hi}, refs x={lo-OUT}..{lo-1} & {hi+1}..{hi+OUT}")

# --- Fix horizontal seams: interpolate vertically using already-fixed result ---
for ry in SEAM_ROWS:
    lo = ry - BAND
    hi = ry + BAND

    top_ref = avg_slice_rows(result, lo - OUT, lo)
    bot_ref = avg_slice_rows(result, hi + 1, hi + 1 + OUT)

    top_y   = lo - OUT / 2
    bot_y   = hi + 1 + OUT / 2

    for y in range(max(0, lo), min(h, hi + 1)):
        t = (y - top_y) / (bot_y - top_y) if bot_y != top_y else 0.5
        t = np.clip(t, 0, 1)
        result[y, :] = top_ref * (1 - t) + bot_ref * t

    print(f"  row seam {ry}: replaced y={lo}–{hi}, refs y={lo-OUT}..{lo-1} & {hi+1}..{hi+OUT}")

out = Image.fromarray(np.clip(result, 0, 255).astype(np.uint8))
out.save('assets/maps/map_01_clean.png')
print(f"\nSaved: assets/maps/map_01_clean.png ({w}x{h})")
