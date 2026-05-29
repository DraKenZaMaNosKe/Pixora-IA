package com.orbix.pixora.features.ringtones;

import com.orbix.pixora.data.repos.RingtoneRepository;
import com.orbix.pixora.data.ringtones.RingtonePreviewPlayer;
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
public final class RingtonesViewModel_Factory implements Factory<RingtonesViewModel> {
  private final Provider<RingtoneRepository> repoProvider;

  private final Provider<RingtonePreviewPlayer> previewPlayerProvider;

  public RingtonesViewModel_Factory(Provider<RingtoneRepository> repoProvider,
      Provider<RingtonePreviewPlayer> previewPlayerProvider) {
    this.repoProvider = repoProvider;
    this.previewPlayerProvider = previewPlayerProvider;
  }

  @Override
  public RingtonesViewModel get() {
    return newInstance(repoProvider.get(), previewPlayerProvider.get());
  }

  public static RingtonesViewModel_Factory create(Provider<RingtoneRepository> repoProvider,
      Provider<RingtonePreviewPlayer> previewPlayerProvider) {
    return new RingtonesViewModel_Factory(repoProvider, previewPlayerProvider);
  }

  public static RingtonesViewModel newInstance(RingtoneRepository repo,
      RingtonePreviewPlayer previewPlayer) {
    return new RingtonesViewModel(repo, previewPlayer);
  }
}
