plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

val keystorePropertiesFile = rootProject.file("key.properties")
val keystoreProperties = if (keystorePropertiesFile.exists()) {
    keystorePropertiesFile.readLines(Charsets.UTF_8).mapNotNull { line ->
        val separator = line.indexOf('=')
        if (separator > 0) {
            line.substring(0, separator) to line.substring(separator + 1)
        } else {
            null
        }
    }.toMap()
} else {
    emptyMap()
}

android {
    namespace = "com.sprecious.wakewall"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        applicationId = "com.sprecious.wakewall"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    signingConfigs {
        create("release") {
            keyAlias = keystoreProperties.getValue("keyAlias")
            keyPassword = keystoreProperties.getValue("keyPassword")
            storeFile = file(keystoreProperties.getValue("storeFile"))
            storePassword = keystoreProperties.getValue("storePassword")
        }
    }

    buildTypes {
        release {
            signingConfig = signingConfigs.getByName("release")
        }
    }

    lint {
        // Flutter regenerates local.properties with Windows paths that Android Lint misreads.
        disable += "PropertyEscape"
        // Flutter still provides a v21 launch drawable even though WakeWall's minimum SDK is newer.
        disable += "ObsoleteSdkInt"
    }

    testOptions {
        unitTests.isIncludeAndroidResources = true
    }
}

dependencies {
    testImplementation("junit:junit:4.13.2")
    testImplementation("org.robolectric:robolectric:4.16")
    testImplementation("org.mockito:mockito-core:5.23.0")
}

// Flutter's copied assets are also inputs to AGP's resource-backed unit tests.
tasks.matching { it.name == "packageDebugUnitTestForUnitTest" }.configureEach {
    dependsOn("copyFlutterAssetsDebug")
}

kotlin {
    compilerOptions {
        jvmTarget = org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17
    }
}

flutter {
    source = "../.."
}
