package com.orbix.pixora.features.wallpapers;

import com.orbix.pixora.data.favorites.FavoriteService;
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
public final class WallpapersViewModel_Factory implements Factory<WallpapersViewModel> {
  private final Provider<WallpaperRepository> repoProvider;

  private final Provider<FavoriteService> favoritesProvider;

  public WallpapersViewModel_Factory(Provider<WallpaperRepository> repoProvider,
      Provider<FavoriteService> favoritesProvider) {
    this.repoProvider = repoProvider;
    this.favoritesProvider = favoritesProvider;
  }

  @Override
  public WallpapersViewModel get() {
    return newInstance(repoProvider.get(), favoritesProvider.get());
  }

  public static WallpapersViewModel_Factory create(Provider<WallpaperRepository> repoProvider,
      Provider<FavoriteService> favoritesProvider) {
    return new WallpapersViewModel_Factory(repoProvider, favoritesProvider);
  }

  public static WallpapersViewModel newInstance(WallpaperRepository repo,
      FavoriteService favorites) {
    return new WallpapersViewModel(repo, favorites);
  }
}
