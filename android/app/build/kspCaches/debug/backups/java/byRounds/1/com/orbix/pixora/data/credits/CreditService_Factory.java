package com.orbix.pixora.data.credits;

import com.orbix.pixora.data.db.CreditDao;
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
public final class CreditService_Factory implements Factory<CreditService> {
  private final Provider<CreditDao> daoProvider;

  public CreditService_Factory(Provider<CreditDao> daoProvider) {
    this.daoProvider = daoProvider;
  }

  @Override
  public CreditService get() {
    return newInstance(daoProvider.get());
  }

  public static CreditService_Factory create(Provider<CreditDao> daoProvider) {
    return new CreditService_Factory(daoProvider);
  }

  public static CreditService newInstance(CreditDao dao) {
    return new CreditService(dao);
  }
}
