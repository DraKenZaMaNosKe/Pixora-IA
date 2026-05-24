package com.orbix.pixora.data

/**
 * Supabase project config — same backend as v1 Flutter (no migration needed).
 * Anon key is safe to embed (it only has read access + filtered by RLS).
 * Service role key NEVER ships in the app (server-only, lives in admin tools).
 */
object SupabaseConfig {
    const val PROJECT_URL = "https://vzuwvsmlyigjtsearxym.supabase.co"
    const val ANON_KEY =
        "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9." +
        "eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InZ6dXd2c21seWlnanRzZWFyeHltIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NTg2NDg3MDksImV4cCI6MjA3NDIyNDcwOX0." +
        "Fqum-r8H3erP3fLUvzQlLtWivlrp3smAebvI0uDA5uE"

    // Storage public buckets
    const val IMAGES_BUCKET = "wallpaper-images"
    const val VIDEOS_BUCKET = "wallpaper-videos"
    private const val STORAGE_PUBLIC = "$PROJECT_URL/storage/v1/object/public"

    /** Build a public URL for a file in the wallpaper-images bucket. */
    fun imageUrl(filename: String): String = "$STORAGE_PUBLIC/$IMAGES_BUCKET/$filename"

    /** Build a public URL for a file in the wallpaper-videos bucket. */
    fun videoUrl(filename: String): String = "$STORAGE_PUBLIC/$VIDEOS_BUCKET/$filename"

    // ─── JSON catalogs in Storage (read-only public) ──────────────────
    // Source of truth for content per kind. Editable from pixora-admin
    // without app updates (6h-cache on client side in v1; v2 just fetches
    // fresh on app start and on pull-to-refresh).
    const val CATALOG_LIVE = "live_wallpaper_catalog.json"
    const val CATALOG_STORIES = "stories_catalog.json"
    const val CATALOG_DAY_CYCLE = "day_cycle_catalog.json"
    const val CATALOG_RINGTONES = "ringtones_catalog.json"

    /** Public URL for a JSON catalog file in a Storage bucket. */
    fun catalogUrl(bucket: String, file: String): String =
        "$STORAGE_PUBLIC/$bucket/$file"
}
