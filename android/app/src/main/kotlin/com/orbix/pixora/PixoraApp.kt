package com.orbix.pixora

import android.app.Application
import androidx.hilt.work.HiltWorkerFactory
import androidx.work.Configuration
import com.google.android.gms.ads.MobileAds
import com.google.android.gms.ads.RequestConfiguration
import dagger.hilt.android.HiltAndroidApp
import javax.inject.Inject

/**
 * Application entry point.
 *
 * `@HiltAndroidApp` triggers Hilt code generation — every other Android
 * component (Activity, Fragment, Service, Worker) that needs injection
 * will pull from this graph.
 *
 * Also configures WorkManager with Hilt-aware worker factory so workers
 * like AutoRotateWorker, DayCycleWorker, etc. can receive injected
 * dependencies via @AssistedInject.
 *
 * AdMob initialization: MUST run on app start. Two non-negotiables:
 *  1. maxAdContentRating=G — filters heavy playable game ads that stutter
 *     on mid-range devices (v1.7.10 fix, memory tech_admob_max_content_rating).
 *  2. testDeviceIds — required during development to avoid AdMob
 *     suspending the account for self-clicks (v1 lesson: 29-day
 *     suspension, 2nd offense = permanent ban). Get your hashed device ID
 *     from logcat after first run: "Use RequestConfiguration.Builder
 *     .setTestDeviceIds(Arrays.asList(\"YOUR_HASH\"))".
 */
@HiltAndroidApp
class PixoraApp : Application(), Configuration.Provider {

    @Inject
    lateinit var workerFactory: HiltWorkerFactory

    override val workManagerConfiguration: Configuration
        get() = Configuration.Builder()
            .setWorkerFactory(workerFactory)
            .build()

    override fun onCreate() {
        super.onCreate()
        initAdMob()
    }

    private fun initAdMob() {
        // Register Samsung A15 (Eduardo) + emulator as test devices.
        // The hashed ID for the Samsung shows up in logcat as
        // "Use RequestConfiguration.Builder.setTestDeviceIds(...)" on
        // first ad load — copy that hash into the list below.
        val testDevices = listOf(
            "EMULATOR",
            // TODO: paste Samsung A15 hashed test ID from logcat here
            //       to silence the "Test ads will not show on this device" warning.
        )
        val requestConfig = RequestConfiguration.Builder()
            .setMaxAdContentRating(RequestConfiguration.MAX_AD_CONTENT_RATING_G)
            .setTestDeviceIds(testDevices)
            .build()
        MobileAds.setRequestConfiguration(requestConfig)
        MobileAds.initialize(this) { /* init complete — could log status here */ }
    }
}
