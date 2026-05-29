package com.orbix.pixora.data.stats;

import dagger.internal.DaggerGenerated;
import dagger.internal.Factory;
import dagger.internal.QualifierMetadata;
import dagger.internal.ScopeMetadata;
import io.github.jan.supabase.SupabaseClient;
import javax.annotation.processing.Generated;
import javax.inject.Provider;

@ScopeMetadata("javax.inject.Singleton")
@QualifierMetadata
@DaggerGenerated
@Generated(
    value = "dagger.internal.codegen.ComponentProcessor",
    comments = "https://dagger.dev"
)
@SuppressWarnings({
    "unchecked",
    "rawtypes",
    "KotlinInternal",
    "KotlinInternalInJava",
    "cast",
    "deprecation"
})
public final class WallpaperStatsService_Factory implements Factory<WallpaperStatsService> {
  private final Provider<SupabaseClient> supabaseProvider;

  public WallpaperStatsService_Factory(Provider<SupabaseClient> supabaseProvider) {
    this.supabaseProvider = supabaseProvider;
  }

  @Override
  public WallpaperStatsService get() {
    return newInstance(supabaseProvider.get());
  }

  public static WallpaperStatsService_Factory create(Provider<SupabaseClient> supabaseProvider) {
    return new WallpaperStatsService_Factory(supabaseProvider);
  }

  public static WallpaperStatsService newInstance(SupabaseClient supabase) {
    return new WallpaperStatsService(supabase);
  }
}
