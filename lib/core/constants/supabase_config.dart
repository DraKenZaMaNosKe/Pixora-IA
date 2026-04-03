class SupabaseConfig {
  SupabaseConfig._();

  static const String projectUrl = 'https://vzuwvsmlyigjtsearxym.supabase.co';
  static const String anonKey =
      'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InZ6dXd2c21seWlnanRzZWFyeHltIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NTg2NDg3MDksImV4cCI6MjA3NDIyNDcwOX0.Fqum-r8H3erP3fLUvzQlLtWivlrp3smAebvI0uDA5uE';
  static const String storageBase =
      '$projectUrl/storage/v1/object/public';
  static const String imagesBucket = 'wallpaper-images';
  static const String modelsBucket = 'wallpaper-models';
  static const String catalogFile = 'dynamic_catalog.json';

  static String imageUrl(String filename) =>
      '$storageBase/$imagesBucket/$filename';

  static String catalogUrl() =>
      '$storageBase/$imagesBucket/$catalogFile';
}
