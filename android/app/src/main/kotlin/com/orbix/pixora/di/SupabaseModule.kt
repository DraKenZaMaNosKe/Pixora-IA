package com.orbix.pixora.di

import com.orbix.pixora.data.SupabaseConfig
import dagger.Module
import dagger.Provides
import dagger.hilt.InstallIn
import dagger.hilt.components.SingletonComponent
import io.github.jan.supabase.SupabaseClient
import io.github.jan.supabase.createSupabaseClient
import io.github.jan.supabase.postgrest.Postgrest
import io.github.jan.supabase.storage.Storage
import javax.inject.Singleton

/**
 * Hilt module that provides a singleton SupabaseClient configured with our
 * project URL + anon key. Postgrest + Storage modules installed for the
 * features we use (auth comes later when we port login).
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
        install(Postgrest)
        install(Storage)
    }
}
