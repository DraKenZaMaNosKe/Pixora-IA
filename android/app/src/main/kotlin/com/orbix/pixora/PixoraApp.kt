package com.orbix.pixora

import android.app.Application
import androidx.hilt.work.HiltWorkerFactory
import androidx.work.Configuration
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
 */
@HiltAndroidApp
class PixoraApp : Application(), Configuration.Provider {

    @Inject
    lateinit var workerFactory: HiltWorkerFactory

    override val workManagerConfiguration: Configuration
        get() = Configuration.Builder()
            .setWorkerFactory(workerFactory)
            .build()
}
