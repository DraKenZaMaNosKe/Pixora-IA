package com.orbix.pixora.ui.components;

import com.orbix.pixora.data.credits.CreditService;
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
public final class PixoraAppBarCreditsViewModel_Factory implements Factory<PixoraAppBarCreditsViewModel> {
  private final Provider<CreditService> creditServiceProvider;

  public PixoraAppBarCreditsViewModel_Factory(Provider<CreditService> creditServiceProvider) {
    this.creditServiceProvider = creditServiceProvider;
  }

  @Override
  public PixoraAppBarCreditsViewModel get() {
    return newInstance(creditServiceProvider.get());
  }

  public static PixoraAppBarCreditsViewModel_Factory create(
      Provider<CreditService> creditServiceProvider) {
    return new PixoraAppBarCreditsViewModel_Factory(creditServiceProvider);
  }

  public static PixoraAppBarCreditsViewModel newInstance(CreditService creditService) {
    return new PixoraAppBarCreditsViewModel(creditService);
  }
}
