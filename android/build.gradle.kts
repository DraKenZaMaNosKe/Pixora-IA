// Root build.gradle.kts — empty by design.
// All plugins are declared in settings.gradle.kts with `apply false` and
// applied per-module. Module-specific config lives in app/build.gradle.kts.
//
// `clean` task removes the build outputs at the root level.
tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}
