import java.util.Properties
import java.io.FileInputStream

plugins {
    id("com.android.application")
    id("org.jetbrains.kotlin.android")
    id("org.jetbrains.kotlin.plugin.compose")
    id("org.jetbrains.kotlin.plugin.serialization")
    id("com.google.devtools.ksp")
    id("com.google.dagger.hilt.android")
    // Firebase google-services plugin removido temporalmente — re-enable
    // cuando agreguemos firebase-messaging + crashlytics correctly setup
    // (necesitan su Crashlytics Gradle plugin para no crashear en boot).
    // id("com.google.gms.google-services")
}

val keystoreProperties = Properties().apply {
    val keystorePropertiesFile = rootProject.file("key.properties")
    if (keystorePropertiesFile.exists()) {
        load(FileInputStream(keystorePropertiesFile))
    }
}

android {
    namespace = "com.orbix.pixora"
    compileSdk = 35
    ndkVersion = "28.2.13676358"

    defaultConfig {
        applicationId = "com.orbix.pixora"
        minSdk = 26
        targetSdk = 35
        // v2 versionCode bumped past last v1 release (1.7.17+60).
        // Convention: v2 starts at 100 + N (gives room to ship v1 hotfixes
        // up to versionCode 99 if needed).
        versionCode = 100
        versionName = "2.0.0-alpha1"

        vectorDrawables { useSupportLibrary = true }
    }

    signingConfigs {
        create("release") {
            keyAlias = keystoreProperties["keyAlias"] as String?
            keyPassword = keystoreProperties["keyPassword"] as String?
            val storeFilePath = keystoreProperties["storeFile"] as String?
            storeFile = storeFilePath?.let { file(it) }
            storePassword = keystoreProperties["storePassword"] as String?
        }
    }

    buildTypes {
        release {
            signingConfig = signingConfigs.getByName("release")
            isMinifyEnabled = false
            proguardFiles(getDefaultProguardFile("proguard-android-optimize.txt"), "proguard-rules.pro")
            ndk { debugSymbolLevel = "FULL" }
        }
        debug {
            // applicationIdSuffix = ".debug"  // off so install -r works with the v1 install
        }
    }

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
        isCoreLibraryDesugaringEnabled = true
    }

    kotlinOptions {
        jvmTarget = "17"
    }

    buildFeatures {
        compose = true
        buildConfig = true
    }

    packaging {
        resources {
            excludes += "/META-INF/{AL2.0,LGPL2.1}"
            excludes += "META-INF/INDEX.LIST"
        }
    }
}

dependencies {
    // ─── Compose BOM ─────────────────────────────────────────────────────
    val composeBom = platform("androidx.compose:compose-bom:2025.01.00")
    implementation(composeBom)
    androidTestImplementation(composeBom)

    implementation("androidx.compose.ui:ui")
    implementation("androidx.compose.ui:ui-graphics")
    implementation("androidx.compose.ui:ui-tooling-preview")
    implementation("androidx.compose.material3:material3")
    implementation("androidx.compose.material:material-icons-extended")
    debugImplementation("androidx.compose.ui:ui-tooling")
    debugImplementation("androidx.compose.ui:ui-test-manifest")

    // ─── Core Android + Lifecycle ────────────────────────────────────────
    implementation("androidx.core:core-ktx:1.15.0")
    implementation("androidx.activity:activity-compose:1.9.3")
    implementation("androidx.lifecycle:lifecycle-runtime-ktx:2.8.7")
    implementation("androidx.lifecycle:lifecycle-viewmodel-compose:2.8.7")
    implementation("androidx.lifecycle:lifecycle-runtime-compose:2.8.7")

    // ─── Navigation ──────────────────────────────────────────────────────
    implementation("androidx.navigation:navigation-compose:2.8.5")

    // ─── Hilt DI ─────────────────────────────────────────────────────────
    implementation("com.google.dagger:hilt-android:2.52")
    ksp("com.google.dagger:hilt-compiler:2.52")
    implementation("androidx.hilt:hilt-navigation-compose:1.2.0")
    implementation("androidx.hilt:hilt-work:1.2.0")
    ksp("androidx.hilt:hilt-compiler:1.2.0")

    // ─── Coil 3 (image loading) ──────────────────────────────────────────
    implementation("io.coil-kt.coil3:coil-compose:3.0.4")
    implementation("io.coil-kt.coil3:coil-network-okhttp:3.0.4")

    // ─── Ktor (HTTP client) ──────────────────────────────────────────────
    implementation("io.ktor:ktor-client-core:3.0.3")
    implementation("io.ktor:ktor-client-okhttp:3.0.3")
    implementation("io.ktor:ktor-client-content-negotiation:3.0.3")
    implementation("io.ktor:ktor-serialization-kotlinx-json:3.0.3")
    implementation("io.ktor:ktor-client-logging:3.0.3")

    // ─── Supabase-kt ─────────────────────────────────────────────────────
    val supabaseBom = platform("io.github.jan-tennert.supabase:bom:3.0.3")
    implementation(supabaseBom)
    implementation("io.github.jan-tennert.supabase:auth-kt")
    implementation("io.github.jan-tennert.supabase:postgrest-kt")
    implementation("io.github.jan-tennert.supabase:storage-kt")
    implementation("io.github.jan-tennert.supabase:realtime-kt")

    // ─── Room (local database) ───────────────────────────────────────────
    implementation("androidx.room:room-runtime:2.6.1")
    implementation("androidx.room:room-ktx:2.6.1")
    ksp("androidx.room:room-compiler:2.6.1")

    // ─── DataStore (preferences replacement) ─────────────────────────────
    implementation("androidx.datastore:datastore-preferences:1.1.1")

    // ─── Media3 (audio + video) ──────────────────────────────────────────
    implementation("androidx.media3:media3-exoplayer:1.5.0")
    implementation("androidx.media3:media3-session:1.5.0")
    implementation("androidx.media3:media3-ui:1.5.0")
    implementation("androidx.media3:media3-common:1.5.0")

    // ─── WorkManager (rotation workers) ──────────────────────────────────
    implementation("androidx.work:work-runtime-ktx:2.9.1")

    // ─── AdMob ───────────────────────────────────────────────────────────
    implementation("com.google.android.gms:play-services-ads:23.6.0")

    // ─── In-App Billing v7 ───────────────────────────────────────────────
    implementation("com.android.billingclient:billing-ktx:7.1.1")

    // ─── Firebase (DISABLED for Day 1) ───────────────────────────────────
    // Re-enable in session 4 cuando setup completo (BoM + plugin gms
    // google-services + plugin crashlytics + plugin perf). firebase-analytics
    // arrastra crashlytics transitively → boot crash sin el plugin.
    // implementation(platform("com.google.firebase:firebase-bom:33.7.0"))
    // implementation("com.google.firebase:firebase-messaging-ktx")
    // implementation("com.google.firebase:firebase-analytics-ktx")

    // ─── Splash Screen API (Android 12+) ─────────────────────────────────
    implementation("androidx.core:core-splashscreen:1.0.1")

    // ─── Compose Google Fonts (downloadable) ─────────────────────────────
    // Lets us reference Geist / Fraunces / JetBrains Mono / Cormorant /
    // Cinzel via Font(GoogleFont(...)) without bundling .ttf files.
    implementation("androidx.compose.ui:ui-text-google-fonts:1.7.6")

    // ─── Material Components (provides Theme.Material3.* XML themes) ─────
    // Compose Material 3 only provides Composables; the XML <style> system
    // needs this lib for `Theme.Material3.DayNight.NoActionBar` parent.
    implementation("com.google.android.material:material:1.12.0")

    // ─── Serialization ───────────────────────────────────────────────────
    implementation("org.jetbrains.kotlinx:kotlinx-serialization-json:1.7.3")

    // ─── Coroutines ──────────────────────────────────────────────────────
    implementation("org.jetbrains.kotlinx:kotlinx-coroutines-android:1.9.0")

    // ─── Core library desugaring (Android 8+ Java 8+ APIs) ──────────────
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.4")
}
