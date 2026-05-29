package com.orbix.pixora.data.auth;

import android.content.Context;
import dagger.internal.DaggerGenerated;
import dagger.internal.Factory;
import dagger.internal.QualifierMetadata;
import dagger.internal.ScopeMetadata;
import javax.annotation.processing.Generated;
import javax.inject.Provider;

@ScopeMetadata("javax.inject.Singleton")
@QualifierMetadata("dagger.hilt.android.qualifiers.ApplicationContext")
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
public final class AuthService_Factory implements Factory<AuthService> {
  private final Provider<Context> contextProvider;

  public AuthService_Factory(Provider<Context> contextProvider) {
    this.contextProvider = contextProvider;
  }

  @Override
  public AuthService get() {
    return newInstance(contextProvider.get());
  }

  public static AuthService_Factory create(Provider<Context> contextProvider) {
    return new AuthService_Factory(contextProvider);
  }

  public static AuthService newInstance(Context context) {
    return new AuthService(context);
  }
}
