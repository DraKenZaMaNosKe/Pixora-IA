package com.orbix.pixora.data.repos;

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
public final class WallpaperRepository_Factory implements Factory<WallpaperRepository> {
  private final Provider<SupabaseClient> supabaseProvider;

  public WallpaperRepository_Factory(Provider<SupabaseClient> supabaseProvider) {
    this.supabaseProvider = supabaseProvider;
  }

  @Override
  public WallpaperRepository get() {
    return newInstance(supabaseProvider.get());
  }

  public static WallpaperRepository_Factory create(Provider<SupabaseClient> supabaseProvider) {
    return new WallpaperRepository_Factory(supabaseProvider);
  }

  public static WallpaperRepository newInstance(SupabaseClient supabase) {
    return new WallpaperRepository(supabase);
  }
}
