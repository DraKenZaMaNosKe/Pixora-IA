package com.orbix.pixora.features.daycycle;

import com.orbix.pixora.data.repos.DayCycleRepository;
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
public final class DayCycleViewModel_Factory implements Factory<DayCycleViewModel> {
  private final Provider<DayCycleRepository> repoProvider;

  public DayCycleViewModel_Factory(Provider<DayCycleRepository> repoProvider) {
    this.repoProvider = repoProvider;
  }

  @Override
  public DayCycleViewModel get() {
    return newInstance(repoProvider.get());
  }

  public static DayCycleViewModel_Factory create(Provider<DayCycleRepository> repoProvider) {
    return new DayCycleViewModel_Factory(repoProvider);
  }

  public static DayCycleViewModel newInstance(DayCycleRepository repo) {
    return new DayCycleViewModel(repo);
  }
}
