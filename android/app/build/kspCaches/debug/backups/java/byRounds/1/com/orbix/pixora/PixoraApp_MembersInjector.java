package com.orbix.pixora;

import androidx.hilt.work.HiltWorkerFactory;
import dagger.MembersInjector;
import dagger.internal.DaggerGenerated;
import dagger.internal.InjectedFieldSignature;
import dagger.internal.QualifierMetadata;
import javax.annotation.processing.Generated;
import javax.inject.Provider;

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
public final class PixoraApp_MembersInjector implements MembersInjector<PixoraApp> {
  private final Provider<HiltWorkerFactory> workerFactoryProvider;

  public PixoraApp_MembersInjector(Provider<HiltWorkerFactory> workerFactoryProvider) {
    this.workerFactoryProvider = workerFactoryProvider;
  }

  public static MembersInjector<PixoraApp> create(
      Provider<HiltWorkerFactory> workerFactoryProvider) {
    return new PixoraApp_MembersInjector(workerFactoryProvider);
  }

  @Override
  public void injectMembers(PixoraApp instance) {
    injectWorkerFactory(instance, workerFactoryProvider.get());
  }

  @InjectedFieldSignature("com.orbix.pixora.PixoraApp.workerFactory")
  public static void injectWorkerFactory(PixoraApp instance, HiltWorkerFactory workerFactory) {
    instance.workerFactory = workerFactory;
  }
}
