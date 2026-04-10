allprojects {
    repositories {
        google()
        mavenCentral()
    }
}

val newBuildDir: Directory =
    rootProject.layout.buildDirectory
        .dir("../../build")
        .get()
rootProject.layout.buildDirectory.value(newBuildDir)

subprojects {
    val newSubprojectBuildDir: Directory = newBuildDir.dir(project.name)
    project.layout.buildDirectory.value(newSubprojectBuildDir)
}
subprojects {
    project.evaluationDependsOn(":app")
}

// Force all subprojects (including flutter_midi_pro) to use the NDK version
// that is actually installed, regardless of what the plugin declares.
subprojects {
    plugins.withId("com.android.library") {
        the<com.android.build.gradle.LibraryExtension>().ndkVersion = "28.2.13676358"
    }
    plugins.withId("com.android.application") {
        the<com.android.build.gradle.AppExtension>().ndkVersion = "28.2.13676358"
    }
}

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}
