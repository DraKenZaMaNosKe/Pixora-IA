package com.orbix.pixora.features.live;

import androidx.lifecycle.SavedStateHandle;
import com.orbix.pixora.data.ads.AdService;
import com.orbix.pixora.data.credits.CreditService;
import com.orbix.pixora.data.repos.LiveWallpaperRepository;
import com.orbix.pixora.data.wallpaper.LiveApplyService;
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
public final class LiveDetailViewModel_Factory implements Factory<LiveDetailViewModel> {
  private final Provider<SavedStateHandle> savedStateHandleProvider;

  private final Provider<LiveWallpaperRepository> repoProvider;

  private final Provider<LiveApplyService> applyServiceProvider;

  private final Provider<AdService> adServiceProvider;

  private final Provider<CreditService> creditServiceProvider;

  public LiveDetailViewModel_Factory(Provider<SavedStateHandle> savedStateHandleProvider,
      Provider<LiveWallpaperRepository> repoProvider,
      Provider<LiveApplyService> applyServiceProvider, Provider<AdService> adServiceProvider,
      Provider<CreditService> creditServiceProvider) {
    this.savedStateHandleProvider = savedStateHandleProvider;
    this.repoProvider = repoProvider;
    this.applyServiceProvider = applyServiceProvider;
    this.adServiceProvider = adServiceProvider;
    this.creditServiceProvider = creditServiceProvider;
  }

  @Override
  public LiveDetailViewModel get() {
    return newInstance(savedStateHandleProvider.get(), repoProvider.get(), applyServiceProvider.get(), adServiceProvider.get(), creditServiceProvider.get());
  }

  public static LiveDetailViewModel_Factory create(
      Provider<SavedStateHandle> savedStateHandleProvider,
      Provider<LiveWallpaperRepository> repoProvider,
      Provider<LiveApplyService> applyServiceProvider, Provider<AdService> adServiceProvider,
      Provider<CreditService> creditServiceProvider) {
    return new LiveDetailViewModel_Factory(savedStateHandleProvider, repoProvider, applyServiceProvider, adServiceProvider, creditServiceProvider);
  }

  public static LiveDetailViewModel newInstance(SavedStateHandle savedStateHandle,
      LiveWallpaperRepository repo, LiveApplyService applyService, AdService adService,
      CreditService creditService) {
    return new LiveDetailViewModel(savedStateHandle, repo, applyService, adService, creditService);
  }
}
