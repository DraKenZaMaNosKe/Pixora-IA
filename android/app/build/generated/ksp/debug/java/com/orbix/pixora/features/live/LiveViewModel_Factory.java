package com.orbix.pixora.features.live;

import com.orbix.pixora.data.repos.LiveWallpaperRepository;
import dagger.internal.DaggerGenerated;
import dagger.internal.Factory;
import dagger.internal.QualifierMetadata;
import dagger.internal.ScopeMetadata;
import javax.annotation.processing.Generated;
import javax.inject.Provider;

@ScopeMetadata
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
public final class LiveViewModel_Factory implements Factory<LiveViewModel> {
  private final Provider<LiveWallpaperRepository> repoProvider;

  public LiveViewModel_Factory(Provider<LiveWallpaperRepository> repoProvider) {
    this.repoProvider = repoProvider;
  }

  @Override
  public LiveViewModel get() {
    return newInstance(repoProvider.get());
  }

  public static LiveViewModel_Factory create(Provider<LiveWallpaperRepository> repoProvider) {
    return new LiveViewModel_Factory(repoProvider);
  }

  public static LiveViewModel newInstance(LiveWallpaperRepository repo) {
    return new LiveViewModel(repo);
  }
}
