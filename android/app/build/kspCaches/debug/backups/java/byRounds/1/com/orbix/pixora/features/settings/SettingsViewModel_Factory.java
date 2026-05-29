package com.orbix.pixora.features.settings;

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
public final class SettingsViewModel_Factory implements Factory<SettingsViewModel> {
  private final Provider<CreditService> creditServiceProvider;

  public SettingsViewModel_Factory(Provider<CreditService> creditServiceProvider) {
    this.creditServiceProvider = creditServiceProvider;
  }

  @Override
  public SettingsViewModel get() {
    return newInstance(creditServiceProvider.get());
  }

  public static SettingsViewModel_Factory create(Provider<CreditService> creditServiceProvider) {
    return new SettingsViewModel_Factory(creditServiceProvider);
  }

  public static SettingsViewModel newInstance(CreditService creditService) {
    return new SettingsViewModel(creditService);
  }
}
