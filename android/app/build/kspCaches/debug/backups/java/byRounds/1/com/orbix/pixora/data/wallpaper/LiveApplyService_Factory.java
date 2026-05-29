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
public final class LiveApplyService_Factory implements Factory<LiveApplyService> {
  private final Provider<Context> contextProvider;

  public LiveApplyService_Factory(Provider<Context> contextProvider) {
    this.contextProvider = contextProvider;
  }

  @Override
  public LiveApplyService get() {
    return newInstance(contextProvider.get());
  }

  public static LiveApplyService_Factory create(Provider<Context> contextProvider) {
    return new LiveApplyService_Factory(contextProvider);
  }

  public static LiveApplyService newInstance(Context context) {
    return new LiveApplyService(context);
  }
}
