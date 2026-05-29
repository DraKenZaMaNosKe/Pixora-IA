package com.orbix.pixora.features.aura;

import com.orbix.pixora.data.aura.AuraPlayerService;
import com.orbix.pixora.data.repos.AuraRepository;
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
public final class AuraViewModel_Factory implements Factory<AuraViewModel> {
  private final Provider<AuraRepository> repoProvider;

  private final Provider<AuraPlayerService> playerServiceProvider;

  public AuraViewModel_Factory(Provider<AuraRepository> repoProvider,
      Provider<AuraPlayerService> playerServiceProvider) {
    this.repoProvider = repoProvider;
    this.playerServiceProvider = playerServiceProvider;
  }

  @Override
  public AuraViewModel get() {
    return newInstance(repoProvider.get(), playerServiceProvider.get());
  }

  public static AuraViewModel_Factory create(Provider<AuraRepository> repoProvider,
      Provider<AuraPlayerService> playerServiceProvider) {
    return new AuraViewModel_Factory(repoProvider, playerServiceProvider);
  }

  public static AuraViewModel newInstance(AuraRepository repo, AuraPlayerService playerService) {
    return new AuraViewModel(repo, playerService);
  }
}
