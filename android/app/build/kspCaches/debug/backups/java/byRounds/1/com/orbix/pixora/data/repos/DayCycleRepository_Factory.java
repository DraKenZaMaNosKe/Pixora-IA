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
public final class DayCycleRepository_Factory implements Factory<DayCycleRepository> {
  private final Provider<HttpClient> httpProvider;

  public DayCycleRepository_Factory(Provider<HttpClient> httpProvider) {
    this.httpProvider = httpProvider;
  }

  @Override
  public DayCycleRepository get() {
    return newInstance(httpProvider.get());
  }

  public static DayCycleRepository_Factory create(Provider<HttpClient> httpProvider) {
    return new DayCycleRepository_Factory(httpProvider);
  }

  public static DayCycleRepository newInstance(HttpClient http) {
    return new DayCycleRepository(http);
  }
}
