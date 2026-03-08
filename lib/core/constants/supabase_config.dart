class SupabaseConfig {
  SupabaseConfig._();

  static const String projectUrl =
      'https://vzuwvsmlyigjtsearxym.supabase.co';
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
