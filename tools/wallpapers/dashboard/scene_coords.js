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

/* ═══════════════════════════════════════════════════════════════════════
   BONE RIG — port fiel de RigController.kt (mantener en sync).
   Todo vive en "espacio Android": origen top-left, +Y ABAJO, rotación
   horaria positiva en grados, matrices con semántica post-concat (cada
   postX antepone por la izquierda: M' = X · M). El flip a mundo Three.js
   (+Y arriba, origen centro) se hace UNA vez al final con F·D·P.

   mat2d = [a, b, tx, c, d, ty]  →  (x,y) ↦ (a·x+b·y+tx, c·x+d·y+ty)
   ═══════════════════════════════════════════════════════════════════════ */

export function m2Identity() { return [1, 0, 0, 0, 1, 0]; }

/** A·B (aplica B primero, luego A). */
export function m2Mul(A, B) {
  return [
    A[0] * B[0] + A[1] * B[3],           A[0] * B[1] + A[1] * B[4],           A[0] * B[2] + A[1] * B[5] + A[2],
    A[3] * B[0] + A[4] * B[3],           A[3] * B[1] + A[4] * B[4],           A[3] * B[2] + A[4] * B[5] + A[5],
  ];
}
// post-ops: M' = OP · M  (igual que android.graphics.Matrix.postXxx)
export function m2PostTranslate(m, tx, ty) { return m2Mul([1, 0, tx, 0, 1, ty], m); }
export function m2PostScale(m, s) { return m2Mul([s, 0, 0, 0, s, 0], m); }
export function m2PostRotateDeg(m, deg) {
  const r = deg * Math.PI / 180, c = Math.cos(r), s = Math.sin(r);
  return m2Mul([c, -s, 0, s, c, 0], m);   // horario en espacio Y-abajo (Android)
}
export function m2PostConcat(m, other) { return m2Mul(other, m); }
export function m2Apply(m, x, y) { return { x: m[0] * x + m[1] * y + m[2], y: m[3] * x + m[4] * y + m[5] }; }

/** Espejo de RigController.sampleLocal: matriz local del hueso a la fase dada. */
export function rigSampleLocal(bone, phase, easing) {
  let dx = 0, dy = 0, rot = 0, s = 1;
  const kf = bone.keyframes || [];
  if (kf.length) {
    let i = 0;
    while (i < kf.length - 1 && phase >= (kf[i + 1].t ?? 0)) i++;
    const a = kf[i], c = (i + 1 < kf.length) ? kf[i + 1] : kf[i];
    const span = (c.t ?? 0) - (a.t ?? 0);
    let u = span > 1e-5 ? (phase - (a.t ?? 0)) / span : 0;
    u = Math.max(0, Math.min(1, u));
    if (easing === 'smooth') u = u * u * (3 - 2 * u);
    const lerp = (p, q) => p + (q - p) * u;
    dx = lerp(a.x ?? 0, c.x ?? 0);
    dy = lerp(a.y ?? 0, c.y ?? 0);
    rot = lerp(a.rotation ?? 0, c.rotation ?? 0);
    s = lerp(a.scale ?? 1, c.scale ?? 1);
  }
  const px = (bone.pivot_px || [0, 0])[0], py = (bone.pivot_px || [0, 0])[1];
  let m = m2Identity();
  m = m2PostTranslate(m, -px, -py);
  m = m2PostScale(m, s);
  m = m2PostRotateDeg(m, rot);
  m = m2PostTranslate(m, px + dx, py + dy);
  return m;
}

/** Espejo de la matriz global (espacio personaje → pantalla Android). */
export function rigGlobalMatrix(rig, rootPivot, sw = surface.w, sh = surface.h) {
  const f = subjectFactor(sw, sh);
  const k = (rig.scale ?? 1) * f;
  const ax = sw / 2 + ((rig.anchor?.[0] ?? 0.5) - 0.5) * REFERENCE_SURFACE_W * f;
  const ay = sh / 2 + ((rig.anchor?.[1] ?? 0.5) - 0.5) * REFERENCE_SURFACE_H * f;
  let g = m2Identity();
  g = m2PostTranslate(g, -rootPivot[0], -rootPivot[1]);
  g = m2PostScale(g, k);
  g = m2PostTranslate(g, ax, ay);
  return g;
}

function rigTopoSort(bones) {
  const byId = {}; bones.forEach(b => { byId[b.id] = b; });
  const out = [], seen = new Set();
  const visit = (b) => {
    if (seen.has(b.id)) return;
    if (b.parent && byId[b.parent] && !seen.has(b.parent)) visit(byId[b.parent]);
    seen.add(b.id); out.push(b);
  };
  bones.forEach(visit);
  return out;
}

/** Devuelve {boneId: worldMat2d} para todos los huesos a la fase dada. */
export function rigComposeWorld(rig, phase, sw = surface.w, sh = surface.h) {
  const bones = rig.bones || [];
  const root = bones.find(b => !b.parent) || bones[0];
  const rootPivot = root ? (root.pivot_px || [0, 0]) : [0, 0];
  const G = rigGlobalMatrix(rig, rootPivot, sw, sh);
  const world = {};
  for (const b of rigTopoSort(bones)) {
    let w = rigSampleLocal(b, phase, rig.easing);
    const parentW = b.parent ? world[b.parent] : null;
    w = m2PostConcat(w, parentW || G);
    world[b.id] = w;
  }
  return world;
}

/** Matriz de dibujo de la parte (incluye el offset del crop). D = W · T(offset). */
export function rigBoneDrawMatrix(worldMat, bone) {
  let d = m2Identity();
  d = m2PostTranslate(d, (bone.offset_px || [0, 0])[0], (bone.offset_px || [0, 0])[1]);
  d = m2PostConcat(d, worldMat);
  return d;
}

/** Flip pantalla-Android → mundo Three (origen centro, +Y arriba). */
export function rigScreenToWorldMat(sw = surface.w, sh = surface.h) {
  return [1, 0, -sw / 2, 0, -1, sh / 2];
}
/** Plane (origen centro, +Y arriba, tam natW×natH) → bitmap px (top-left, +Y abajo). */
export function rigPlaneToBitmapMat(natW, natH) {
  return [1, 0, natW / 2, 0, -1, natH / 2];
}

/**
 * Matriz completa mesh→mundo para una parte: M = F · D · P.
 * Llena y devuelve un THREE.Matrix4 (pásale la clase THREE).
 */
export function rigBoneMatrix4(THREE, worldMat, bone, natW, natH, zThree, sw = surface.w, sh = surface.h) {
  const D = rigBoneDrawMatrix(worldMat, bone);
  const M = m2Mul(rigScreenToWorldMat(sw, sh), m2Mul(D, rigPlaneToBitmapMat(natW, natH)));
  const m4 = new THREE.Matrix4();
  // M = [a,b,tx, c,d,ty]  → punto (x,y,0,1) ↦ (a·x+b·y+tx, c·x+d·y+ty, z)
  m4.set(
    M[0], M[1], 0, M[2],
    M[3], M[4], 0, M[5],
    0, 0, 1, zThree,
    0, 0, 0, 1,
  );
  return m4;
}

/** Posición en MUNDO Three del pivote de un hueso (para dibujar el crosshair). */
export function rigPivotWorld(worldMat, bone, sw = surface.w, sh = surface.h) {
  const p = bone.pivot_px || [0, 0];
  const screen = m2Apply(worldMat, p[0], p[1]);
  return m2Apply(rigScreenToWorldMat(sw, sh), screen.x, screen.y);
}

/** Delta de arrastre (mundo Three) → delta de anchor normalizado del rig. */
export function rigAnchorDragDelta(dxWorld, dyWorld, sw = surface.w, sh = surface.h) {
  const f = subjectFactor(sw, sh) || 1;
  return { dax: dxWorld / (REFERENCE_SURFACE_W * f), day: -dyWorld / (REFERENCE_SURFACE_H * f) };
}