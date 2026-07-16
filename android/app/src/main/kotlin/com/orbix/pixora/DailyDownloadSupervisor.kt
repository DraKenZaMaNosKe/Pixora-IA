package com.orbix.pixora

import android.content.Context
import android.graphics.BitmapFactory
import android.util.Log
import com.orbix.pixora.scene.SceneSpec
import org.json.JSONObject
import java.io.File
import java.net.HttpURLConnection
import java.net.URL
import java.util.zip.ZipInputStream

/**
 * DailyDownloadSupervisor — internal, verified download manager for Pixora
 * Daily canvas_scenes (2026-07-16).
 *
 * WHY THIS EXISTS
 * ---------------
 * Before this, scene content for Daily was downloaded by Dart
 * (`AutoRotateService._prefetchSceneMarkers`) as a fire-and-forget task inside
 * the app process. On OEMs that aggressively kill background apps (ZTE Axon,
 * MiFavor, MIUI…) that task dies mid-download, the scene cache stays empty, and
 * the native seed step (`AutoRotateWorker.seedDailyIfNeeded`) has nothing to
 * apply — so "Escenas 3D" rotates nothing while static/panoramic (downloaded by
 * the native worker) work fine. There was also a structural seed race: the
 * worker seeds before Dart's markers exist and nothing re-seeds for 6h.
 *
 * WHAT THIS DOES
 * --------------
 * A per-resource, verified, resumable download state machine that runs in the
 * MAIN process, driven by [AutoRotateWorker] (WorkManager — survives app death
 * and retries with backoff, which is exactly why static wallpapers already work
 * on the ZTE). For every scene it downloads and VERIFIES, in order:
 *
 *     spec (JSON) → image_layers → sprite packs → flat marker
 *
 * The flat marker (`<id>__scene.webp`, the rotation-pool eligibility signal) is
 * written LAST and only when every prior resource verified — so a scene appears
 * in the rotation pool only when it is fully renderable (atomicity by commit).
 * If the process dies mid-way there is no marker → the scene simply doesn't
 * exist yet for rotation, and the next worker run resumes the missing pieces.
 *
 * STATE
 * -----
 * `filesDir/pixora_daily/download_state.json` — per-resource status + byte
 * progress + attempts + last error, surfaced to Flutter via
 * `getDailyDownloadStatus` for the remote ZTE diagnosis (no logcat needed).
 * The `:wallpaper` process NEVER reads this file — its contract stays "files in
 * auto_rotate_cache/ + scene_specs/ + scene_layers/ + sprites/", so the
 * multi-process SharedPreferences pitfall is untouched.
 *
 * OWNERSHIP
 * ---------
 * Dart's `SceneSpecService` / `SpriteDownloadService` remain the owners of
 * *freshness* (revisions, FCM invalidation) and of the manual apply flow. This
 * supervisor is a presence-and-integrity fallback: it never overwrites a valid
 * existing file and writes the SAME on-disk formats (layer layout,
 * `.pixora_sprite_meta.json`), so a scene already hydrated by navigating the 3D
 * tab is recognized as complete (verify, not re-download).
 */
object DailyDownloadSupervisor {
    private const val TAG = "PixoraDailySup"
    private const val STATE_DIR = "pixora_daily"
    private const val STATE_FILE = "download_state.json"
    private const val SCHEMA = 1

    private const val MAX_ATTEMPTS = 6
    /** Per-attempt backoff before a FAILED resource is eligible again. */
    private val BACKOFF_MS = longArrayOf(0L, 60_000L, 300_000L, 900_000L, 3_600_000L, 3_600_000L)
    /** Layer bytes downloaded per supervision pass — caps mobile-data burst. */
    private const val LAYER_BUDGET_PER_RUN = 30L * 1024 * 1024

    private const val STORAGE_BASE =
        "https://vzuwvsmlyigjtsearxym.supabase.co/storage/v1/object/public"
    private const val SPRITES_BASE = "$STORAGE_BASE/wallpaper-sprites"

    private const val MIN_IMAGE_BYTES = 1024L
    private const val MIN_JSON_BYTES = 2L

    /** Serializes state file access. Only the worker + method channel touch it,
     *  both in the main process, so a JVM monitor is sufficient. */
    private val lock = Any()

    // Cached sprite manifest (per process), refreshed at most every 24h on disk.
    @Volatile private var manifestCache: JSONObject? = null

    // ── Public API ─────────────────────────────────────────────────────────

    /**
     * Rebuild the download plan for a fresh activation / category change.
     * Bumps `generation` (invalidates any in-flight pass with the old one),
     * replaces the scene set, and drops state for scenes no longer present.
     *
     * @param entries wire catalog lines "id|<id>__scene.webp|glow|scene|<flatUrl>|<specUrl>"
     */
    fun syncCatalog(context: Context, entries: List<String>, category: String?) {
        synchronized(lock) {
            val st = load(context)
            st.put("schema", SCHEMA)
            st.put("generation", st.optInt("generation", 0) + 1)
            st.put("category", category ?: "")
            val scenes = JSONObject()
            for (e in entries) {
                val p = e.split("|")
                if (p.getOrNull(3) != "scene") continue // type gate (req.4, native side)
                val id = p.getOrNull(0).orEmpty()
                val flat = p.getOrNull(4).orEmpty()
                val spec = p.getOrNull(5).orEmpty()
                if (id.isEmpty() || flat.isEmpty() || spec.isEmpty()) {
                    Log.w(TAG, "scene '$id' skipped — wire entry missing urls")
                    continue
                }
                scenes.put(id, JSONObject()
                    .put("flat_url", flat)
                    .put("spec_url", spec)
                    .put("resources", JSONObject()))
            }
            st.put("scenes", scenes)
            save(context, st)
            Log.d(TAG, "syncCatalog: gen=${st.optInt("generation")} cat=$category scenes=${scenes.length()}")
        }
    }

    /**
     * One supervision pass: advance every not-yet-complete resource of every
     * scene, verifying as it goes. Seeds Daily as soon as the first scene
     * commits a marker. MUST be called off the main thread (Worker.doWork is).
     *
     * @return true if retryable work remains (caller maps to Result.retry()).
     */
    fun runOnce(context: Context): Boolean {
        val gen: Int
        val ids: List<String>
        synchronized(lock) {
            val st = load(context)
            gen = st.optInt("generation", 0)
            val sc = st.optJSONObject("scenes") ?: JSONObject()
            ids = sc.keys().asSequence().toList()
        }
        if (ids.isEmpty()) return false

        var pending = false
        var committed = false
        for (id in ids) {
            when (superviseScene(context, id, gen)) {
                SceneOutcome.COMMITTED -> { committed = true }
                SceneOutcome.PENDING -> pending = true
                SceneOutcome.COMPLETE, SceneOutcome.PERMANENT, SceneOutcome.STALE -> {}
            }
        }
        if (committed) {
            // Seed the moment renderable content exists — kills the structural
            // seed race (worker used to seed before any marker existed).
            try {
                AutoRotateWorker.seedDailyIfNeeded(context)
            } catch (e: Exception) {
                Log.w(TAG, "seed after commit failed: ${e.message}")
            }
        }
        return pending
    }

    /** JSON snapshot of the download state, for Flutter telemetry. Pure read. */
    fun statusSnapshot(context: Context): String =
        synchronized(lock) { load(context).toString() }

    // ── Per-scene supervision ───────────────────────────────────────────────

    private enum class SceneOutcome { COMPLETE, COMMITTED, PENDING, PERMANENT, STALE }

    private fun superviseScene(context: Context, id: String, gen: Int): SceneOutcome {
        val filesDir = context.filesDir
        val marker = File(filesDir, "auto_rotate_cache/$id${PixoraWallpaperService.SCENE_MARKER_SUFFIX}")
        if (marker.isFile && marker.length() > MIN_IMAGE_BYTES) {
            mark(context, gen, id, "marker", "COMPLETE", marker.length(), null)
            return SceneOutcome.COMPLETE
        }

        val flatUrl = sceneField(context, id, "flat_url") ?: return SceneOutcome.STALE
        val specUrl = sceneField(context, id, "spec_url") ?: return SceneOutcome.STALE

        // 1. SPEC — download if absent, validate with the renderer's own parser
        //    (req.4: if the parser that will draw it can't read it, it isn't a
        //    valid 3D scene for this build).
        val specFile = File(filesDir, "scene_specs/$id.json")
        when (val r = step(context, gen, id, "spec", specFile, specUrl, MIN_JSON_BYTES) {
            SceneSpec.fromFile(it) != null
        }) {
            StepResult.COMPLETE -> {}
            StepResult.PENDING -> return SceneOutcome.PENDING
            StepResult.PERMANENT -> return SceneOutcome.PERMANENT
            StepResult.STALE -> return SceneOutcome.STALE
            StepResult.FAILED_THIS_PASS -> return SceneOutcome.PENDING
        }

        val spec = SceneSpec.fromFile(specFile) ?: run {
            // Should not happen — step verified it — but never trust a race.
            markFailed(context, gen, id, "spec", "SPEC_PARSE")
            return SceneOutcome.PENDING
        }

        // 2. IMAGE LAYERS — the expected set comes from the spec itself.
        var layerBudget = LAYER_BUDGET_PER_RUN
        for (layer in spec.imageLayers) {
            if (layer.key.isBlank() || layer.url.isBlank()) continue
            val lf = File(filesDir, "scene_layers/$id/${layer.key}.webp")
            if (lf.isFile && lf.length() > MIN_IMAGE_BYTES && decodableImage(lf)) continue
            if (layerBudget <= 0) return SceneOutcome.PENDING // resume next pass
            when (step(context, gen, id, "layer:${layer.key}", lf, layer.url, MIN_IMAGE_BYTES,
                    onBytes = { layerBudget -= it }) { decodableImage(it) }) {
                StepResult.COMPLETE -> {}
                StepResult.PENDING, StepResult.FAILED_THIS_PASS -> return SceneOutcome.PENDING
                StepResult.PERMANENT -> return SceneOutcome.PERMANENT
                StepResult.STALE -> return SceneOutcome.STALE
            }
        }

        // 3. SPRITE PACKS — expected set = spec.sprites[].manifestKey (req.3:
        //    "the right sprites for THIS wallpaper" is defined by its spec).
        for (sprite in spec.sprites) {
            val key = sprite.manifestKey
            if (key.isBlank()) continue
            when (ensureSpritePack(context, gen, id, key)) {
                StepResult.COMPLETE -> {}
                StepResult.PENDING, StepResult.FAILED_THIS_PASS -> return SceneOutcome.PENDING
                StepResult.PERMANENT -> return SceneOutcome.PERMANENT
                StepResult.STALE -> return SceneOutcome.STALE
            }
        }

        // 4. MARKER — the commit. Only reachable when 1-3 all verified.
        return when (step(context, gen, id, "marker", marker, flatUrl, MIN_IMAGE_BYTES) {
            decodableImage(it)
        }) {
            StepResult.COMPLETE -> {
                Log.i(TAG, "scene $id COMMITTED — all resources verified")
                SceneOutcome.COMMITTED
            }
            StepResult.PENDING, StepResult.FAILED_THIS_PASS -> SceneOutcome.PENDING
            StepResult.PERMANENT -> SceneOutcome.PERMANENT
            StepResult.STALE -> SceneOutcome.STALE
        }
    }

    private enum class StepResult { COMPLETE, PENDING, PERMANENT, STALE, FAILED_THIS_PASS }

    /**
     * Download-if-needed + verify + state bookkeeping for ONE file resource.
     * Idempotent: an existing verifying file short-circuits to COMPLETE. Every
     * failure path records a reason — no silent catches (req.6).
     */
    private fun step(
        context: Context,
        gen: Int,
        sceneId: String,
        res: String,
        target: File,
        url: String,
        minBytes: Long,
        onBytes: (Long) -> Unit = {},
        verify: (File) -> Boolean,
    ): StepResult {
        // Already present & valid?
        if (target.isFile && target.length() > minBytes &&
            runCatching { verify(target) }.getOrDefault(false)) {
            mark(context, gen, sceneId, res, "COMPLETE", target.length(), null)
            return StepResult.COMPLETE
        }
        when (retryEligibility(context, sceneId, res)) {
            Eligibility.PERMANENT -> return StepResult.PERMANENT
            Eligibility.BACKOFF -> return StepResult.PENDING
            Eligibility.OK -> {}
        }
        if (mark(context, gen, sceneId, res, "DOWNLOADING", 0, null) == MarkResult.STALE) {
            return StepResult.STALE
        }
        target.parentFile?.mkdirs()
        val tmp = File(target.parentFile, "${target.name}.tmp")
        val err = download(url, tmp)
        if (err != null) {
            tmp.delete()
            markFailed(context, gen, sceneId, res, err)
            return StepResult.FAILED_THIS_PASS
        }
        onBytes(tmp.length())
        mark(context, gen, sceneId, res, "VERIFYING", tmp.length(), null)
        val ok = runCatching { verify(tmp) }.getOrElse {
            markFailed(context, gen, sceneId, res, "IO:${it.message?.take(60)}")
            false
        }
        if (!ok) {
            tmp.delete()
            markFailed(context, gen, sceneId, res, "VERIFY_DECODE")
            return StepResult.FAILED_THIS_PASS
        }
        if (!tmp.renameTo(target)) {
            tmp.delete()
            markFailed(context, gen, sceneId, res, "IO:rename")
            return StepResult.FAILED_THIS_PASS
        }
        mark(context, gen, sceneId, res, "COMPLETE", target.length(), null)
        return StepResult.COMPLETE
    }

    /**
     * Sprite pack: manifest lookup → sized ZIP → clean unzip → frame-count +
     * decode verification → Dart-compatible meta. The whole folder is wiped
     * before extraction so a partial/corrupt prior attempt can't linger (req.5).
     */
    private fun ensureSpritePack(context: Context, gen: Int, sceneId: String, key: String): StepResult {
        val res = "sprite:$key"
        val dir = File(context.filesDir, "sprites/$key")
        val manifest = spriteManifest(context)
        val info = manifest?.optJSONObject(key)
        if (info == null) {
            // Not in the manifest — can't verify integrity, treat as permanent
            // so we don't loop forever; surfaced in telemetry.
            markFailed(context, gen, sceneId, res, "MANIFEST_MISSING_KEY", permanent = true)
            return StepResult.PERMANENT
        }
        val frames = info.optInt("frames", 1)
        val zipSize = info.optLong("size", -1L)
        val zipPath = info.optString("zip")

        if (validSpritePack(dir, frames, zipSize)) {
            mark(context, gen, sceneId, res, "COMPLETE", zipSize.coerceAtLeast(0), null)
            return StepResult.COMPLETE
        }
        if (zipPath.isBlank()) {
            markFailed(context, gen, sceneId, res, "MANIFEST_MISSING_KEY", permanent = true)
            return StepResult.PERMANENT
        }
        when (retryEligibility(context, sceneId, res)) {
            Eligibility.PERMANENT -> return StepResult.PERMANENT
            Eligibility.BACKOFF -> return StepResult.PENDING
            Eligibility.OK -> {}
        }
        if (mark(context, gen, sceneId, res, "DOWNLOADING", 0, null) == MarkResult.STALE) {
            return StepResult.STALE
        }
        val tmpZip = File(context.cacheDir, "sprite_${key.replace('/', '_')}.zip.tmp")
        val err = download("$SPRITES_BASE/$zipPath", tmpZip)
        if (err != null) {
            tmpZip.delete()
            markFailed(context, gen, sceneId, res, err)
            return StepResult.FAILED_THIS_PASS
        }
        if (zipSize > 0 && tmpZip.length() != zipSize) {
            val got = tmpZip.length()
            tmpZip.delete()
            markFailed(context, gen, sceneId, res, "VERIFY_ZIP_SIZE($got/$zipSize)")
            return StepResult.FAILED_THIS_PASS
        }
        mark(context, gen, sceneId, res, "VERIFYING", tmpZip.length(), null)
        dir.deleteRecursively()
        dir.mkdirs()
        var extracted = 0
        val unzipErr = try {
            ZipInputStream(tmpZip.inputStream().buffered()).use { zin ->
                var entry = zin.nextEntry
                while (entry != null) {
                    if (!entry.isDirectory && entry.name.endsWith(".png")) {
                        File(dir, File(entry.name).name).outputStream().use { zin.copyTo(it) }
                        extracted++
                    }
                    entry = zin.nextEntry
                }
            }
            null
        } catch (e: Exception) {
            "IO:${e.message?.take(60)}"
        } finally {
            tmpZip.delete()
        }
        if (unzipErr != null) {
            dir.deleteRecursively()
            markFailed(context, gen, sceneId, res, unzipErr)
            return StepResult.FAILED_THIS_PASS
        }
        val pngs = dir.listFiles()?.filter { it.name.endsWith(".png") } ?: emptyList()
        if (extracted != frames || pngs.size != frames || !pngs.all { pngDecodable(it) }) {
            dir.deleteRecursively()
            markFailed(context, gen, sceneId, res, "VERIFY_SPRITE_COUNT($extracted/$frames)")
            return StepResult.FAILED_THIS_PASS
        }
        // Dart-compatible meta so SpriteDownloadService._isCached agrees.
        runCatching {
            File(dir, ".pixora_sprite_meta.json")
                .writeText(JSONObject().put("frames", frames).put("zip_size", zipSize).toString())
        }
        mark(context, gen, sceneId, res, "COMPLETE", zipSize.coerceAtLeast(0), null)
        return StepResult.COMPLETE
    }

    // ── Verification helpers ────────────────────────────────────────────────

    /** True if the file decodes as an image (bounds only — cheap, catches
     *  truncated/corrupt WebP/PNG without a full decode). */
    private fun decodableImage(f: File): Boolean = try {
        val opts = BitmapFactory.Options().apply { inJustDecodeBounds = true }
        BitmapFactory.decodeFile(f.absolutePath, opts)
        opts.outWidth > 0 && opts.outHeight > 0
    } catch (_: Exception) { false }

    private fun pngDecodable(f: File): Boolean = f.length() > 0 && decodableImage(f)

    private fun validSpritePack(dir: File, frames: Int, zipSize: Long): Boolean {
        if (!dir.isDirectory) return false
        val pngs = dir.listFiles()?.filter { it.name.endsWith(".png") } ?: return false
        if (pngs.size != frames) return false
        if (zipSize <= 0) return true
        val meta = File(dir, ".pixora_sprite_meta.json")
        if (!meta.isFile) return true // legacy folder — trust frame count
        return runCatching {
            JSONObject(meta.readText()).optLong("zip_size", -1L) == zipSize
        }.getOrDefault(false)
    }

    // ── Network ─────────────────────────────────────────────────────────────

    /** Downloads [url] into [target]. Returns null on success, or an error
     *  string from the closed taxonomy (HTTP_<code> / TIMEOUT / IO:<msg>). */
    private fun download(url: String, target: File): String? {
        var conn: HttpURLConnection? = null
        return try {
            target.parentFile?.mkdirs()
            conn = (URL(url).openConnection() as HttpURLConnection).apply {
                connectTimeout = 15_000
                readTimeout = 30_000
            }
            val code = conn.responseCode
            if (code != HttpURLConnection.HTTP_OK) return "HTTP_$code"
            conn.inputStream.use { input ->
                target.outputStream().use { output -> input.copyTo(output, 8192) }
            }
            null
        } catch (e: java.net.SocketTimeoutException) {
            target.delete(); "TIMEOUT"
        } catch (e: Exception) {
            target.delete(); "IO:${e.message?.take(60)}"
        } finally {
            conn?.disconnect()
        }
    }

    private fun spriteManifest(context: Context): JSONObject? {
        manifestCache?.let { return it }
        val cacheFile = File(context.filesDir, "sprites/manifest.json")
        // Reuse Dart's on-disk manifest when fresh (<24h) — same file, one source.
        if (cacheFile.isFile &&
            System.currentTimeMillis() - cacheFile.lastModified() < 24L * 3600 * 1000) {
            runCatching { JSONObject(cacheFile.readText()) }.getOrNull()?.let {
                manifestCache = it; return it
            }
        }
        val tmp = File(context.cacheDir, "sprite_manifest.json.tmp")
        if (download("$SPRITES_BASE/manifest.json", tmp) == null) {
            val obj = runCatching { JSONObject(tmp.readText()) }.getOrNull()
            tmp.delete()
            if (obj != null) {
                runCatching {
                    cacheFile.parentFile?.mkdirs()
                    cacheFile.writeText(obj.toString())
                }
                manifestCache = obj
                return obj
            }
        }
        tmp.delete()
        // Fall back to a stale on-disk copy rather than failing outright.
        if (cacheFile.isFile) {
            return runCatching { JSONObject(cacheFile.readText()) }.getOrNull()
                ?.also { manifestCache = it }
        }
        return null
    }

    // ── State persistence ───────────────────────────────────────────────────

    private fun stateFile(context: Context): File {
        val dir = File(context.filesDir, STATE_DIR)
        if (!dir.exists()) dir.mkdirs()
        return File(dir, STATE_FILE)
    }

    private fun load(context: Context): JSONObject {
        val f = stateFile(context)
        if (!f.isFile) return JSONObject().put("schema", SCHEMA).put("generation", 0)
            .put("scenes", JSONObject())
        return runCatching { JSONObject(f.readText()) }.getOrElse {
            JSONObject().put("schema", SCHEMA).put("generation", 0).put("scenes", JSONObject())
        }
    }

    private fun save(context: Context, st: JSONObject) {
        st.put("updated_at", System.currentTimeMillis())
        val f = stateFile(context)
        val tmp = File(f.parentFile, "$STATE_FILE.tmp")
        runCatching {
            tmp.writeText(st.toString())
            if (!tmp.renameTo(f)) { f.delete(); tmp.renameTo(f) }
        }.onFailure { tmp.delete() }
    }

    private enum class MarkResult { OK, STALE }

    /** Records a resource state transition. Returns STALE (and writes nothing)
     *  when a newer generation has superseded this pass. */
    private fun mark(
        context: Context, gen: Int, sceneId: String, res: String,
        state: String, bytes: Long, error: String?,
    ): MarkResult = synchronized(lock) {
        val st = load(context)
        if (st.optInt("generation", 0) != gen) return MarkResult.STALE
        val scene = st.optJSONObject("scenes")?.optJSONObject(sceneId) ?: return MarkResult.OK
        val resources = scene.optJSONObject("resources") ?: JSONObject().also {
            scene.put("resources", it)
        }
        val prev = resources.optJSONObject(res) ?: JSONObject()
        prev.put("st", state).put("bytes", bytes)
        if (error != null) prev.put("last_error", error) else prev.remove("last_error")
        resources.put(res, prev)
        save(context, st)
        MarkResult.OK
    }

    // Block body (not expression body): android.util.Log.w returns Int, which
    // would make an expression-bodied `= synchronized { … Log.w() }` infer an
    // Int return type and reject the bare early `return`s.
    private fun markFailed(
        context: Context, gen: Int, sceneId: String, res: String,
        error: String, permanent: Boolean = false,
    ) {
        synchronized(lock) {
            val st = load(context)
            if (st.optInt("generation", 0) != gen) return
            val scene = st.optJSONObject("scenes")?.optJSONObject(sceneId) ?: return
            val resources = scene.optJSONObject("resources") ?: JSONObject().also {
                scene.put("resources", it)
            }
            val prev = resources.optJSONObject(res) ?: JSONObject()
            val attempts = prev.optInt("attempts", 0) + 1
            val done = permanent || attempts >= MAX_ATTEMPTS
            prev.put("st", if (done) "FAILED_PERMANENT" else "FAILED")
                .put("attempts", attempts)
                .put("last_error", error)
                .put("next_retry_at",
                    System.currentTimeMillis() + BACKOFF_MS[attempts.coerceAtMost(BACKOFF_MS.size - 1)])
            resources.put(res, prev)
            save(context, st)
            Log.w(TAG, "scene $sceneId/$res FAILED ($attempts/$MAX_ATTEMPTS): $error")
        }
    }

    private enum class Eligibility { OK, BACKOFF, PERMANENT }

    private fun retryEligibility(context: Context, sceneId: String, res: String): Eligibility =
        synchronized(lock) {
            val r = load(context).optJSONObject("scenes")?.optJSONObject(sceneId)
                ?.optJSONObject("resources")?.optJSONObject(res) ?: return Eligibility.OK
            when (r.optString("st")) {
                "FAILED_PERMANENT" -> Eligibility.PERMANENT
                "FAILED" ->
                    if (System.currentTimeMillis() >= r.optLong("next_retry_at", 0))
                        Eligibility.OK else Eligibility.BACKOFF
                else -> Eligibility.OK
            }
        }

    private fun sceneField(context: Context, sceneId: String, field: String): String? =
        synchronized(lock) {
            load(context).optJSONObject("scenes")?.optJSONObject(sceneId)
                ?.optString(field)?.takeIf { it.isNotEmpty() }
        }
}
