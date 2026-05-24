package com.orbix.pixora.di

import android.content.Context
import androidx.room.Room
import com.orbix.pixora.data.db.CreditDao
import com.orbix.pixora.data.db.PixoraDatabase
import dagger.Module
import dagger.Provides
import dagger.hilt.InstallIn
import dagger.hilt.android.qualifiers.ApplicationContext
import dagger.hilt.components.SingletonComponent
import javax.inject.Singleton

@Module
@InstallIn(SingletonComponent::class)
object DatabaseModule {

    @Provides
    @Singleton
    fun provideDatabase(@ApplicationContext context: Context): PixoraDatabase =
        Room.databaseBuilder(context, PixoraDatabase::class.java, PixoraDatabase.DB_NAME)
            // For v2 alpha we don't have a migration story yet — fall back to
            // destructive recreation so schema bumps don't crash the app.
            // Replace with proper migrations when we have a user base.
            .fallbackToDestructiveMigration()
            .build()

    @Provides
    @Singleton
    fun provideCreditDao(db: PixoraDatabase): CreditDao = db.creditDao()
}
