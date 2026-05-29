package com.orbix.pixora.features.daycycle;

import androidx.lifecycle.SavedStateHandle;
import com.orbix.pixora.data.repos.DayCycleRepository;
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
public final class DayCycleDetailViewModel_Factory implements Factory<DayCycleDetailViewModel> {
  private final Provider<SavedStateHandle> savedStateHandleProvider;

  private final Provider<DayCycleRepository> repoProvider;

  private final Provider<WallpaperApplyService> applyServiceProvider;

  public DayCycleDetailViewModel_Factory(Provider<SavedStateHandle> savedStateHandleProvider,
      Provider<DayCycleRepository> repoProvider,
      Provider<WallpaperApplyService> applyServiceProvider) {
    this.savedStateHandleProvider = savedStateHandleProvider;
    this.repoProvider = repoProvider;
    this.applyServiceProvider = applyServiceProvider;
  }

  @Override
  public DayCycleDetailViewModel get() {
    return newInstance(savedStateHandleProvider.get(), repoProvider.get(), applyServiceProvider.get());
  }

  public static DayCycleDetailViewModel_Factory create(
      Provider<SavedStateHandle> savedStateHandleProvider,
      Provider<DayCycleRepository> repoProvider,
      Provider<WallpaperApplyService> applyServiceProvider) {
    return new DayCycleDetailViewModel_Factory(savedStateHandleProvider, repoProvider, applyServiceProvider);
  }

  public static DayCycleDetailViewModel newInstance(SavedStateHandle savedStateHandle,
      DayCycleRepository repo, WallpaperApplyService applyService) {
    return new DayCycleDetailViewModel(savedStateHandle, repo, applyService);
  }
}
