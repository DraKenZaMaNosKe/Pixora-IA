package com.orbix.pixora.di

import com.orbix.pixora.data.SupabaseConfig
import dagger.Module
import dagger.Provides
import dagger.hilt.InstallIn
import dagger.hilt.components.SingletonComponent
import io.github.jan.supabase.SupabaseClient
import io.github.jan.supabase.createSupabaseClient
import io.github.jan.supabase.postgrest.Postgrest
import io.github.jan.supabase.serializer.KotlinXSerializer
import io.github.jan.supabase.storage.Storage
import kotlinx.serialization.json.Json
import javax.inject.Singleton

/**
 * Hilt module that provides a singleton SupabaseClient.
 *
 * The default KotlinXSerializer fails hard on null values for non-nullable
 * String fields (we hit this with aura_tracks.color_hex). Pass a custom Json
 * with coerceInputValues=true so null → default value transparently, plus
 * ignoreUnknownKeys for forward-compat with new server columns.
 */
@Module
@InstallIn(SingletonComponent::class)
object SupabaseModule {

    @Provides
    @Singleton
    fun provideSupabaseClient(): SupabaseClient = createSupabaseClient(
        supabaseUrl = SupabaseConfig.PROJECT_URL,
        supabaseKey = SupabaseConfig.ANON_KEY,
    ) {
        defaultSerializer = KotlinXSerializer(
            json = Json {
                ignoreUnknownKeys = true
                coerceInputValues = true
                isLenient = true
                explicitNulls = false
            }
        )
        install(Postgrest)
        install(Storage)
    }
}
