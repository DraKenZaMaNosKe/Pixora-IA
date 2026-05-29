package com.orbix.pixora.features.favorites;

import com.orbix.pixora.data.favorites.FavoriteService;
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
public final class FavoritesViewModel_Factory implements Factory<FavoritesViewModel> {
  private final Provider<FavoriteService> serviceProvider;

  public FavoritesViewModel_Factory(Provider<FavoriteService> serviceProvider) {
    this.serviceProvider = serviceProvider;
  }

  @Override
  public FavoritesViewModel get() {
    return newInstance(serviceProvider.get());
  }

  public static FavoritesViewModel_Factory create(Provider<FavoriteService> serviceProvider) {
    return new FavoritesViewModel_Factory(serviceProvider);
  }

  public static FavoritesViewModel newInstance(FavoriteService service) {
    return new FavoritesViewModel(service);
  }
}
