package com.orbix.pixora.features.wallpapers;

import androidx.lifecycle.SavedStateHandle;
import com.orbix.pixora.data.ads.AdService;
import com.orbix.pixora.data.credits.CreditService;
import com.orbix.pixora.data.repos.WallpaperRepository;
import com.orbix.pixora.data.stats.WallpaperStatsService;
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
public final class WallpaperDetailViewModel_Factory implements Factory<WallpaperDetailViewModel> {
  private final Provider<SavedStateHandle> savedStateHandleProvider;

  private final Provider<WallpaperRepository> repoProvider;

  private final Provider<WallpaperApplyService> applyServiceProvider;

  private final Provider<AdService> adServiceProvider;

  private final Provider<CreditService> creditServiceProvider;

  private final Provider<WallpaperStatsService> statsServiceProvider;

  public WallpaperDetailViewModel_Factory(Provider<SavedStateHandle> savedStateHandleProvider,
      Provider<WallpaperRepository> repoProvider,
      Provider<WallpaperApplyService> applyServiceProvider, Provider<AdService> adServiceProvider,
      Provider<CreditService> creditServiceProvider,
      Provider<WallpaperStatsService> statsServiceProvider) {
    this.savedStateHandleProvider = savedStateHandleProvider;
    this.repoProvider = repoProvider;
    this.applyServiceProvider = applyServiceProvider;
    this.adServiceProvider = adServiceProvider;
    this.creditServiceProvider = creditServiceProvider;
    this.statsServiceProvider = statsServiceProvider;
  }

  @Override
  public WallpaperDetailViewModel get() {
    return newInstance(savedStateHandleProvider.get(), repoProvider.get(), applyServiceProvider.get(), adServiceProvider.get(), creditServiceProvider.get(), statsServiceProvider.get());
  }

  public static WallpaperDetailViewModel_Factory create(
      Provider<SavedStateHandle> savedStateHandleProvider,
      Provider<WallpaperRepository> repoProvider,
      Provider<WallpaperApplyService> applyServiceProvider, Provider<AdService> adServiceProvider,
      Provider<CreditService> creditServiceProvider,
      Provider<WallpaperStatsService> statsServiceProvider) {
    return new WallpaperDetailViewModel_Factory(savedStateHandleProvider, repoProvider, applyServiceProvider, adServiceProvider, creditServiceProvider, statsServiceProvider);
  }

  public static WallpaperDetailViewModel newInstance(SavedStateHandle savedStateHandle,
      WallpaperRepository repo, WallpaperApplyService applyService, AdService adService,
      CreditService creditService, WallpaperStatsService statsService) {
    return new WallpaperDetailViewModel(savedStateHandle, repo, applyService, adService, creditService, statsService);
  }
}
