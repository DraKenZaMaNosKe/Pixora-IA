package com.orbix.pixora.ui.components;

import com.orbix.pixora.data.auth.AuthService;
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
public final class PixoraAppBarAuthViewModel_Factory implements Factory<PixoraAppBarAuthViewModel> {
  private final Provider<AuthService> authServiceProvider;

  public PixoraAppBarAuthViewModel_Factory(Provider<AuthService> authServiceProvider) {
    this.authServiceProvider = authServiceProvider;
  }

  @Override
  public PixoraAppBarAuthViewModel get() {
    return newInstance(authServiceProvider.get());
  }

  public static PixoraAppBarAuthViewModel_Factory create(
      Provider<AuthService> authServiceProvider) {
    return new PixoraAppBarAuthViewModel_Factory(authServiceProvider);
  }

  public static PixoraAppBarAuthViewModel newInstance(AuthService authService) {
    return new PixoraAppBarAuthViewModel(authService);
  }
}
