package com.orbix.pixora.di;

import dagger.internal.DaggerGenerated;
import dagger.internal.Factory;
import dagger.internal.Preconditions;
import dagger.internal.QualifierMetadata;
import dagger.internal.ScopeMetadata;
import io.github.jan.supabase.SupabaseClient;
import javax.annotation.processing.Generated;

@ScopeMetadata("javax.inject.Singleton")
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
public final class SupabaseModule_ProvideSupabaseClientFactory implements Factory<SupabaseClient> {
  @Override
  public SupabaseClient get() {
    return provideSupabaseClient();
  }

  public static SupabaseModule_ProvideSupabaseClientFactory create() {
    return InstanceHolder.INSTANCE;
  }

  public static SupabaseClient provideSupabaseClient() {
    return Preconditions.checkNotNullFromProvides(SupabaseModule.INSTANCE.provideSupabaseClient());
  }

  private static final class InstanceHolder {
    private static final SupabaseModule_ProvideSupabaseClientFactory INSTANCE = new SupabaseModule_ProvideSupabaseClientFactory();
  }
}
