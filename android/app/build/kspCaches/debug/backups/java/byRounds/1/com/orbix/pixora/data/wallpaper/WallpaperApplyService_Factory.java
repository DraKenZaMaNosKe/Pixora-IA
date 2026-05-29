package com.orbix.pixora.data.wallpaper;

import android.content.Context;
import dagger.internal.DaggerGenerated;
import dagger.internal.Factory;
import dagger.internal.QualifierMetadata;
import dagger.internal.ScopeMetadata;
import javax.annotation.processing.Generated;
import javax.inject.Provider;

@ScopeMetadata("javax.inject.Singleton")
@QualifierMetadata("dagger.hilt.android.qualifiers.ApplicationContext")
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
public final class WallpaperApplyService_Factory implements Factory<WallpaperApplyService> {
  private final Provider<Context> contextProvider;

  public WallpaperApplyService_Factory(Provider<Context> contextProvider) {
    this.contextProvider = contextProvider;
  }

  @Override
  public WallpaperApplyService get() {
    return newInstance(contextProvider.get());
  }

  public static WallpaperApplyService_Factory create(Provider<Context> contextProvider) {
    return new WallpaperApplyService_Factory(contextProvider);
  }

  public static WallpaperApplyService newInstance(Context context) {
    return new WallpaperApplyService(context);
  }
}
