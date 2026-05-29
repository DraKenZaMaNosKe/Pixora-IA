package com.orbix.pixora;

import android.app.Activity;
import android.app.Service;
import android.view.View;
import androidx.fragment.app.Fragment;
import androidx.hilt.work.HiltWorkerFactory;
import androidx.hilt.work.WorkerAssistedFactory;
import androidx.hilt.work.WorkerFactoryModule_ProvideFactoryFactory;
import androidx.lifecycle.SavedStateHandle;
import androidx.lifecycle.ViewModel;
import androidx.work.ListenableWorker;
import com.google.common.collect.ImmutableMap;
import com.google.common.collect.ImmutableSet;
import com.google.errorprone.annotations.CanIgnoreReturnValue;
import com.orbix.pixora.data.ads.AdService;
import com.orbix.pixora.data.aura.AuraPlayerService;
import com.orbix.pixora.data.auth.AuthService;
import com.orbix.pixora.data.credits.CreditService;
import com.orbix.pixora.data.db.CreditDao;
import com.orbix.pixora.data.db.FavoriteDao;
import com.orbix.pixora.data.db.PixoraDatabase;
import com.orbix.pixora.data.favorites.FavoriteService;
import com.orbix.pixora.data.repos.AuraRepository;
import com.orbix.pixora.data.repos.DayCycleRepository;
import com.orbix.pixora.data.repos.LiveWallpaperRepository;
import com.orbix.pixora.data.repos.RingtoneRepository;
import com.orbix.pixora.data.repos.StoryRepository;
import com.orbix.pixora.data.repos.WallpaperRepository;
import com.orbix.pixora.data.ringtones.RingtonePreviewPlayer;
import com.orbix.pixora.data.stats.WallpaperStatsService;
import com.orbix.pixora.data.wallpaper.LiveApplyService;
import com.orbix.pixora.data.wallpaper.WallpaperApplyService;
import com.orbix.pixora.di.DatabaseModule_ProvideCreditDaoFactory;
import com.orbix.pixora.di.DatabaseModule_ProvideDatabaseFactory;
import com.orbix.pixora.di.DatabaseModule_ProvideFavoriteDaoFactory;
import com.orbix.pixora.di.HttpModule_ProvideHttpClientFactory;
import com.orbix.pixora.di.HttpModule_ProvideJsonFactory;
import com.orbix.pixora.di.SupabaseModule_ProvideSupabaseClientFactory;
import com.orbix.pixora.features.aura.AuraMiniPlayerViewModel;
import com.orbix.pixora.features.aura.AuraMiniPlayerViewModel_HiltModules;
import com.orbix.pixora.features.aura.AuraViewModel;
import com.orbix.pixora.features.aura.AuraViewModel_HiltModules;
import com.orbix.pixora.features.daycycle.DayCycleDetailViewModel;
import com.orbix.pixora.features.daycycle.DayCycleDetailViewModel_HiltModules;
import com.orbix.pixora.features.daycycle.DayCycleViewModel;
import com.orbix.pixora.features.daycycle.DayCycleViewModel_HiltModules;
import com.orbix.pixora.features.favorites.FavoritesViewModel;
import com.orbix.pixora.features.favorites.FavoritesViewModel_HiltModules;
import com.orbix.pixora.features.live.LiveDetailViewModel;
import com.orbix.pixora.features.live.LiveDetailViewModel_HiltModules;
import com.orbix.pixora.features.live.LiveViewModel;
import com.orbix.pixora.features.live.LiveViewModel_HiltModules;
import com.orbix.pixora.features.ringtones.RingtonePackViewModel;
import com.orbix.pixora.features.ringtones.RingtonePackViewModel_HiltModules;
import com.orbix.pixora.features.ringtones.RingtonesViewModel;
import com.orbix.pixora.features.ringtones.RingtonesViewModel_HiltModules;
import com.orbix.pixora.features.settings.SettingsViewModel;
import com.orbix.pixora.features.settings.SettingsViewModel_HiltModules;
import com.orbix.pixora.features.stories.StoriesViewModel;
import com.orbix.pixora.features.stories.StoriesViewModel_HiltModules;
import com.orbix.pixora.features.stories.StoryDetailViewModel;
import com.orbix.pixora.features.stories.StoryDetailViewModel_HiltModules;
import com.orbix.pixora.features.threed.ThreeDViewModel;
import com.orbix.pixora.features.threed.ThreeDViewModel_HiltModules;
import com.orbix.pixora.features.wallpapers.WallpaperDetailViewModel;
import com.orbix.pixora.features.wallpapers.WallpaperDetailViewModel_HiltModules;
import com.orbix.pixora.features.wallpapers.WallpapersViewModel;
import com.orbix.pixora.features.wallpapers.WallpapersViewModel_HiltModules;
import com.orbix.pixora.ui.components.PixoraAppBarAuthViewModel;
import com.orbix.pixora.ui.components.PixoraAppBarAuthViewModel_HiltModules;
import com.orbix.pixora.ui.components.PixoraAppBarCreditsViewModel;
import com.orbix.pixora.ui.components.PixoraAppBarCreditsViewModel_HiltModules;
import dagger.hilt.android.ActivityRetainedLifecycle;
import dagger.hilt.android.ViewModelLifecycle;
import dagger.hilt.android.internal.builders.ActivityComponentBuilder;
import dagger.hilt.android.internal.builders.ActivityRetainedComponentBuilder;
import dagger.hilt.android.internal.builders.FragmentComponentBuilder;
import dagger.hilt.android.internal.builders.ServiceComponentBuilder;
import dagger.hilt.android.internal.builders.ViewComponentBuilder;
import dagger.hilt.android.internal.builders.ViewModelComponentBuilder;
import dagger.hilt.android.internal.builders.ViewWithFragmentComponentBuilder;
import dagger.hilt.android.internal.lifecycle.DefaultViewModelFactories;
import dagger.hilt.android.internal.lifecycle.DefaultViewModelFactories_InternalFactoryFactory_Factory;
import dagger.hilt.android.internal.managers.ActivityRetainedComponentManager_LifecycleModule_ProvideActivityRetainedLifecycleFactory;
import dagger.hilt.android.internal.managers.SavedStateHandleHolder;
import dagger.hilt.android.internal.modules.ApplicationContextModule;
import dagger.hilt.android.internal.modules.ApplicationContextModule_ProvideContextFactory;
import dagger.internal.DaggerGenerated;
import dagger.internal.DoubleCheck;
import dagger.internal.IdentifierNameString;
import dagger.internal.KeepFieldType;
import dagger.internal.LazyClassKeyMap;
import dagger.internal.Preconditions;
import dagger.internal.Provider;
import io.github.jan.supabase.SupabaseClient;
import io.ktor.client.HttpClient;
import java.util.Map;
import java.util.Set;
import javax.annotation.processing.Generated;
import kotlinx.serialization.json.Json;

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
public final class DaggerPixoraApp_HiltComponents_SingletonC {
  private DaggerPixoraApp_HiltComponents_SingletonC() {
  }

  public static Builder builder() {
    return new Builder();
  }

  public static final class Builder {
    private ApplicationContextModule applicationContextModule;

    private Builder() {
    }

    public Builder applicationContextModule(ApplicationContextModule applicationContextModule) {
      this.applicationContextModule = Preconditions.checkNotNull(applicationContextModule);
      return this;
    }

    public PixoraApp_HiltComponents.SingletonC build() {
      Preconditions.checkBuilderRequirement(applicationContextModule, ApplicationContextModule.class);
      return new SingletonCImpl(applicationContextModule);
    }
  }

  private static final class ActivityRetainedCBuilder implements PixoraApp_HiltComponents.ActivityRetainedC.Builder {
    private final SingletonCImpl singletonCImpl;

    private SavedStateHandleHolder savedStateHandleHolder;

    private ActivityRetainedCBuilder(SingletonCImpl singletonCImpl) {
      this.singletonCImpl = singletonCImpl;
    }

    @Override
    public ActivityRetainedCBuilder savedStateHandleHolder(
        SavedStateHandleHolder savedStateHandleHolder) {
      this.savedStateHandleHolder = Preconditions.checkNotNull(savedStateHandleHolder);
      return this;
    }

    @Override
    public PixoraApp_HiltComponents.ActivityRetainedC build() {
      Preconditions.checkBuilderRequirement(savedStateHandleHolder, SavedStateHandleHolder.class);
      return new ActivityRetainedCImpl(singletonCImpl, savedStateHandleHolder);
    }
  }

  private static final class ActivityCBuilder implements PixoraApp_HiltComponents.ActivityC.Builder {
    private final SingletonCImpl singletonCImpl;

    private final ActivityRetainedCImpl activityRetainedCImpl;

    private Activity activity;

    private ActivityCBuilder(SingletonCImpl singletonCImpl,
        ActivityRetainedCImpl activityRetainedCImpl) {
      this.singletonCImpl = singletonCImpl;
      this.activityRetainedCImpl = activityRetainedCImpl;
    }

    @Override
    public ActivityCBuilder activity(Activity activity) {
      this.activity = Preconditions.checkNotNull(activity);
      return this;
    }

    @Override
    public PixoraApp_HiltComponents.ActivityC build() {
      Preconditions.checkBuilderRequirement(activity, Activity.class);
      return new ActivityCImpl(singletonCImpl, activityRetainedCImpl, activity);
    }
  }

  private static final class FragmentCBuilder implements PixoraApp_HiltComponents.FragmentC.Builder {
    private final SingletonCImpl singletonCImpl;

    private final ActivityRetainedCImpl activityRetainedCImpl;

    private final ActivityCImpl activityCImpl;

    private Fragment fragment;

    private FragmentCBuilder(SingletonCImpl singletonCImpl,
        ActivityRetainedCImpl activityRetainedCImpl, ActivityCImpl activityCImpl) {
      this.singletonCImpl = singletonCImpl;
      this.activityRetainedCImpl = activityRetainedCImpl;
      this.activityCImpl = activityCImpl;
    }

    @Override
    public FragmentCBuilder fragment(Fragment fragment) {
      this.fragment = Preconditions.checkNotNull(fragment);
      return this;
    }

    @Override
    public PixoraApp_HiltComponents.FragmentC build() {
      Preconditions.checkBuilderRequirement(fragment, Fragment.class);
      return new FragmentCImpl(singletonCImpl, activityRetainedCImpl, activityCImpl, fragment);
    }
  }

  private static final class ViewWithFragmentCBuilder implements PixoraApp_HiltComponents.ViewWithFragmentC.Builder {
    private final SingletonCImpl singletonCImpl;

    private final ActivityRetainedCImpl activityRetainedCImpl;

    private final ActivityCImpl activityCImpl;

    private final FragmentCImpl fragmentCImpl;

    private View view;

    private ViewWithFragmentCBuilder(SingletonCImpl singletonCImpl,
        ActivityRetainedCImpl activityRetainedCImpl, ActivityCImpl activityCImpl,
        FragmentCImpl fragmentCImpl) {
      this.singletonCImpl = singletonCImpl;
      this.activityRetainedCImpl = activityRetainedCImpl;
      this.activityCImpl = activityCImpl;
      this.fragmentCImpl = fragmentCImpl;
    }

    @Override
    public ViewWithFragmentCBuilder view(View view) {
      this.view = Preconditions.checkNotNull(view);
      return this;
    }

    @Override
    public PixoraApp_HiltComponents.ViewWithFragmentC build() {
      Preconditions.checkBuilderRequirement(view, View.class);
      return new ViewWithFragmentCImpl(singletonCImpl, activityRetainedCImpl, activityCImpl, fragmentCImpl, view);
    }
  }

  private static final class ViewCBuilder implements PixoraApp_HiltComponents.ViewC.Builder {
    private final SingletonCImpl singletonCImpl;

    private final ActivityRetainedCImpl activityRetainedCImpl;

    private final ActivityCImpl activityCImpl;

    private View view;

    private ViewCBuilder(SingletonCImpl singletonCImpl, ActivityRetainedCImpl activityRetainedCImpl,
        ActivityCImpl activityCImpl) {
      this.singletonCImpl = singletonCImpl;
      this.activityRetainedCImpl = activityRetainedCImpl;
      this.activityCImpl = activityCImpl;
    }

    @Override
    public ViewCBuilder view(View view) {
      this.view = Preconditions.checkNotNull(view);
      return this;
    }

    @Override
    public PixoraApp_HiltComponents.ViewC build() {
      Preconditions.checkBuilderRequirement(view, View.class);
      return new ViewCImpl(singletonCImpl, activityRetainedCImpl, activityCImpl, view);
    }
  }

  private static final class ViewModelCBuilder implements PixoraApp_HiltComponents.ViewModelC.Builder {
    private final SingletonCImpl singletonCImpl;

    private final ActivityRetainedCImpl activityRetainedCImpl;

    private SavedStateHandle savedStateHandle;

    private ViewModelLifecycle viewModelLifecycle;

    private ViewModelCBuilder(SingletonCImpl singletonCImpl,
        ActivityRetainedCImpl activityRetainedCImpl) {
      this.singletonCImpl = singletonCImpl;
      this.activityRetainedCImpl = activityRetainedCImpl;
    }

    @Override
    public ViewModelCBuilder savedStateHandle(SavedStateHandle handle) {
      this.savedStateHandle = Preconditions.checkNotNull(handle);
      return this;
    }

    @Override
    public ViewModelCBuilder viewModelLifecycle(ViewModelLifecycle viewModelLifecycle) {
      this.viewModelLifecycle = Preconditions.checkNotNull(viewModelLifecycle);
      return this;
    }

    @Override
    public PixoraApp_HiltComponents.ViewModelC build() {
      Preconditions.checkBuilderRequirement(savedStateHandle, SavedStateHandle.class);
      Preconditions.checkBuilderRequirement(viewModelLifecycle, ViewModelLifecycle.class);
      return new ViewModelCImpl(singletonCImpl, activityRetainedCImpl, savedStateHandle, viewModelLifecycle);
    }
  }

  private static final class ServiceCBuilder implements PixoraApp_HiltComponents.ServiceC.Builder {
    private final SingletonCImpl singletonCImpl;

    private Service service;

    private ServiceCBuilder(SingletonCImpl singletonCImpl) {
      this.singletonCImpl = singletonCImpl;
    }

    @Override
    public ServiceCBuilder service(Service service) {
      this.service = Preconditions.checkNotNull(service);
      return this;
    }

    @Override
    public PixoraApp_HiltComponents.ServiceC build() {
      Preconditions.checkBuilderRequirement(service, Service.class);
      return new ServiceCImpl(singletonCImpl, service);
    }
  }

  private static final class ViewWithFragmentCImpl extends PixoraApp_HiltComponents.ViewWithFragmentC {
    private final SingletonCImpl singletonCImpl;

    private final ActivityRetainedCImpl activityRetainedCImpl;

    private final ActivityCImpl activityCImpl;

    private final FragmentCImpl fragmentCImpl;

    private final ViewWithFragmentCImpl viewWithFragmentCImpl = this;

    private ViewWithFragmentCImpl(SingletonCImpl singletonCImpl,
        ActivityRetainedCImpl activityRetainedCImpl, ActivityCImpl activityCImpl,
        FragmentCImpl fragmentCImpl, View viewParam) {
      this.singletonCImpl = singletonCImpl;
      this.activityRetainedCImpl = activityRetainedCImpl;
      this.activityCImpl = activityCImpl;
      this.fragmentCImpl = fragmentCImpl;


    }
  }

  private static final class FragmentCImpl extends PixoraApp_HiltComponents.FragmentC {
    private final SingletonCImpl singletonCImpl;

    private final ActivityRetainedCImpl activityRetainedCImpl;

    private final ActivityCImpl activityCImpl;

    private final FragmentCImpl fragmentCImpl = this;

    private FragmentCImpl(SingletonCImpl singletonCImpl,
        ActivityRetainedCImpl activityRetainedCImpl, ActivityCImpl activityCImpl,
        Fragment fragmentParam) {
      this.singletonCImpl = singletonCImpl;
      this.activityRetainedCImpl = activityRetainedCImpl;
      this.activityCImpl = activityCImpl;


    }

    @Override
    public DefaultViewModelFactories.InternalFactoryFactory getHiltInternalFactoryFactory() {
      return activityCImpl.getHiltInternalFactoryFactory();
    }

    @Override
    public ViewWithFragmentComponentBuilder viewWithFragmentComponentBuilder() {
      return new ViewWithFragmentCBuilder(singletonCImpl, activityRetainedCImpl, activityCImpl, fragmentCImpl);
    }
  }

  private static final class ViewCImpl extends PixoraApp_HiltComponents.ViewC {
    private final SingletonCImpl singletonCImpl;

    private final ActivityRetainedCImpl activityRetainedCImpl;

    private final ActivityCImpl activityCImpl;

    private final ViewCImpl viewCImpl = this;

    private ViewCImpl(SingletonCImpl singletonCImpl, ActivityRetainedCImpl activityRetainedCImpl,
        ActivityCImpl activityCImpl, View viewParam) {
      this.singletonCImpl = singletonCImpl;
      this.activityRetainedCImpl = activityRetainedCImpl;
      this.activityCImpl = activityCImpl;


    }
  }

  private static final class ActivityCImpl extends PixoraApp_HiltComponents.ActivityC {
    private final SingletonCImpl singletonCImpl;

    private final ActivityRetainedCImpl activityRetainedCImpl;

    private final ActivityCImpl activityCImpl = this;

    private ActivityCImpl(SingletonCImpl singletonCImpl,
        ActivityRetainedCImpl activityRetainedCImpl, Activity activityParam) {
      this.singletonCImpl = singletonCImpl;
      this.activityRetainedCImpl = activityRetainedCImpl;


    }

    @Override
    public void injectMainActivity(MainActivity mainActivity) {
    }

    @Override
    public DefaultViewModelFactories.InternalFactoryFactory getHiltInternalFactoryFactory() {
      return DefaultViewModelFactories_InternalFactoryFactory_Factory.newInstance(getViewModelKeys(), new ViewModelCBuilder(singletonCImpl, activityRetainedCImpl));
    }

    @Override
    public Map<Class<?>, Boolean> getViewModelKeys() {
      return LazyClassKeyMap.<Boolean>of(ImmutableMap.<String, Boolean>builderWithExpectedSize(17).put(LazyClassKeyProvider.com_orbix_pixora_features_aura_AuraMiniPlayerViewModel, AuraMiniPlayerViewModel_HiltModules.KeyModule.provide()).put(LazyClassKeyProvider.com_orbix_pixora_features_aura_AuraViewModel, AuraViewModel_HiltModules.KeyModule.provide()).put(LazyClassKeyProvider.com_orbix_pixora_features_daycycle_DayCycleDetailViewModel, DayCycleDetailViewModel_HiltModules.KeyModule.provide()).put(LazyClassKeyProvider.com_orbix_pixora_features_daycycle_DayCycleViewModel, DayCycleViewModel_HiltModules.KeyModule.provide()).put(LazyClassKeyProvider.com_orbix_pixora_features_favorites_FavoritesViewModel, FavoritesViewModel_HiltModules.KeyModule.provide()).put(LazyClassKeyProvider.com_orbix_pixora_features_live_LiveDetailViewModel, LiveDetailViewModel_HiltModules.KeyModule.provide()).put(LazyClassKeyProvider.com_orbix_pixora_features_live_LiveViewModel, LiveViewModel_HiltModules.KeyModule.provide()).put(LazyClassKeyProvider.com_orbix_pixora_ui_components_PixoraAppBarAuthViewModel, PixoraAppBarAuthViewModel_HiltModules.KeyModule.provide()).put(LazyClassKeyProvider.com_orbix_pixora_ui_components_PixoraAppBarCreditsViewModel, PixoraAppBarCreditsViewModel_HiltModules.KeyModule.provide()).put(LazyClassKeyProvider.com_orbix_pixora_features_ringtones_RingtonePackViewModel, RingtonePackViewModel_HiltModules.KeyModule.provide()).put(LazyClassKeyProvider.com_orbix_pixora_features_ringtones_RingtonesViewModel, RingtonesViewModel_HiltModules.KeyModule.provide()).put(LazyClassKeyProvider.com_orbix_pixora_features_settings_SettingsViewModel, SettingsViewModel_HiltModules.KeyModule.provide()).put(LazyClassKeyProvider.com_orbix_pixora_features_stories_StoriesViewModel, StoriesViewModel_HiltModules.KeyModule.provide()).put(LazyClassKeyProvider.com_orbix_pixora_features_stories_StoryDetailViewModel, StoryDetailViewModel_HiltModules.KeyModule.provide()).put(LazyClassKeyProvider.com_orbix_pixora_features_threed_ThreeDViewModel, ThreeDViewModel_HiltModules.KeyModule.provide()).put(LazyClassKeyProvider.com_orbix_pixora_features_wallpapers_WallpaperDetailViewModel, WallpaperDetailViewModel_HiltModules.KeyModule.provide()).put(LazyClassKeyProvider.com_orbix_pixora_features_wallpapers_WallpapersViewModel, WallpapersViewModel_HiltModules.KeyModule.provide()).build());
    }

    @Override
    public ViewModelComponentBuilder getViewModelComponentBuilder() {
      return new ViewModelCBuilder(singletonCImpl, activityRetainedCImpl);
    }

    @Override
    public FragmentComponentBuilder fragmentComponentBuilder() {
      return new FragmentCBuilder(singletonCImpl, activityRetainedCImpl, activityCImpl);
    }

    @Override
    public ViewComponentBuilder viewComponentBuilder() {
      return new ViewCBuilder(singletonCImpl, activityRetainedCImpl, activityCImpl);
    }

    @IdentifierNameString
    private static final class LazyClassKeyProvider {
      static String com_orbix_pixora_features_aura_AuraViewModel = "com.orbix.pixora.features.aura.AuraViewModel";

      static String com_orbix_pixora_features_daycycle_DayCycleViewModel = "com.orbix.pixora.features.daycycle.DayCycleViewModel";

      static String com_orbix_pixora_features_daycycle_DayCycleDetailViewModel = "com.orbix.pixora.features.daycycle.DayCycleDetailViewModel";

      static String com_orbix_pixora_features_ringtones_RingtonesViewModel = "com.orbix.pixora.features.ringtones.RingtonesViewModel";

      static String com_orbix_pixora_features_settings_SettingsViewModel = "com.orbix.pixora.features.settings.SettingsViewModel";

      static String com_orbix_pixora_features_threed_ThreeDViewModel = "com.orbix.pixora.features.threed.ThreeDViewModel";

      static String com_orbix_pixora_features_wallpapers_WallpaperDetailViewModel = "com.orbix.pixora.features.wallpapers.WallpaperDetailViewModel";

      static String com_orbix_pixora_features_stories_StoriesViewModel = "com.orbix.pixora.features.stories.StoriesViewModel";

      static String com_orbix_pixora_features_favorites_FavoritesViewModel = "com.orbix.pixora.features.favorites.FavoritesViewModel";

      static String com_orbix_pixora_ui_components_PixoraAppBarAuthViewModel = "com.orbix.pixora.ui.components.PixoraAppBarAuthViewModel";

      static String com_orbix_pixora_features_ringtones_RingtonePackViewModel = "com.orbix.pixora.features.ringtones.RingtonePackViewModel";

      static String com_orbix_pixora_features_wallpapers_WallpapersViewModel = "com.orbix.pixora.features.wallpapers.WallpapersViewModel";

      static String com_orbix_pixora_features_live_LiveViewModel = "com.orbix.pixora.features.live.LiveViewModel";

      static String com_orbix_pixora_ui_components_PixoraAppBarCreditsViewModel = "com.orbix.pixora.ui.components.PixoraAppBarCreditsViewModel";

      static String com_orbix_pixora_features_aura_AuraMiniPlayerViewModel = "com.orbix.pixora.features.aura.AuraMiniPlayerViewModel";

      static String com_orbix_pixora_features_stories_StoryDetailViewModel = "com.orbix.pixora.features.stories.StoryDetailViewModel";

      static String com_orbix_pixora_features_live_LiveDetailViewModel = "com.orbix.pixora.features.live.LiveDetailViewModel";

      @KeepFieldType
      AuraViewModel com_orbix_pixora_features_aura_AuraViewModel2;

      @KeepFieldType
      DayCycleViewModel com_orbix_pixora_features_daycycle_DayCycleViewModel2;

      @KeepFieldType
      DayCycleDetailViewModel com_orbix_pixora_features_daycycle_DayCycleDetailViewModel2;

      @KeepFieldType
      RingtonesViewModel com_orbix_pixora_features_ringtones_RingtonesViewModel2;

      @KeepFieldType
      SettingsViewModel com_orbix_pixora_features_settings_SettingsViewModel2;

      @KeepFieldType
      ThreeDViewModel com_orbix_pixora_features_threed_ThreeDViewModel2;

      @KeepFieldType
      WallpaperDetailViewModel com_orbix_pixora_features_wallpapers_WallpaperDetailViewModel2;

      @KeepFieldType
      StoriesViewModel com_orbix_pixora_features_stories_StoriesViewModel2;

      @KeepFieldType
      FavoritesViewModel com_orbix_pixora_features_favorites_FavoritesViewModel2;

      @KeepFieldType
      PixoraAppBarAuthViewModel com_orbix_pixora_ui_components_PixoraAppBarAuthViewModel2;

      @KeepFieldType
      RingtonePackViewModel com_orbix_pixora_features_ringtones_RingtonePackViewModel2;

      @KeepFieldType
      WallpapersViewModel com_orbix_pixora_features_wallpapers_WallpapersViewModel2;

      @KeepFieldType
      LiveViewModel com_orbix_pixora_features_live_LiveViewModel2;

      @KeepFieldType
      PixoraAppBarCreditsViewModel com_orbix_pixora_ui_components_PixoraAppBarCreditsViewModel2;

      @KeepFieldType
      AuraMiniPlayerViewModel com_orbix_pixora_features_aura_AuraMiniPlayerViewModel2;

      @KeepFieldType
      StoryDetailViewModel com_orbix_pixora_features_stories_StoryDetailViewModel2;

      @KeepFieldType
      LiveDetailViewModel com_orbix_pixora_features_live_LiveDetailViewModel2;
    }
  }

  private static final class ViewModelCImpl extends PixoraApp_HiltComponents.ViewModelC {
    private final SavedStateHandle savedStateHandle;

    private final SingletonCImpl singletonCImpl;

    private final ActivityRetainedCImpl activityRetainedCImpl;

    private final ViewModelCImpl viewModelCImpl = this;

    private Provider<AuraMiniPlayerViewModel> auraMiniPlayerViewModelProvider;

    private Provider<AuraViewModel> auraViewModelProvider;

    private Provider<DayCycleDetailViewModel> dayCycleDetailViewModelProvider;

    private Provider<DayCycleViewModel> dayCycleViewModelProvider;

    private Provider<FavoritesViewModel> favoritesViewModelProvider;

    private Provider<LiveDetailViewModel> liveDetailViewModelProvider;

    private Provider<LiveViewModel> liveViewModelProvider;

    private Provider<PixoraAppBarAuthViewModel> pixoraAppBarAuthViewModelProvider;

    private Provider<PixoraAppBarCreditsViewModel> pixoraAppBarCreditsViewModelProvider;

    private Provider<RingtonePackViewModel> ringtonePackViewModelProvider;

    private Provider<RingtonesViewModel> ringtonesViewModelProvider;

    private Provider<SettingsViewModel> settingsViewModelProvider;

    private Provider<StoriesViewModel> storiesViewModelProvider;

    private Provider<StoryDetailViewModel> storyDetailViewModelProvider;

    private Provider<ThreeDViewModel> threeDViewModelProvider;

    private Provider<WallpaperDetailViewModel> wallpaperDetailViewModelProvider;

    private Provider<WallpapersViewModel> wallpapersViewModelProvider;

    private ViewModelCImpl(SingletonCImpl singletonCImpl,
        ActivityRetainedCImpl activityRetainedCImpl, SavedStateHandle savedStateHandleParam,
        ViewModelLifecycle viewModelLifecycleParam) {
      this.singletonCImpl = singletonCImpl;
      this.activityRetainedCImpl = activityRetainedCImpl;
      this.savedStateHandle = savedStateHandleParam;
      initialize(savedStateHandleParam, viewModelLifecycleParam);

    }

    @SuppressWarnings("unchecked")
    private void initialize(final SavedStateHandle savedStateHandleParam,
        final ViewModelLifecycle viewModelLifecycleParam) {
      this.auraMiniPlayerViewModelProvider = new SwitchingProvider<>(singletonCImpl, activityRetainedCImpl, viewModelCImpl, 0);
      this.auraViewModelProvider = new SwitchingProvider<>(singletonCImpl, activityRetainedCImpl, viewModelCImpl, 1);
      this.dayCycleDetailViewModelProvider = new SwitchingProvider<>(singletonCImpl, activityRetainedCImpl, viewModelCImpl, 2);
      this.dayCycleViewModelProvider = new SwitchingProvider<>(singletonCImpl, activityRetainedCImpl, viewModelCImpl, 3);
      this.favoritesViewModelProvider = new SwitchingProvider<>(singletonCImpl, activityRetainedCImpl, viewModelCImpl, 4);
      this.liveDetailViewModelProvider = new SwitchingProvider<>(singletonCImpl, activityRetainedCImpl, viewModelCImpl, 5);
      this.liveViewModelProvider = new SwitchingProvider<>(singletonCImpl, activityRetainedCImpl, viewModelCImpl, 6);
      this.pixoraAppBarAuthViewModelProvider = new SwitchingProvider<>(singletonCImpl, activityRetainedCImpl, viewModelCImpl, 7);
      this.pixoraAppBarCreditsViewModelProvider = new SwitchingProvider<>(singletonCImpl, activityRetainedCImpl, viewModelCImpl, 8);
      this.ringtonePackViewModelProvider = new SwitchingProvider<>(singletonCImpl, activityRetainedCImpl, viewModelCImpl, 9);
      this.ringtonesViewModelProvider = new SwitchingProvider<>(singletonCImpl, activityRetainedCImpl, viewModelCImpl, 10);
      this.settingsViewModelProvider = new SwitchingProvider<>(singletonCImpl, activityRetainedCImpl, viewModelCImpl, 11);
      this.storiesViewModelProvider = new SwitchingProvider<>(singletonCImpl, activityRetainedCImpl, viewModelCImpl, 12);
      this.storyDetailViewModelProvider = new SwitchingProvider<>(singletonCImpl, activityRetainedCImpl, viewModelCImpl, 13);
      this.threeDViewModelProvider = new SwitchingProvider<>(singletonCImpl, activityRetainedCImpl, viewModelCImpl, 14);
      this.wallpaperDetailViewModelProvider = new SwitchingProvider<>(singletonCImpl, activityRetainedCImpl, viewModelCImpl, 15);
      this.wallpapersViewModelProvider = new SwitchingProvider<>(singletonCImpl, activityRetainedCImpl, viewModelCImpl, 16);
    }

    @Override
    public Map<Class<?>, javax.inject.Provider<ViewModel>> getHiltViewModelMap() {
      return LazyClassKeyMap.<javax.inject.Provider<ViewModel>>of(ImmutableMap.<String, javax.inject.Provider<ViewModel>>builderWithExpectedSize(17).put(LazyClassKeyProvider.com_orbix_pixora_features_aura_AuraMiniPlayerViewModel, ((Provider) auraMiniPlayerViewModelProvider)).put(LazyClassKeyProvider.com_orbix_pixora_features_aura_AuraViewModel, ((Provider) auraViewModelProvider)).put(LazyClassKeyProvider.com_orbix_pixora_features_daycycle_DayCycleDetailViewModel, ((Provider) dayCycleDetailViewModelProvider)).put(LazyClassKeyProvider.com_orbix_pixora_features_daycycle_DayCycleViewModel, ((Provider) dayCycleViewModelProvider)).put(LazyClassKeyProvider.com_orbix_pixora_features_favorites_FavoritesViewModel, ((Provider) favoritesViewModelProvider)).put(LazyClassKeyProvider.com_orbix_pixora_features_live_LiveDetailViewModel, ((Provider) liveDetailViewModelProvider)).put(LazyClassKeyProvider.com_orbix_pixora_features_live_LiveViewModel, ((Provider) liveViewModelProvider)).put(LazyClassKeyProvider.com_orbix_pixora_ui_components_PixoraAppBarAuthViewModel, ((Provider) pixoraAppBarAuthViewModelProvider)).put(LazyClassKeyProvider.com_orbix_pixora_ui_components_PixoraAppBarCreditsViewModel, ((Provider) pixoraAppBarCreditsViewModelProvider)).put(LazyClassKeyProvider.com_orbix_pixora_features_ringtones_RingtonePackViewModel, ((Provider) ringtonePackViewModelProvider)).put(LazyClassKeyProvider.com_orbix_pixora_features_ringtones_RingtonesViewModel, ((Provider) ringtonesViewModelProvider)).put(LazyClassKeyProvider.com_orbix_pixora_features_settings_SettingsViewModel, ((Provider) settingsViewModelProvider)).put(LazyClassKeyProvider.com_orbix_pixora_features_stories_StoriesViewModel, ((Provider) storiesViewModelProvider)).put(LazyClassKeyProvider.com_orbix_pixora_features_stories_StoryDetailViewModel, ((Provider) storyDetailViewModelProvider)).put(LazyClassKeyProvider.com_orbix_pixora_features_threed_ThreeDViewModel, ((Provider) threeDViewModelProvider)).put(LazyClassKeyProvider.com_orbix_pixora_features_wallpapers_WallpaperDetailViewModel, ((Provider) wallpaperDetailViewModelProvider)).put(LazyClassKeyProvider.com_orbix_pixora_features_wallpapers_WallpapersViewModel, ((Provider) wallpapersViewModelProvider)).build());
    }

    @Override
    public Map<Class<?>, Object> getHiltViewModelAssistedMap() {
      return ImmutableMap.<Class<?>, Object>of();
    }

    @IdentifierNameString
    private static final class LazyClassKeyProvider {
      static String com_orbix_pixora_ui_components_PixoraAppBarAuthViewModel = "com.orbix.pixora.ui.components.PixoraAppBarAuthViewModel";

      static String com_orbix_pixora_features_favorites_FavoritesViewModel = "com.orbix.pixora.features.favorites.FavoritesViewModel";

      static String com_orbix_pixora_features_wallpapers_WallpapersViewModel = "com.orbix.pixora.features.wallpapers.WallpapersViewModel";

      static String com_orbix_pixora_ui_components_PixoraAppBarCreditsViewModel = "com.orbix.pixora.ui.components.PixoraAppBarCreditsViewModel";

      static String com_orbix_pixora_features_daycycle_DayCycleDetailViewModel = "com.orbix.pixora.features.daycycle.DayCycleDetailViewModel";

      static String com_orbix_pixora_features_settings_SettingsViewModel = "com.orbix.pixora.features.settings.SettingsViewModel";

      static String com_orbix_pixora_features_aura_AuraMiniPlayerViewModel = "com.orbix.pixora.features.aura.AuraMiniPlayerViewModel";

      static String com_orbix_pixora_features_live_LiveViewModel = "com.orbix.pixora.features.live.LiveViewModel";

      static String com_orbix_pixora_features_ringtones_RingtonePackViewModel = "com.orbix.pixora.features.ringtones.RingtonePackViewModel";

      static String com_orbix_pixora_features_live_LiveDetailViewModel = "com.orbix.pixora.features.live.LiveDetailViewModel";

      static String com_orbix_pixora_features_ringtones_RingtonesViewModel = "com.orbix.pixora.features.ringtones.RingtonesViewModel";

      static String com_orbix_pixora_features_daycycle_DayCycleViewModel = "com.orbix.pixora.features.daycycle.DayCycleViewModel";

      static String com_orbix_pixora_features_stories_StoriesViewModel = "com.orbix.pixora.features.stories.StoriesViewModel";

      static String com_orbix_pixora_features_wallpapers_WallpaperDetailViewModel = "com.orbix.pixora.features.wallpapers.WallpaperDetailViewModel";

      static String com_orbix_pixora_features_threed_ThreeDViewModel = "com.orbix.pixora.features.threed.ThreeDViewModel";

      static String com_orbix_pixora_features_aura_AuraViewModel = "com.orbix.pixora.features.aura.AuraViewModel";

      static String com_orbix_pixora_features_stories_StoryDetailViewModel = "com.orbix.pixora.features.stories.StoryDetailViewModel";

      @KeepFieldType
      PixoraAppBarAuthViewModel com_orbix_pixora_ui_components_PixoraAppBarAuthViewModel2;

      @KeepFieldType
      FavoritesViewModel com_orbix_pixora_features_favorites_FavoritesViewModel2;

      @KeepFieldType
      WallpapersViewModel com_orbix_pixora_features_wallpapers_WallpapersViewModel2;

      @KeepFieldType
      PixoraAppBarCreditsViewModel com_orbix_pixora_ui_components_PixoraAppBarCreditsViewModel2;

      @KeepFieldType
      DayCycleDetailViewModel com_orbix_pixora_features_daycycle_DayCycleDetailViewModel2;

      @KeepFieldType
      SettingsViewModel com_orbix_pixora_features_settings_SettingsViewModel2;

      @KeepFieldType
      AuraMiniPlayerViewModel com_orbix_pixora_features_aura_AuraMiniPlayerViewModel2;

      @KeepFieldType
      LiveViewModel com_orbix_pixora_features_live_LiveViewModel2;

      @KeepFieldType
      RingtonePackViewModel com_orbix_pixora_features_ringtones_RingtonePackViewModel2;

      @KeepFieldType
      LiveDetailViewModel com_orbix_pixora_features_live_LiveDetailViewModel2;

      @KeepFieldType
      RingtonesViewModel com_orbix_pixora_features_ringtones_RingtonesViewModel2;

      @KeepFieldType
      DayCycleViewModel com_orbix_pixora_features_daycycle_DayCycleViewModel2;

      @KeepFieldType
      StoriesViewModel com_orbix_pixora_features_stories_StoriesViewModel2;

      @KeepFieldType
      WallpaperDetailViewModel com_orbix_pixora_features_wallpapers_WallpaperDetailViewModel2;

      @KeepFieldType
      ThreeDViewModel com_orbix_pixora_features_threed_ThreeDViewModel2;

      @KeepFieldType
      AuraViewModel com_orbix_pixora_features_aura_AuraViewModel2;

      @KeepFieldType
      StoryDetailViewModel com_orbix_pixora_features_stories_StoryDetailViewModel2;
    }

    private static final class SwitchingProvider<T> implements Provider<T> {
      private final SingletonCImpl singletonCImpl;

      private final ActivityRetainedCImpl activityRetainedCImpl;

      private final ViewModelCImpl viewModelCImpl;

      private final int id;

      SwitchingProvider(SingletonCImpl singletonCImpl, ActivityRetainedCImpl activityRetainedCImpl,
          ViewModelCImpl viewModelCImpl, int id) {
        this.singletonCImpl = singletonCImpl;
        this.activityRetainedCImpl = activityRetainedCImpl;
        this.viewModelCImpl = viewModelCImpl;
        this.id = id;
      }

      @SuppressWarnings("unchecked")
      @Override
      public T get() {
        switch (id) {
          case 0: // com.orbix.pixora.features.aura.AuraMiniPlayerViewModel 
          return (T) new AuraMiniPlayerViewModel(singletonCImpl.auraPlayerServiceProvider.get());

          case 1: // com.orbix.pixora.features.aura.AuraViewModel 
          return (T) new AuraViewModel(singletonCImpl.auraRepositoryProvider.get(), singletonCImpl.auraPlayerServiceProvider.get());

          case 2: // com.orbix.pixora.features.daycycle.DayCycleDetailViewModel 
          return (T) new DayCycleDetailViewModel(viewModelCImpl.savedStateHandle, singletonCImpl.dayCycleRepositoryProvider.get(), singletonCImpl.wallpaperApplyServiceProvider.get());

          case 3: // com.orbix.pixora.features.daycycle.DayCycleViewModel 
          return (T) new DayCycleViewModel(singletonCImpl.dayCycleRepositoryProvider.get());

          case 4: // com.orbix.pixora.features.favorites.FavoritesViewModel 
          return (T) new FavoritesViewModel(singletonCImpl.favoriteServiceProvider.get());

          case 5: // com.orbix.pixora.features.live.LiveDetailViewModel 
          return (T) new LiveDetailViewModel(viewModelCImpl.savedStateHandle, singletonCImpl.liveWallpaperRepositoryProvider.get(), singletonCImpl.liveApplyServiceProvider.get(), singletonCImpl.adServiceProvider.get(), singletonCImpl.creditServiceProvider.get());

          case 6: // com.orbix.pixora.features.live.LiveViewModel 
          return (T) new LiveViewModel(singletonCImpl.liveWallpaperRepositoryProvider.get());

          case 7: // com.orbix.pixora.ui.components.PixoraAppBarAuthViewModel 
          return (T) new PixoraAppBarAuthViewModel(singletonCImpl.authServiceProvider.get());

          case 8: // com.orbix.pixora.ui.components.PixoraAppBarCreditsViewModel 
          return (T) new PixoraAppBarCreditsViewModel(singletonCImpl.creditServiceProvider.get());

          case 9: // com.orbix.pixora.features.ringtones.RingtonePackViewModel 
          return (T) new RingtonePackViewModel(viewModelCImpl.savedStateHandle, singletonCImpl.ringtoneRepositoryProvider.get(), singletonCImpl.ringtonePreviewPlayerProvider.get());

          case 10: // com.orbix.pixora.features.ringtones.RingtonesViewModel 
          return (T) new RingtonesViewModel(singletonCImpl.ringtoneRepositoryProvider.get(), singletonCImpl.ringtonePreviewPlayerProvider.get());

          case 11: // com.orbix.pixora.features.settings.SettingsViewModel 
          return (T) new SettingsViewModel(singletonCImpl.creditServiceProvider.get());

          case 12: // com.orbix.pixora.features.stories.StoriesViewModel 
          return (T) new StoriesViewModel(singletonCImpl.storyRepositoryProvider.get());

          case 13: // com.orbix.pixora.features.stories.StoryDetailViewModel 
          return (T) new StoryDetailViewModel(viewModelCImpl.savedStateHandle, singletonCImpl.storyRepositoryProvider.get(), singletonCImpl.wallpaperApplyServiceProvider.get());

          case 14: // com.orbix.pixora.features.threed.ThreeDViewModel 
          return (T) new ThreeDViewModel(singletonCImpl.wallpaperRepositoryProvider.get());

          case 15: // com.orbix.pixora.features.wallpapers.WallpaperDetailViewModel 
          return (T) new WallpaperDetailViewModel(viewModelCImpl.savedStateHandle, singletonCImpl.wallpaperRepositoryProvider.get(), singletonCImpl.wallpaperApplyServiceProvider.get(), singletonCImpl.adServiceProvider.get(), singletonCImpl.creditServiceProvider.get(), singletonCImpl.wallpaperStatsServiceProvider.get());

          case 16: // com.orbix.pixora.features.wallpapers.WallpapersViewModel 
          return (T) new WallpapersViewModel(singletonCImpl.wallpaperRepositoryProvider.get(), singletonCImpl.favoriteServiceProvider.get());

          default: throw new AssertionError(id);
        }
      }
    }
  }

  private static final class ActivityRetainedCImpl extends PixoraApp_HiltComponents.ActivityRetainedC {
    private final SingletonCImpl singletonCImpl;

    private final ActivityRetainedCImpl activityRetainedCImpl = this;

    private Provider<ActivityRetainedLifecycle> provideActivityRetainedLifecycleProvider;

    private ActivityRetainedCImpl(SingletonCImpl singletonCImpl,
        SavedStateHandleHolder savedStateHandleHolderParam) {
      this.singletonCImpl = singletonCImpl;

      initialize(savedStateHandleHolderParam);

    }

    @SuppressWarnings("unchecked")
    private void initialize(final SavedStateHandleHolder savedStateHandleHolderParam) {
      this.provideActivityRetainedLifecycleProvider = DoubleCheck.provider(new SwitchingProvider<ActivityRetainedLifecycle>(singletonCImpl, activityRetainedCImpl, 0));
    }

    @Override
    public ActivityComponentBuilder activityComponentBuilder() {
      return new ActivityCBuilder(singletonCImpl, activityRetainedCImpl);
    }

    @Override
    public ActivityRetainedLifecycle getActivityRetainedLifecycle() {
      return provideActivityRetainedLifecycleProvider.get();
    }

    private static final class SwitchingProvider<T> implements Provider<T> {
      private final SingletonCImpl singletonCImpl;

      private final ActivityRetainedCImpl activityRetainedCImpl;

      private final int id;

      SwitchingProvider(SingletonCImpl singletonCImpl, ActivityRetainedCImpl activityRetainedCImpl,
          int id) {
        this.singletonCImpl = singletonCImpl;
        this.activityRetainedCImpl = activityRetainedCImpl;
        this.id = id;
      }

      @SuppressWarnings("unchecked")
      @Override
      public T get() {
        switch (id) {
          case 0: // dagger.hilt.android.ActivityRetainedLifecycle 
          return (T) ActivityRetainedComponentManager_LifecycleModule_ProvideActivityRetainedLifecycleFactory.provideActivityRetainedLifecycle();

          default: throw new AssertionError(id);
        }
      }
    }
  }

  private static final class ServiceCImpl extends PixoraApp_HiltComponents.ServiceC {
    private final SingletonCImpl singletonCImpl;

    private final ServiceCImpl serviceCImpl = this;

    private ServiceCImpl(SingletonCImpl singletonCImpl, Service serviceParam) {
      this.singletonCImpl = singletonCImpl;


    }
  }

  private static final class SingletonCImpl extends PixoraApp_HiltComponents.SingletonC {
    private final ApplicationContextModule applicationContextModule;

    private final SingletonCImpl singletonCImpl = this;

    private Provider<AuraPlayerService> auraPlayerServiceProvider;

    private Provider<SupabaseClient> provideSupabaseClientProvider;

    private Provider<AuraRepository> auraRepositoryProvider;

    private Provider<Json> provideJsonProvider;

    private Provider<HttpClient> provideHttpClientProvider;

    private Provider<DayCycleRepository> dayCycleRepositoryProvider;

    private Provider<WallpaperApplyService> wallpaperApplyServiceProvider;

    private Provider<PixoraDatabase> provideDatabaseProvider;

    private Provider<FavoriteDao> provideFavoriteDaoProvider;

    private Provider<FavoriteService> favoriteServiceProvider;

    private Provider<LiveWallpaperRepository> liveWallpaperRepositoryProvider;

    private Provider<LiveApplyService> liveApplyServiceProvider;

    private Provider<AdService> adServiceProvider;

    private Provider<CreditDao> provideCreditDaoProvider;

    private Provider<CreditService> creditServiceProvider;

    private Provider<AuthService> authServiceProvider;

    private Provider<RingtoneRepository> ringtoneRepositoryProvider;

    private Provider<RingtonePreviewPlayer> ringtonePreviewPlayerProvider;

    private Provider<StoryRepository> storyRepositoryProvider;

    private Provider<WallpaperRepository> wallpaperRepositoryProvider;

    private Provider<WallpaperStatsService> wallpaperStatsServiceProvider;

    private SingletonCImpl(ApplicationContextModule applicationContextModuleParam) {
      this.applicationContextModule = applicationContextModuleParam;
      initialize(applicationContextModuleParam);

    }

    private HiltWorkerFactory hiltWorkerFactory() {
      return WorkerFactoryModule_ProvideFactoryFactory.provideFactory(ImmutableMap.<String, javax.inject.Provider<WorkerAssistedFactory<? extends ListenableWorker>>>of());
    }

    @SuppressWarnings("unchecked")
    private void initialize(final ApplicationContextModule applicationContextModuleParam) {
      this.auraPlayerServiceProvider = DoubleCheck.provider(new SwitchingProvider<AuraPlayerService>(singletonCImpl, 0));
      this.provideSupabaseClientProvider = DoubleCheck.provider(new SwitchingProvider<SupabaseClient>(singletonCImpl, 2));
      this.auraRepositoryProvider = DoubleCheck.provider(new SwitchingProvider<AuraRepository>(singletonCImpl, 1));
      this.provideJsonProvider = DoubleCheck.provider(new SwitchingProvider<Json>(singletonCImpl, 5));
      this.provideHttpClientProvider = DoubleCheck.provider(new SwitchingProvider<HttpClient>(singletonCImpl, 4));
      this.dayCycleRepositoryProvider = DoubleCheck.provider(new SwitchingProvider<DayCycleRepository>(singletonCImpl, 3));
      this.wallpaperApplyServiceProvider = DoubleCheck.provider(new SwitchingProvider<WallpaperApplyService>(singletonCImpl, 6));
      this.provideDatabaseProvider = DoubleCheck.provider(new SwitchingProvider<PixoraDatabase>(singletonCImpl, 9));
      this.provideFavoriteDaoProvider = DoubleCheck.provider(new SwitchingProvider<FavoriteDao>(singletonCImpl, 8));
      this.favoriteServiceProvider = DoubleCheck.provider(new SwitchingProvider<FavoriteService>(singletonCImpl, 7));
      this.liveWallpaperRepositoryProvider = DoubleCheck.provider(new SwitchingProvider<LiveWallpaperRepository>(singletonCImpl, 10));
      this.liveApplyServiceProvider = DoubleCheck.provider(new SwitchingProvider<LiveApplyService>(singletonCImpl, 11));
      this.adServiceProvider = DoubleCheck.provider(new SwitchingProvider<AdService>(singletonCImpl, 12));
      this.provideCreditDaoProvider = DoubleCheck.provider(new SwitchingProvider<CreditDao>(singletonCImpl, 14));
      this.creditServiceProvider = DoubleCheck.provider(new SwitchingProvider<CreditService>(singletonCImpl, 13));
      this.authServiceProvider = DoubleCheck.provider(new SwitchingProvider<AuthService>(singletonCImpl, 15));
      this.ringtoneRepositoryProvider = DoubleCheck.provider(new SwitchingProvider<RingtoneRepository>(singletonCImpl, 16));
      this.ringtonePreviewPlayerProvider = DoubleCheck.provider(new SwitchingProvider<RingtonePreviewPlayer>(singletonCImpl, 17));
      this.storyRepositoryProvider = DoubleCheck.provider(new SwitchingProvider<StoryRepository>(singletonCImpl, 18));
      this.wallpaperRepositoryProvider = DoubleCheck.provider(new SwitchingProvider<WallpaperRepository>(singletonCImpl, 19));
      this.wallpaperStatsServiceProvider = DoubleCheck.provider(new SwitchingProvider<WallpaperStatsService>(singletonCImpl, 20));
    }

    @Override
    public void injectPixoraApp(PixoraApp pixoraApp) {
      injectPixoraApp2(pixoraApp);
    }

    @Override
    public Set<Boolean> getDisableFragmentGetContextFix() {
      return ImmutableSet.<Boolean>of();
    }

    @Override
    public ActivityRetainedComponentBuilder retainedComponentBuilder() {
      return new ActivityRetainedCBuilder(singletonCImpl);
    }

    @Override
    public ServiceComponentBuilder serviceComponentBuilder() {
      return new ServiceCBuilder(singletonCImpl);
    }

    @CanIgnoreReturnValue
    private PixoraApp injectPixoraApp2(PixoraApp instance) {
      PixoraApp_MembersInjector.injectWorkerFactory(instance, hiltWorkerFactory());
      return instance;
    }

    private static final class SwitchingProvider<T> implements Provider<T> {
      private final SingletonCImpl singletonCImpl;

      private final int id;

      SwitchingProvider(SingletonCImpl singletonCImpl, int id) {
        this.singletonCImpl = singletonCImpl;
        this.id = id;
      }

      @SuppressWarnings("unchecked")
      @Override
      public T get() {
        switch (id) {
          case 0: // com.orbix.pixora.data.aura.AuraPlayerService 
          return (T) new AuraPlayerService(ApplicationContextModule_ProvideContextFactory.provideContext(singletonCImpl.applicationContextModule));

          case 1: // com.orbix.pixora.data.repos.AuraRepository 
          return (T) new AuraRepository(singletonCImpl.provideSupabaseClientProvider.get());

          case 2: // io.github.jan.supabase.SupabaseClient 
          return (T) SupabaseModule_ProvideSupabaseClientFactory.provideSupabaseClient();

          case 3: // com.orbix.pixora.data.repos.DayCycleRepository 
          return (T) new DayCycleRepository(singletonCImpl.provideHttpClientProvider.get());

          case 4: // io.ktor.client.HttpClient 
          return (T) HttpModule_ProvideHttpClientFactory.provideHttpClient(singletonCImpl.provideJsonProvider.get());

          case 5: // kotlinx.serialization.json.Json 
          return (T) HttpModule_ProvideJsonFactory.provideJson();

          case 6: // com.orbix.pixora.data.wallpaper.WallpaperApplyService 
          return (T) new WallpaperApplyService(ApplicationContextModule_ProvideContextFactory.provideContext(singletonCImpl.applicationContextModule));

          case 7: // com.orbix.pixora.data.favorites.FavoriteService 
          return (T) new FavoriteService(singletonCImpl.provideFavoriteDaoProvider.get());

          case 8: // com.orbix.pixora.data.db.FavoriteDao 
          return (T) DatabaseModule_ProvideFavoriteDaoFactory.provideFavoriteDao(singletonCImpl.provideDatabaseProvider.get());

          case 9: // com.orbix.pixora.data.db.PixoraDatabase 
          return (T) DatabaseModule_ProvideDatabaseFactory.provideDatabase(ApplicationContextModule_ProvideContextFactory.provideContext(singletonCImpl.applicationContextModule));

          case 10: // com.orbix.pixora.data.repos.LiveWallpaperRepository 
          return (T) new LiveWallpaperRepository(singletonCImpl.provideHttpClientProvider.get());

          case 11: // com.orbix.pixora.data.wallpaper.LiveApplyService 
          return (T) new LiveApplyService(ApplicationContextModule_ProvideContextFactory.provideContext(singletonCImpl.applicationContextModule));

          case 12: // com.orbix.pixora.data.ads.AdService 
          return (T) new AdService(ApplicationContextModule_ProvideContextFactory.provideContext(singletonCImpl.applicationContextModule));

          case 13: // com.orbix.pixora.data.credits.CreditService 
          return (T) new CreditService(singletonCImpl.provideCreditDaoProvider.get());

          case 14: // com.orbix.pixora.data.db.CreditDao 
          return (T) DatabaseModule_ProvideCreditDaoFactory.provideCreditDao(singletonCImpl.provideDatabaseProvider.get());

          case 15: // com.orbix.pixora.data.auth.AuthService 
          return (T) new AuthService(ApplicationContextModule_ProvideContextFactory.provideContext(singletonCImpl.applicationContextModule));

          case 16: // com.orbix.pixora.data.repos.RingtoneRepository 
          return (T) new RingtoneRepository(singletonCImpl.provideHttpClientProvider.get());

          case 17: // com.orbix.pixora.data.ringtones.RingtonePreviewPlayer 
          return (T) new RingtonePreviewPlayer(ApplicationContextModule_ProvideContextFactory.provideContext(singletonCImpl.applicationContextModule));

          case 18: // com.orbix.pixora.data.repos.StoryRepository 
          return (T) new StoryRepository(singletonCImpl.provideHttpClientProvider.get());

          case 19: // com.orbix.pixora.data.repos.WallpaperRepository 
          return (T) new WallpaperRepository(singletonCImpl.provideSupabaseClientProvider.get());

          case 20: // com.orbix.pixora.data.stats.WallpaperStatsService 
          return (T) new WallpaperStatsService(singletonCImpl.provideSupabaseClientProvider.get());

          default: throw new AssertionError(id);
        }
      }
    }
  }
}
