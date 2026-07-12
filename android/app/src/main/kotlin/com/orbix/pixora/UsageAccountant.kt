package com.orbix.pixora

import android.content.Context
import android.os.Build
import android.os.Handler
import android.os.HandlerThread
import android.os.SystemClock
import android.util.Log
import org.json.JSONArray
import org.json.JSONObject
import java.io.File
import java.io.FileOutputStream
import java.net.HttpURLConnection
import java.net.URL

/**
 * UsageAccountant (F1 part 2) — measures the REAL time a live wallpaper is
 * visible on screen and reports it to the Supabase `usage_report` RPC, so the
 * admin dashboard can show real usage hours per wallpaper.
 *
 * Lives in the isolated `:wallpaper` process. Design by a Fable 5 subagent,
 * reviewed by Opus. See project_presence_usage_tracking memory.
 *
 * Key invariants:
 *  - Durations use SystemClock.elapsedRealtime() ONLY (monotonic, advances
 *    only while the phone is ON). Wall clock (currentTimeMillis) is used solely
 *    as the `segment_start` label — never to compute a duration. Clock jumps /
 *    NTP / timezone changes can't corrupt accounting.
 *  - Exactly ONE open segment at a time, guarded by a visible-engine refcount.
 *  - The open segment is checkpointed to disk every 60s so a process kill loses
 *    at most 60s. entry_id is generated once at OPEN and persisted, so a
 *    recovered or retried segment keeps the same id — the server's
 *    (device_id, entry_id) unique constraint makes reporting idempotent.
 *  - Closed segments go to an append-only ledger (fsync'd). Flush sends the
 *    WHOLE ledger in ONE POST (never split — the server's anti-cheat clamp
 *    would truncate a second sequential call).
 *  - All state is touched only on the internal HandlerThread. The POST blocks
 *    that thread (≤45s), never the render thread.
 */
object UsageAccountant {
    private const val TAG = "PixoraUsage"

    private const val MIN_SEGMENT_S = 5
    private const val CHECKPOINT_MS = 60_000L
    private const val ROLL_MS = 1_800_000L          // 30 min → cap per credit
    private const val FLUSH_MIN_PENDING_S = 60
    private const val MAX_BATCH = 200
    private const val MAX_LEDGER_LINES = 500
    private const val SEG_CAP_S = 21_600            // 6h defensive cap
    private const val RECOVER_DELAY_MS = 3_000L

    private const val CHECKPOINT_FILE = "usage_open_segment.json"
    private const val LEDGER_FILE = "usage_ledger.jsonl"
    private const val IDENTITY_FILE = "pixora_identity.json"

    private lateinit var appContext: Context
    private var handler: Handler? = null
    @Volatile private var initialized = false

    // ── State — only touched on the handler thread ──
    private var visibleCount = 0
    private var occluded = false
    private var openSegment: Segment? = null
    private var nextRetryAtElapsed = 0L
    private var backoffMs = 0L
    private var catalogCache: Map<String, String>? = null
    private var identityCache: Identity? = null

    private data class Segment(
        val entryId: String,
        val contentId: String,
        val isDaily: Boolean,
        val segmentStartWallMs: Long,
        val startElapsed: Long,
        var lastCheckpointElapsed: Long,
    )

    private data class Identity(
        val deviceId: String,
        val supabaseUrl: String,
        val anonKey: String,
        val appVersion: String?,
    )

    @Synchronized
    fun init(context: Context) {
        if (initialized) return
        appContext = context.applicationContext
        val thread = HandlerThread("PixoraUsage").apply { start() }
        handler = Handler(thread.looper)
        initialized = true
    }

    private fun post(block: () -> Unit) {
        handler?.post(block)
    }

    // ── Public API — capture elapsed/wall at the call-site to avoid queue latency ──

    fun engineVisible() {
        val now = SystemClock.elapsedRealtime()
        val wall = System.currentTimeMillis()
        post {
            visibleCount++
            if (visibleCount == 1 && !occluded && openSegment == null) {
                openSegment(now, wall)
            }
        }
    }

    fun engineHidden() {
        val now = SystemClock.elapsedRealtime()
        post {
            if (visibleCount > 0) visibleCount--
            if (visibleCount == 0 && openSegment != null) {
                closeSegment(now)
                maybeFlush(now, force = false)
            }
        }
    }

    /** onDestroy — idempotent equivalent of a visibility=false for this engine. */
    fun engineGone() = engineHidden()

    /** Ad overlay covering the wallpaper — pause accounting (no flush). */
    fun setOccluded(value: Boolean) {
        val now = SystemClock.elapsedRealtime()
        val wall = System.currentTimeMillis()
        post {
            if (value == occluded) return@post
            occluded = value
            if (occluded) {
                if (openSegment != null) closeSegment(now)
            } else {
                if (visibleCount > 0 && openSegment == null) openSegment(now, wall)
            }
        }
    }

    /** Wallpaper changed under our feet (Daily rotation, Story, DayCycle, …). */
    fun wallpaperChanged() {
        val now = SystemClock.elapsedRealtime()
        val wall = System.currentTimeMillis()
        post {
            if (openSegment != null) closeSegment(now)
            catalogCache = null // catalog may have changed; force a re-read
            if (visibleCount > 0 && !occluded) openSegment(now, wall)
        }
    }

    /** onCreate — recover a segment orphaned by a kill, then flush the backlog. */
    fun recoverAndMaybeFlush() {
        post {
            recoverOrphan()
            handler?.postDelayed({
                maybeFlush(SystemClock.elapsedRealtime(), force = true)
            }, RECOVER_DELAY_MS)
        }
    }

    // ── Segment lifecycle (handler thread only) ──

    private fun openSegment(nowElapsed: Long, wallMs: Long) {
        if (openSegment != null) return
        val (contentId, isDaily) = resolveContent()
        val entryId = "e_${wallMs}_${randomSuffix(wallMs)}"
        val seg = Segment(entryId, contentId, isDaily, wallMs, nowElapsed, nowElapsed)
        openSegment = seg
        writeCheckpoint(seg)
        scheduleCheckpoint()
        Log.d(TAG, "segment OPEN id=$contentId daily=$isDaily entry=$entryId")
    }

    private fun closeSegment(nowElapsed: Long) {
        val seg = openSegment ?: return
        openSegment = null
        cancelCheckpoint()
        deleteCheckpoint()
        var seconds = ((nowElapsed - seg.startElapsed) / 1000L).toInt()
        if (seconds < MIN_SEGMENT_S) {
            Log.d(TAG, "segment DISCARD (<${MIN_SEGMENT_S}s) id=${seg.contentId}")
            return
        }
        if (seconds > SEG_CAP_S) seconds = SEG_CAP_S
        appendLedger(seg, seconds)
        Log.d(TAG, "segment CLOSE id=${seg.contentId} seconds=$seconds")
    }

    private val checkpointRunnable = Runnable { onCheckpoint() }

    private fun scheduleCheckpoint() {
        handler?.postDelayed(checkpointRunnable, CHECKPOINT_MS)
    }

    private fun cancelCheckpoint() {
        handler?.removeCallbacks(checkpointRunnable)
    }

    private fun onCheckpoint() {
        val seg = openSegment ?: return
        val now = SystemClock.elapsedRealtime()
        // Roll a very long segment so no single credit exceeds ROLL_MS and a
        // screen-always-on user still produces flushable material.
        if (now - seg.startElapsed >= ROLL_MS) {
            closeSegment(now)
            openSegment(now, System.currentTimeMillis())
            maybeFlush(now, force = false)
            return
        }
        seg.lastCheckpointElapsed = now
        writeCheckpoint(seg)
        scheduleCheckpoint()
    }

    // ── Content id resolution (reads the same in-process prefs view) ──

    /** @return (contentId, isDaily). */
    private fun resolveContent(): Pair<String, Boolean> {
        return try {
            val prefs = appContext.getSharedPreferences("pixora_live", Context.MODE_PRIVATE)
            val path = prefs.getString("wallpaper_path", "") ?: ""
            val sceneId = prefs.getString("scene_id", null)
            val isDaily = path.contains("auto_rotate_cache")
            // 1. canvas_scene — the scene id IS the catalog row id.
            if (!sceneId.isNullOrBlank()) return sceneId to isDaily
            val base = path.substringAfterLast('/').substringAfterLast('\\')
            // 2. Daily rotation.
            if (isDaily) {
                if (base.endsWith(PixoraWallpaperService.SCENE_MARKER_SUFFIX)) {
                    return base.removeSuffix(PixoraWallpaperService.SCENE_MARKER_SUFFIX) to true
                }
                catalogMap()[base]?.let { return it to true }
                return "file:${base.substringBeforeLast('.')}" to true
            }
            // 3. Manual apply — content_id written to prefs by MainActivity,
            //    trusted only if the path still matches (guard vs stale prefs).
            val cid = prefs.getString("content_id", null)
            if (!cid.isNullOrBlank()) return cid to false
            "file:${base.substringBeforeLast('.')}" to false
        } catch (e: Exception) {
            "unknown" to false
        }
    }

    /** basename(file.replace("/","_")) → catalog id, parsed from the Daily catalog. */
    private fun catalogMap(): Map<String, String> {
        catalogCache?.let { return it }
        val m = HashMap<String, String>()
        try {
            val ar = appContext.getSharedPreferences("pixora_auto_rotate", Context.MODE_PRIVATE)
            val raw = ar.getString("catalog_json", null)
            raw?.split("\n")?.forEach { line ->
                val parts = line.split("|")
                if (parts.size >= 2) {
                    val id = parts[0]
                    val file = parts[1]
                    if (id.isNotEmpty() && file.isNotEmpty()) {
                        m[file.replace("/", "_")] = id
                    }
                }
            }
        } catch (e: Exception) {
            Log.w(TAG, "catalogMap parse failed: ${e.message}")
        }
        catalogCache = m
        return m
    }

    // ── Checkpoint file (survives a kill of the open segment) ──

    private fun writeCheckpoint(seg: Segment) {
        try {
            val json = JSONObject().apply {
                put("entry_id", seg.entryId)
                put("content_id", seg.contentId)
                put("is_daily", seg.isDaily)
                put("segment_start_wall", seg.segmentStartWallMs)
                put("start_elapsed", seg.startElapsed)
                put("last_checkpoint_elapsed", seg.lastCheckpointElapsed)
            }
            val tmp = File(appContext.filesDir, "$CHECKPOINT_FILE.tmp")
            tmp.writeText(json.toString())
            tmp.renameTo(File(appContext.filesDir, CHECKPOINT_FILE))
        } catch (e: Exception) {
            Log.w(TAG, "checkpoint write failed: ${e.message}")
        }
    }

    private fun deleteCheckpoint() {
        try {
            File(appContext.filesDir, CHECKPOINT_FILE).delete()
        } catch (_: Exception) {
        }
    }

    private fun recoverOrphan() {
        try {
            val f = File(appContext.filesDir, CHECKPOINT_FILE)
            if (!f.isFile) return
            val json = JSONObject(f.readText())
            f.delete()
            val startElapsed = json.getLong("start_elapsed")
            val lastCp = json.getLong("last_checkpoint_elapsed")
            // Both timestamps are from the SAME boot; if the process died and
            // the phone rebooted, elapsedRealtime reset — but we only use the
            // stored delta, never mix with the current clock. Incoherent → drop.
            if (lastCp < startElapsed) {
                Log.w(TAG, "recover: incoherent checkpoint, discard")
                return
            }
            var seconds = ((lastCp - startElapsed) / 1000L).toInt()
            if (seconds < MIN_SEGMENT_S) return
            if (seconds > SEG_CAP_S) seconds = SEG_CAP_S
            val seg = Segment(
                json.getString("entry_id"),
                json.getString("content_id"),
                json.optBoolean("is_daily", false),
                json.getLong("segment_start_wall"),
                startElapsed, lastCp,
            )
            appendLedger(seg, seconds)
            Log.d(TAG, "recover: orphan segment ${seconds}s id=${seg.contentId} entry=${seg.entryId}")
        } catch (e: Exception) {
            Log.w(TAG, "recover failed: ${e.message}")
        }
    }

    // ── Ledger (append-only, fsync'd) ──

    private fun appendLedger(seg: Segment, seconds: Int) {
        try {
            val line = JSONObject().apply {
                put("entry_id", seg.entryId)
                put("content_id", seg.contentId)
                put("is_daily", seg.isDaily)
                put("seconds", seconds)
                put("segment_start", iso8601(seg.segmentStartWallMs))
                put("v", 1)
            }.toString()
            val f = File(appContext.filesDir, LEDGER_FILE)
            FileOutputStream(f, true).use { fos ->
                fos.write((line + "\n").toByteArray(Charsets.UTF_8))
                fos.flush()
                fos.fd.sync()
            }
        } catch (e: Exception) {
            Log.w(TAG, "ledger append failed: ${e.message}")
        }
    }

    private fun readLedger(): List<JSONObject> {
        val f = File(appContext.filesDir, LEDGER_FILE)
        if (!f.isFile) return emptyList()
        val out = ArrayList<JSONObject>()
        val seen = HashSet<String>()
        try {
            f.readLines().forEach { line ->
                if (line.isBlank()) return@forEach
                try {
                    val o = JSONObject(line)
                    val eid = o.optString("entry_id")
                    val secs = o.optInt("seconds", 0)
                    // Skip corrupt/half-written lines and duplicate entry_ids.
                    if (eid.isNotEmpty() && secs in 1..86400 && seen.add(eid)) out.add(o)
                } catch (_: Exception) {
                    // half-written last line after a kill — ignore
                }
            }
        } catch (e: Exception) {
            Log.w(TAG, "ledger read failed: ${e.message}")
        }
        return out
    }

    private fun compactLedger(confirmedIds: Set<String>) {
        val remaining = readLedger().filter { it.optString("entry_id") !in confirmedIds }
        val capped =
            if (remaining.size > MAX_LEDGER_LINES) remaining.takeLast(MAX_LEDGER_LINES)
            else remaining
        val f = File(appContext.filesDir, LEDGER_FILE)
        try {
            if (capped.isEmpty()) {
                f.delete()
                return
            }
            val tmp = File(appContext.filesDir, "$LEDGER_FILE.tmp")
            tmp.writeText(capped.joinToString("\n") { it.toString() } + "\n")
            tmp.renameTo(f)
        } catch (e: Exception) {
            Log.w(TAG, "ledger compact failed: ${e.message}")
        }
    }

    // ── Flush ──

    private fun maybeFlush(nowElapsed: Long, force: Boolean) {
        if (nowElapsed < nextRetryAtElapsed) return
        val entries = readLedger()
        if (entries.isEmpty()) return
        if (!force) {
            val totalSeconds = entries.sumOf { it.optInt("seconds", 0) }
            if (totalSeconds < FLUSH_MIN_PENDING_S) return
        }
        doFlush(entries, nowElapsed)
    }

    private fun doFlush(entries: List<JSONObject>, nowElapsed: Long) {
        val id = identity()
        if (id == null) {
            Log.d(TAG, "identity file missing — accumulating offline")
            return
        }
        val batch = if (entries.size > MAX_BATCH) entries.subList(0, MAX_BATCH) else entries
        val sentIds = HashSet<String>()
        val credits = JSONArray()
        for (e in batch) {
            val eid = e.getString("entry_id")
            sentIds.add(eid)
            credits.put(JSONObject().apply {
                put("kind", "wallpaper")
                put("content_id", e.getString("content_id"))
                put("is_daily", e.optBoolean("is_daily", false))
                put("seconds", e.getInt("seconds"))
                put("segment_start", e.optString("segment_start"))
                put("entry_id", eid)
            })
        }
        val body = JSONObject().apply {
            put("p_device_id", id.deviceId)
            put("p_state", stateJson(id))
            put("p_credits", credits)
        }
        val totalSec = (0 until credits.length()).sumOf { credits.getJSONObject(it).getInt("seconds") }
        Log.d(TAG, "flush: sending ${batch.size} credits (${totalSec}s total)")
        val code = postRpc(id, body)
        if (code in 200..299) {
            compactLedger(sentIds)
            backoffMs = 0
            nextRetryAtElapsed = 0
            Log.d(TAG, "flush OK code=$code")
        } else {
            backoffMs = if (backoffMs == 0L) 60_000L else minOf(backoffMs * 5, ROLL_MS)
            nextRetryAtElapsed = nowElapsed + backoffMs
            Log.w(TAG, "flush FAIL code=$code retry in ${backoffMs / 1000}s")
        }
    }

    private fun stateJson(id: Identity): JSONObject {
        val prefs = appContext.getSharedPreferences("pixora_live", Context.MODE_PRIVATE)
        val path = prefs.getString("wallpaper_path", "") ?: ""
        val sceneId = prefs.getString("scene_id", null)
        val (cid, isDaily) = resolveContent()
        val kind = when {
            isDaily -> "daily"
            !sceneId.isNullOrBlank() -> "canvas_scene"
            path.endsWith(".mp4", ignoreCase = true) -> "live_video"
            else -> "static"
        }
        return JSONObject().apply {
            put("source", "wallpaper")
            put("active_kind", kind)
            if (cid.isNotEmpty() && !cid.startsWith("file:")) put("active_wallpaper_id", cid)
            put("daily_enabled", isDaily)
            put("device_model", Build.MODEL)
            put("android_sdk", Build.VERSION.SDK_INT)
            id.appVersion?.let { put("app_version", it) }
        }
    }

    private fun postRpc(id: Identity, body: JSONObject): Int {
        var conn: HttpURLConnection? = null
        return try {
            val url = URL("${id.supabaseUrl}/rest/v1/rpc/usage_report")
            conn = (url.openConnection() as HttpURLConnection).apply {
                requestMethod = "POST"
                connectTimeout = 15_000
                readTimeout = 30_000
                doOutput = true
                setRequestProperty("Content-Type", "application/json")
                setRequestProperty("apikey", id.anonKey)
                setRequestProperty("Authorization", "Bearer ${id.anonKey}")
            }
            conn.outputStream.use { it.write(body.toString().toByteArray(Charsets.UTF_8)) }
            val code = conn.responseCode
            try {
                (if (code in 200..299) conn.inputStream else conn.errorStream)?.use { it.readBytes() }
            } catch (_: Exception) {
            }
            code
        } catch (e: Exception) {
            Log.w(TAG, "postRpc failed: ${e.message}")
            -1
        } finally {
            conn?.disconnect()
        }
    }

    // ── Identity bridge ──

    private fun identity(): Identity? {
        identityCache?.let { return it }
        return try {
            val f = File(appContext.filesDir, IDENTITY_FILE)
            if (!f.isFile) return null
            val o = JSONObject(f.readText())
            val did = o.optString("device_id")
            val url = o.optString("supabase_url")
            val key = o.optString("anon_key")
            if (did.isEmpty() || url.isEmpty() || key.isEmpty()) return null
            val appVer = if (o.has("app_version") && !o.isNull("app_version")) {
                o.optString("app_version")
            } else null
            Identity(did, url, key, appVer).also { identityCache = it }
        } catch (e: Exception) {
            Log.w(TAG, "identity read failed: ${e.message}")
            null
        }
    }

    // ── Helpers ──

    private fun iso8601(wallMs: Long): String {
        val fmt = java.text.SimpleDateFormat("yyyy-MM-dd'T'HH:mm:ss.SSS'Z'", java.util.Locale.US)
        fmt.timeZone = java.util.TimeZone.getTimeZone("UTC")
        return fmt.format(java.util.Date(wallMs))
    }

    /** Deterministic-per-open random-ish suffix (no Math.random dependency,
     *  which is banned in some build contexts). Signed-long mixing only. */
    private fun randomSuffix(seed: Long): String {
        var x = seed
        x = x xor (x ushr 33)
        x *= -0x7ee3623a03d3c2ddL
        x = x xor (x ushr 29)
        val v = x and 0xFFFFFFFFFFL
        return java.lang.Long.toHexString(v).takeLast(6).padStart(6, '0')
    }
}
