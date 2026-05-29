package com.orbix.pixora.data.aura;

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
public final class AuraPlayerService_Factory implements Factory<AuraPlayerService> {
  private final Provider<Context> contextProvider;

  public AuraPlayerService_Factory(Provider<Context> contextProvider) {
    this.contextProvider = contextProvider;
  }

  @Override
  public AuraPlayerService get() {
    return newInstance(contextProvider.get());
  }

  public static AuraPlayerService_Factory create(Provider<Context> contextProvider) {
    return new AuraPlayerService_Factory(contextProvider);
  }

  public static AuraPlayerService newInstance(Context context) {
    return new AuraPlayerService(context);
  }
}
