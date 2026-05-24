package com.orbix.pixora.data.ads

import android.app.Activity
import android.content.Context
import com.google.android.gms.ads.AdError
import com.google.android.gms.ads.AdRequest
import com.google.android.gms.ads.FullScreenContentCallback
import com.google.android.gms.ads.LoadAdError
import com.google.android.gms.ads.interstitial.InterstitialAd
import com.google.android.gms.ads.interstitial.InterstitialAdLoadCallback
import dagger.hilt.android.qualifiers.ApplicationContext
import javax.inject.Inject
import javax.inject.Singleton

/**
 * Interstitial ad gate — mirrors v1 AdService.instance pattern.
 *
 *  - Preloads one interstitial at app start (so it's ready instantly).
 *  - showInterstitial(activity, onDismissed) alternates 1-yes/1-no per
 *    call, so the user doesn't get hammered on every single action.
 *  - Every dismissal triggers a re-preload AND fires onDismissed so the
 *    caller (e.g. WallpaperApplyService) can proceed with its work.
 *
 * In dev builds we use Google's universal test interstitial unit ID.
 * NEVER use the production unit IDs from KEYS_LOCAL while developing —
 * self-clicks will get the AdMob account suspended (v1 incident, 29 days).
 *
 * The production unit ID swap happens at release time, gated by BuildConfig.
 */
@Singleton
class AdService @Inject constructor(
    @ApplicationContext private val context: Context,
) {

    // Google's universal test interstitial. Always-test — safe in dev.
    private val testUnitId = "ca-app-pub-3940256099942544/1033173712"

    private var loaded: InterstitialAd? = null
    private var loading: Boolean = false
    /** False on first call → show, then true → skip, then false → show … */
    private var skipNext: Boolean = false

    init {
        preload()
    }

    fun preload() {
        if (loaded != null || loading) return
        loading = true
        InterstitialAd.load(
            context,
            testUnitId,
            AdRequest.Builder().build(),
            object : InterstitialAdLoadCallback() {
                override fun onAdLoaded(ad: InterstitialAd) {
                    loaded = ad
                    loading = false
                    println("[AdService] interstitial loaded")
                }

                override fun onAdFailedToLoad(error: LoadAdError) {
                    loaded = null
                    loading = false
                    println("[AdService] interstitial failed to load: ${error.message}")
                }
            },
        )
    }

    /**
     * Tries to show an interstitial in front of [activity]. The user's
     * action (the thing they wanted to do — e.g. apply a wallpaper)
     * runs inside [onDismissed], so we always call it exactly once:
     *  - immediately if it's a "no-ad" turn or the ad isn't ready;
     *  - after the ad is closed if it shows.
     *
     * onDismissed receives `awardedCredit = true` when an ad actually
     * played (so the caller can call CreditService.earnFromAd()).
     */
    fun showInterstitial(activity: Activity, onDismissed: (awardedCredit: Boolean) -> Unit) {
        val ad = loaded
        val shouldSkip = skipNext || ad == null
        if (shouldSkip) {
            skipNext = false
            if (ad == null) preload() // try again so next call has one
            onDismissed(false)
            return
        }

        ad.fullScreenContentCallback = object : FullScreenContentCallback() {
            override fun onAdDismissedFullScreenContent() {
                loaded = null
                skipNext = true
                preload()
                onDismissed(true)
            }

            override fun onAdFailedToShowFullScreenContent(error: AdError) {
                loaded = null
                preload()
                onDismissed(false)
            }
        }
        ad.show(activity)
    }
}
