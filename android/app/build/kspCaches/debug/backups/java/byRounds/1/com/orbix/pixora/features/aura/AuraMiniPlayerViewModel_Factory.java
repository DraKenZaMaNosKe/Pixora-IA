package com.orbix.pixora.features.aura;

import com.orbix.pixora.data.aura.AuraPlayerService;
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
public final class AuraMiniPlayerViewModel_Factory implements Factory<AuraMiniPlayerViewModel> {
  private final Provider<AuraPlayerService> playerProvider;

  public AuraMiniPlayerViewModel_Factory(Provider<AuraPlayerService> playerProvider) {
    this.playerProvider = playerProvider;
  }

  @Override
  public AuraMiniPlayerViewModel get() {
    return newInstance(playerProvider.get());
  }

  public static AuraMiniPlayerViewModel_Factory create(Provider<AuraPlayerService> playerProvider) {
    return new AuraMiniPlayerViewModel_Factory(playerProvider);
  }

  public static AuraMiniPlayerViewModel newInstance(AuraPlayerService player) {
    return new AuraMiniPlayerViewModel(player);
  }
}
