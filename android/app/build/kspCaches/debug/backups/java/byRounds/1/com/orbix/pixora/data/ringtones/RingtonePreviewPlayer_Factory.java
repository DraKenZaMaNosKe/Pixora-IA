package com.orbix.pixora.data.ringtones;

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
public final class RingtonePreviewPlayer_Factory implements Factory<RingtonePreviewPlayer> {
  private final Provider<Context> contextProvider;

  public RingtonePreviewPlayer_Factory(Provider<Context> contextProvider) {
    this.contextProvider = contextProvider;
  }

  @Override
  public RingtonePreviewPlayer get() {
    return newInstance(contextProvider.get());
  }

  public static RingtonePreviewPlayer_Factory create(Provider<Context> contextProvider) {
    return new RingtonePreviewPlayer_Factory(contextProvider);
  }

  public static RingtonePreviewPlayer newInstance(Context context) {
    return new RingtonePreviewPlayer(context);
  }
}
