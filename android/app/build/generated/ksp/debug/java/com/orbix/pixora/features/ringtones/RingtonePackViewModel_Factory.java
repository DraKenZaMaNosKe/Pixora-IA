package com.orbix.pixora.features.ringtones;

import androidx.lifecycle.SavedStateHandle;
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
public final class RingtonePackViewModel_Factory implements Factory<RingtonePackViewModel> {
  private final Provider<SavedStateHandle> savedStateHandleProvider;

  private final Provider<RingtoneRepository> repoProvider;

  private final Provider<RingtonePreviewPlayer> previewPlayerProvider;

  public RingtonePackViewModel_Factory(Provider<SavedStateHandle> savedStateHandleProvider,
      Provider<RingtoneRepository> repoProvider,
      Provider<RingtonePreviewPlayer> previewPlayerProvider) {
    this.savedStateHandleProvider = savedStateHandleProvider;
    this.repoProvider = repoProvider;
    this.previewPlayerProvider = previewPlayerProvider;
  }

  @Override
  public RingtonePackViewModel get() {
    return newInstance(savedStateHandleProvider.get(), repoProvider.get(), previewPlayerProvider.get());
  }

  public static RingtonePackViewModel_Factory create(
      Provider<SavedStateHandle> savedStateHandleProvider,
      Provider<RingtoneRepository> repoProvider,
      Provider<RingtonePreviewPlayer> previewPlayerProvider) {
    return new RingtonePackViewModel_Factory(savedStateHandleProvider, repoProvider, previewPlayerProvider);
  }

  public static RingtonePackViewModel newInstance(SavedStateHandle savedStateHandle,
      RingtoneRepository repo, RingtonePreviewPlayer previewPlayer) {
    return new RingtonePackViewModel(savedStateHandle, repo, previewPlayer);
  }
}
