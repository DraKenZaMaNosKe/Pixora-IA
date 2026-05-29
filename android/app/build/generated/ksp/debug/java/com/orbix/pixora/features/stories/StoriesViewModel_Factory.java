package com.orbix.pixora.features.stories;

import com.orbix.pixora.data.repos.StoryRepository;
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
public final class StoriesViewModel_Factory implements Factory<StoriesViewModel> {
  private final Provider<StoryRepository> repoProvider;

  public StoriesViewModel_Factory(Provider<StoryRepository> repoProvider) {
    this.repoProvider = repoProvider;
  }

  @Override
  public StoriesViewModel get() {
    return newInstance(repoProvider.get());
  }

  public static StoriesViewModel_Factory create(Provider<StoryRepository> repoProvider) {
    return new StoriesViewModel_Factory(repoProvider);
  }

  public static StoriesViewModel newInstance(StoryRepository repo) {
    return new StoriesViewModel(repo);
  }
}
