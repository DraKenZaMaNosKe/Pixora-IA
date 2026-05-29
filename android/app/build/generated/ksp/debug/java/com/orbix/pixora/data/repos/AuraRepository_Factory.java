package com.orbix.pixora.data.repos;

import dagger.internal.DaggerGenerated;
import dagger.internal.Factory;
import dagger.internal.QualifierMetadata;
import dagger.internal.ScopeMetadata;
import io.github.jan.supabase.SupabaseClient;
import javax.annotation.processing.Generated;
import javax.inject.Provider;

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
public final class AuraRepository_Factory implements Factory<AuraRepository> {
  private final Provider<SupabaseClient> supabaseProvider;

  public AuraRepository_Factory(Provider<SupabaseClient> supabaseProvider) {
    this.supabaseProvider = supabaseProvider;
  }

  @Override
  public AuraRepository get() {
    return newInstance(supabaseProvider.get());
  }

  public static AuraRepository_Factory create(Provider<SupabaseClient> supabaseProvider) {
    return new AuraRepository_Factory(supabaseProvider);
  }

  public static AuraRepository newInstance(SupabaseClient supabase) {
    return new AuraRepository(supabase);
  }
}
