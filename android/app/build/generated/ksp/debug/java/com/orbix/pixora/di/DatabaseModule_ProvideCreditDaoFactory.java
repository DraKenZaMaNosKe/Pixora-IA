package com.orbix.pixora.di;

import com.orbix.pixora.data.db.CreditDao;
import com.orbix.pixora.data.db.PixoraDatabase;
import dagger.internal.DaggerGenerated;
import dagger.internal.Factory;
import dagger.internal.Preconditions;
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
public final class DatabaseModule_ProvideCreditDaoFactory implements Factory<CreditDao> {
  private final Provider<PixoraDatabase> dbProvider;

  public DatabaseModule_ProvideCreditDaoFactory(Provider<PixoraDatabase> dbProvider) {
    this.dbProvider = dbProvider;
  }

  @Override
  public CreditDao get() {
    return provideCreditDao(dbProvider.get());
  }

  public static DatabaseModule_ProvideCreditDaoFactory create(Provider<PixoraDatabase> dbProvider) {
    return new DatabaseModule_ProvideCreditDaoFactory(dbProvider);
  }

  public static CreditDao provideCreditDao(PixoraDatabase db) {
    return Preconditions.checkNotNullFromProvides(DatabaseModule.INSTANCE.provideCreditDao(db));
  }
}
