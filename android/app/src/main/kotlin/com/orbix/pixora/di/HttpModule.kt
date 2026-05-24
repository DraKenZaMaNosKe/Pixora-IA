package com.orbix.pixora.di

import dagger.Module
import dagger.Provides
import dagger.hilt.InstallIn
import dagger.hilt.components.SingletonComponent
import io.ktor.client.HttpClient
import io.ktor.client.engine.okhttp.OkHttp
import io.ktor.client.plugins.HttpTimeout
import io.ktor.client.plugins.contentnegotiation.ContentNegotiation
import io.ktor.serialization.kotlinx.json.json
import kotlinx.serialization.json.Json
import javax.inject.Singleton

/**
 * Hilt module that provides a singleton Ktor HttpClient.
 *
 * Used by the JSON catalog repositories (Live, Stories, DayCycle, Ringtones).
 * Static wallpapers go through SupabaseClient directly (Postgres view), not
 * Ktor — kept separate so a Supabase outage doesn't take everything down.
 *
 * `ignoreUnknownKeys = true` is intentional: the v1 admin tool sometimes
 * adds experimental fields to catalog JSONs before the client knows about
 * them. We don't want clients to crash on a field they don't model yet.
 */
@Module
@InstallIn(SingletonComponent::class)
object HttpModule {

    @Provides
    @Singleton
    fun provideJson(): Json = Json {
        ignoreUnknownKeys = true
        coerceInputValues = true
        isLenient = true
    }

    @Provides
    @Singleton
    fun provideHttpClient(json: Json): HttpClient = HttpClient(OkHttp) {
        install(ContentNegotiation) {
            json(json)
        }
        install(HttpTimeout) {
            requestTimeoutMillis = 20_000
            connectTimeoutMillis = 10_000
            socketTimeoutMillis = 30_000
        }
    }
}
