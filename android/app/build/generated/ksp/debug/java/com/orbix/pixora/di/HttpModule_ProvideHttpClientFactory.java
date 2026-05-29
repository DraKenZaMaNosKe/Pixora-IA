package com.orbix.pixora.di;

import dagger.internal.DaggerGenerated;
import dagger.internal.Factory;
import dagger.internal.Preconditions;
import dagger.internal.QualifierMetadata;
import dagger.internal.ScopeMetadata;
import io.ktor.client.HttpClient;
import javax.annotation.processing.Generated;
import javax.inject.Provider;
import kotlinx.serialization.json.Json;

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
public final class HttpModule_ProvideHttpClientFactory implements Factory<HttpClient> {
  private final Provider<Json> jsonProvider;

  public HttpModule_ProvideHttpClientFactory(Provider<Json> jsonProvider) {
    this.jsonProvider = jsonProvider;
  }

  @Override
  public HttpClient get() {
    return provideHttpClient(jsonProvider.get());
  }

  public static HttpModule_ProvideHttpClientFactory create(Provider<Json> jsonProvider) {
    return new HttpModule_ProvideHttpClientFactory(jsonProvider);
  }

  public static HttpClient provideHttpClient(Json json) {
    return Preconditions.checkNotNullFromProvides(HttpModule.INSTANCE.provideHttpClient(json));
  }
}
