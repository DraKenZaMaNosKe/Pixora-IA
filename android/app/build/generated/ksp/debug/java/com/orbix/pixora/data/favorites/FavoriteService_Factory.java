package com.orbix.pixora.data.favorites;

import com.orbix.pixora.data.db.FavoriteDao;
import dagger.internal.DaggerGenerated;
import dagger.internal.Factory;
import dagger.internal.QualifierMetadata;
import dagger.internal.ScopeMetadata;
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
public final class FavoriteService_Factory implements Factory<FavoriteService> {
  private final Provider<FavoriteDao> daoProvider;

  public FavoriteService_Factory(Provider<FavoriteDao> daoProvider) {
    this.daoProvider = daoProvider;
  }

  @Override
  public FavoriteService get() {
    return newInstance(daoProvider.get());
  }

  public static FavoriteService_Factory create(Provider<FavoriteDao> daoProvider) {
    return new FavoriteService_Factory(daoProvider);
  }

  public static FavoriteService newInstance(FavoriteDao dao) {
    return new FavoriteService(dao);
  }
}
