/**
 * Shared coordinate math for Pixora canvas scenes.
 * Mirrors android/.../scene/SceneCoords.kt — keep formulas in sync.
 *
 * Surface dimensions default to reference 1080x2340 but the editor sets
 * `surface.w/h` from the connected device via /api/device-surface.
 */

/** @type {{ w: number, h: number }} Live surface size (editor syncs from adb). */
export const surface = { w: 1080, h: 2340 };

export const REFERENCE_SURFACE_W = 1080;
export const REFERENCE_SURFACE_H = 2340;

export function setSurfaceDims(w, h) {
  const nw = Math.round(Number(w));
  const nh = Math.round(Number(h));
  if (nw > 0 && nh > 0) {
    surface.w = nw;
    surface.h = nh;
  }
}

export function getSurfaceDims() {
  return { w: surface.w, h: surface.h };
}

/** @deprecated use surface.w */
export function surfaceW() { return surface.w; }
/** @deprecated use surface.h */
export function surfaceH() { return surface.h; }

export function screenCenterPx(sw = surface.w, sh = surface.h) {
  return { x: sw / 2, y: sh / 2 };
}

export const SCREEN_CENTER_WORLD = { x: 0, y: 0 };

export function hasParallaxLayers(spec) {
  return Array.isArray(spec?.image_layers) && spec.image_layers.length > 0;
}

export function coverFitScale(bmpW, bmpH, surfaceW = surface.w, surfaceH = surface.h, layerScale = 1) {
  return Math.max(surfaceW / bmpW, surfaceH / bmpH) * layerScale;
}

/** 2026-07-04 — Universal target-fit factor.
 *  Compresses the REFERENCE (1080×2340) inside the current viewport
 *  proportionally. ALL layers AND sprites scale by this so their
 *  composition stays locked cross-aspect (Samsung 2340 vs Huawei 1920).
 *  Mirrors SceneCoords.kt subjectFactor. */
export function subjectFactor(surfaceW = surface.w, surfaceH = surface.h) {
  return Math.min(surfaceW / REFERENCE_SURFACE_W, surfaceH / REFERENCE_SURFACE_H);
}

export function layerDrawRect(bmpW, bmpH, layer, surfaceW = surface.w, surfaceH = surface.h) {
  // 2026-07-04 — mirrors CanvasSceneRenderer.ensureLayersPrescaled:
  // ALL layers use subjectFactor × layer.scale so background and subject
  // remain locked in the same composition on any aspect ratio.
  const scale = subjectFactor(surfaceW, surfaceH) * (layer.scale || 1);
  const drawW = bmpW * scale;
  const drawH = bmpH * scale;
  const factor = subjectFactor(surfaceW, surfaceH);
  const left = (surfaceW - drawW) / 2 + (layer.offset_x_px || 0) * factor;
  const top = (surfaceH - drawH) / 2 + (layer.offset_y_px || 0) * factor;
  return {
    left, top, drawW, drawH,
    centerX: left + drawW / 2,
    centerY: top + drawH / 2,
  };
}

export function layerWorldSize(bmpW, bmpH, layer, surfaceW = surface.w, surfaceH = surface.h) {
  const { drawW, drawH } = layerDrawRect(bmpW, bmpH, layer, surfaceW, surfaceH);
  return { w: drawW, h: drawH };
}

export function layerMeshPosition(layer, surfaceW = surface.w, surfaceH = surface.h) {
  // 2026-07-04 — offsets scale by subjectFactor so a subject with
  // offset_y=684 lands at the same relative position as authored,
  // whether the editor is showing 2340 tall or 1920 tall.
  const f = subjectFactor(surfaceW, surfaceH);
  return {
    x: (layer.offset_x_px || 0) * f,
    y: -(layer.offset_y_px || 0) * f,
  };
}

export function applyLayerMeshTransform(mesh, layer, surfaceW = surface.w, surfaceH = surface.h) {
  const p = layerMeshPosition(layer, surfaceW, surfaceH);
  mesh.position.x = p.x;
  mesh.position.y = p.y;
}

export function spriteSampleDiv(params) {
  return (params?.high_res || params?.fullscreen) ? 1 : 2;
}

export function spriteDecodedSize(natW, natH, params) {
  const div = spriteSampleDiv(params);
  return { w: natW / div, h: natH / div };
}

export function spriteRenderSize(params, natW, natH, surfaceW = surface.w, surfaceH = surface.h) {
  if (params?.fullscreen) {
    const aspect = natW / natH;
    const screenAspect = surfaceW / surfaceH;
    if (aspect > screenAspect) return { w: surfaceH * aspect, h: surfaceH };
    return { w: surfaceW, h: surfaceW / aspect };
  }
  const { w: decW, h: decH } = spriteDecodedSize(natW, natH, params);
  const scale = params?.scale ?? 0.003;
  // 2026-07-04 — mirrors SpriteController: sprites scale by REFERENCE_W
  // × scale × subjectFactor so they shrink with their subject on
  // shorter viewports (Huawei 1920) instead of staying oversized.
  const rw = decW * scale * REFERENCE_SURFACE_W * subjectFactor(surfaceW, surfaceH);
  return { w: rw, h: rw * (decH / decW) };
}

export function spriteAnchor(params) {
  return {
    x: params?.anchor_x ?? 0.5,
    y: params?.anchor_y ?? 0.5,
  };
}

export function anchorFromAlphaBbox(bbox) {
  if (!bbox) return { x: 0.5, y: 0.5 };
  return {
    x: (bbox.x + bbox.w / 2) / bbox.texW,
    y: (bbox.y + bbox.h / 2) / bbox.texH,
  };
}

export function anchorNormToAndroidPx(xNorm, yNorm, surfaceW = surface.w, surfaceH = surface.h) {
  return { x: xNorm * surfaceW, y: yNorm * surfaceH };
}

export function spriteDrawCenterPx(params, renderW, renderH, surfaceW = surface.w, surfaceH = surface.h) {
  const xNorm = params?.x ?? 0.5;
  const yNorm = params?.y ?? 0.5;
  const anchor = spriteAnchor(params);
  // 2026-07-04 — mirrors SceneCoords.spriteDrawCenter (target-relative):
  // sprite sticks to the composition the author saw in the editor even
  // when the device viewport is shorter than TARGET (Huawei 1080×1920).
  const f = subjectFactor(surfaceW, surfaceH);
  return {
    x: surfaceW / 2 + (xNorm - 0.5) * REFERENCE_SURFACE_W * f + (0.5 - anchor.x) * renderW,
    y: surfaceH / 2 + (yNorm - 0.5) * REFERENCE_SURFACE_H * f + (0.5 - anchor.y) * renderH,
  };
}

export function spriteMeshPosition(params, renderW, renderH, surfaceW = surface.w, surfaceH = surface.h) {
  const draw = spriteDrawCenterPx(params, renderW, renderH, surfaceW, surfaceH);
  return {
    x: draw.x - surfaceW / 2,
    y: surfaceH / 2 - draw.y,
  };
}

/** Inverse of spriteMeshPosition for a bare point (no anchor/size): converts
 *  a Three.js world coordinate back to a normalized 0..1 sprite position.
 *  Used by the editor's "draw route A→B" tool to turn mouse clicks into
 *  from/to. Mirrors the (xNorm-0.5)·REFERENCE·factor mapping exactly. */
export function worldToSpriteNorm(worldX, worldY, surfaceW = surface.w, surfaceH = surface.h) {
  const f = subjectFactor(surfaceW, surfaceH) || 1;
  return {
    x: 0.5 + worldX / (REFERENCE_SURFACE_W * f),
    y: 0.5 - worldY / (REFERENCE_SURFACE_H * f),
  };
}

export function spriteAnchorWorld(params, renderW, renderH, surfaceW = surface.w, surfaceH = surface.h) {
  const anchor = spriteAnchor(params);
  const mesh = spriteMeshPosition(params, renderW, renderH, surfaceW, surfaceH);
  return {
    x: mesh.x - (0.5 - anchor.x) * renderW,
    y: mesh.y + (0.5 - anchor.y) * renderH,
  };
}

export function retargetSpriteAnchor(params, newAnchorX, newAnchorY, renderW, renderH, surfaceW = surface.w, surfaceH = surface.h) {
  const old = spriteAnchor(params);
  const dxPx = (newAnchorX - old.x) * renderW;
  const dyPx = (newAnchorY - old.y) * renderH;
  const out = { ...params };
  out.anchor_x = newAnchorX;
  out.anchor_y = newAnchorY;
  out.x = (params.x ?? 0.5) + dxPx / surfaceW;
  out.y = (params.y ?? 0.5) + dyPx / surfaceH;
  return out;
}

export function worldDragToNormDelta(dxWorld, dyWorld, surfaceW = surface.w, surfaceH = surface.h) {
  return {
    dxNorm: dxWorld / surfaceW,
    dyNorm: -dyWorld / surfaceH,
  };
}