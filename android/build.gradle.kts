// Aliyun Maven mirrors are opt-in via the `useCnMirror` Gradle property
// (e.g. `useCnMirror=true` in ~/.gradle/gradle.properties for developers
// in China). CI and other builds resolve from google()/mavenCentral()
// directly. The mirrors exist because plugin subprojects (e.g.
// flutter_inappwebview) resolve their buildscript classpath from their own
// build.gradle's google()/mavenCentral(), which 403s on direct
// connections from China — prefixing the same mirrors here fixes that.
val useCnMirror: Boolean =
    (findProperty("useCnMirror") as String?)?.toBoolean() == true

fun RepositoryHandler.addCnMirrors() {
    if (!useCnMirror) return
    maven { url = uri("https://maven.aliyun.com/repository/google") }
    maven { url = uri("https://maven.aliyun.com/repository/central") }
    maven { url = uri("https://maven.aliyun.com/repository/gradle-plugin") }
    maven { url = uri("https://maven.aliyun.com/repository/public") }
}

allprojects {
    buildscript {
        repositories {
            addCnMirrors()
            // With the China mirrors on, dl.google.com is only a fallback
            // that hangs from China (empty responses, long retries). The
            // Aliyun google mirror serves the same artifacts.
            if (!useCnMirror) google()
            mavenCentral()
        }
    }
    repositories {
        addCnMirrors()
        // Same fallback rule as buildscript above.
        if (!useCnMirror) google()
        mavenCentral()
    }
}

val newBuildDir: Directory = rootProject.layout.buildDirectory.dir("../../build").get()
rootProject.layout.buildDirectory.value(newBuildDir)

subprojects {
    val newSubprojectBuildDir: Directory = newBuildDir.dir(project.name)
    project.layout.buildDirectory.value(newSubprojectBuildDir)
}
subprojects {
    project.evaluationDependsOn(":app")
}

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}
