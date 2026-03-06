import org.gradle.api.file.Directory
import org.gradle.api.tasks.Delete

// ✅ AGP 8+: extensões DSL
import com.android.build.api.dsl.ApplicationExtension
import com.android.build.api.dsl.LibraryExtension

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

/**
 * ✅ Opção A (correta): habilita BuildConfig em TODOS os módulos Android
 * (app + libraries/plugins, incluindo :firebase_installations)
 *
 * IMPORTANTÍSSIMO: NÃO usar afterEvaluate aqui, porque o erro ocorre durante a configuração.
 */
subprojects {
    plugins.withId("com.android.application") {
        extensions.configure<ApplicationExtension>("android") {
            buildFeatures {
                buildConfig = true
            }
        }
    }

    plugins.withId("com.android.library") {
        extensions.configure<LibraryExtension>("android") {
            buildFeatures {
                buildConfig = true
            }
        }
    }
}

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}