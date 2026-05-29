package com.orbix.pixora.features.stories;

import androidx.lifecycle.SavedStateHandle;
import com.orbix.pixora.data.repos.StoryRepository;
import com.orbix.pixora.data.wallpaper.WallpaperApplyService;
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
public final class StoryDetailViewModel_Factory implements Factory<StoryDetailViewModel> {
  private final Provider<SavedStateHandle> savedStateHandleProvider;

  private final Provider<StoryRepository> repoProvider;

  private final Provider<WallpaperApplyService> applyServiceProvider;

  public StoryDetailViewModel_Factory(Provider<SavedStateHandle> savedStateHandleProvider,
      Provider<StoryRepository> repoProvider,
      Provider<WallpaperApplyService> applyServiceProvider) {
    this.savedStateHandleProvider = savedStateHandleProvider;
    this.repoProvider = repoProvider;
    this.applyServiceProvider = applyServiceProvider;
  }

  @Override
  public StoryDetailViewModel get() {
    return newInstance(savedStateHandleProvider.get(), repoProvider.get(), applyServiceProvider.get());
  }

  public static StoryDetailViewModel_Factory create(
      Provider<SavedStateHandle> savedStateHandleProvider, Provider<StoryRepository> repoProvider,
      Provider<WallpaperApplyService> applyServiceProvider) {
    return new StoryDetailViewModel_Factory(savedStateHandleProvider, repoProvider, applyServiceProvider);
  }

  public static StoryDetailViewModel newInstance(SavedStateHandle savedStateHandle,
      StoryRepository repo, WallpaperApplyService applyService) {
    return new StoryDetailViewModel(savedStateHandle, repo, applyService);
  }
}
