package com.orbix.pixora.data.ads;

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
public final class AdService_Factory implements Factory<AdService> {
  private final Provider<Context> contextProvider;

  public AdService_Factory(Provider<Context> contextProvider) {
    this.contextProvider = contextProvider;
  }

  @Override
  public AdService get() {
    return newInstance(contextProvider.get());
  }

  public static AdService_Factory create(Provider<Context> contextProvider) {
    return new AdService_Factory(contextProvider);
  }

  public static AdService newInstance(Context context) {
    return new AdService(context);
  }
}
