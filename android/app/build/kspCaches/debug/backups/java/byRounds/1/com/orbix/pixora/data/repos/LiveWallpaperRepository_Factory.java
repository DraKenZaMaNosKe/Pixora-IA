package com.orbix.pixora.data.repos;

import dagger.internal.DaggerGenerated;
import dagger.internal.Factory;
import dagger.internal.QualifierMetadata;
import dagger.internal.ScopeMetadata;
import io.ktor.client.HttpClient;
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
public final class LiveWallpaperRepository_Factory implements Factory<LiveWallpaperRepository> {
  private final Provider<HttpClient> httpProvider;

  public LiveWallpaperRepository_Factory(Provider<HttpClient> httpProvider) {
    this.httpProvider = httpProvider;
  }

  @Override
  public LiveWallpaperRepository get() {
    return newInstance(httpProvider.get());
  }

  public static LiveWallpaperRepository_Factory create(Provider<HttpClient> httpProvider) {
    return new LiveWallpaperRepository_Factory(httpProvider);
  }

  public static LiveWallpaperRepository newInstance(HttpClient http) {
    return new LiveWallpaperRepository(http);
  }
}
