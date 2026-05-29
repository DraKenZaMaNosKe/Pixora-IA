package com.orbix.pixora.features.threed;

import com.orbix.pixora.data.repos.WallpaperRepository;
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
public final class ThreeDViewModel_Factory implements Factory<ThreeDViewModel> {
  private final Provider<WallpaperRepository> repoProvider;

  public ThreeDViewModel_Factory(Provider<WallpaperRepository> repoProvider) {
    this.repoProvider = repoProvider;
  }

  @Override
  public ThreeDViewModel get() {
    return newInstance(repoProvider.get());
  }

  public static ThreeDViewModel_Factory create(Provider<WallpaperRepository> repoProvider) {
    return new ThreeDViewModel_Factory(repoProvider);
  }

  public static ThreeDViewModel newInstance(WallpaperRepository repo) {
    return new ThreeDViewModel(repo);
  }
}
