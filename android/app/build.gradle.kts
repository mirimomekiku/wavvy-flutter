plugins {
    id("com.android.application")
    id("kotlin-android")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

android {
    namespace = "com.mirimomekiku.wavvy"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    kotlinOptions {
        jvmTarget = JavaVersion.VERSION_17.toString()
    }

    defaultConfig {
        // TODO: Specify your own unique Application ID (https://developer.android.com/studio/build/application-id.html).
        applicationId = "com.mirimomekiku.wavvy"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    // Two builds of the same app:
    //  * play: no downloader, safe for the Play Store.
    //  * full: adds the yt-dlp downloader (runs downloaded code, so sideload
    //    only). Build with `flutter run --flavor full` / `--flavor play`.
    flavorDimensions += "distribution"
    productFlavors {
        create("play") {
            dimension = "distribution"
        }
        create("full") {
            dimension = "distribution"
            versionNameSuffix = "-full"
            // The bundled Python is arm64 only, to keep the app small.
            ndk {
                abiFilters += listOf("arm64-v8a")
            }
        }
    }

    buildTypes {
        release {
            // TODO: Add your own signing config for the release build.
            // Signing with the debug keys for now, so `flutter run --release` works.
            signingConfig = signingConfigs.getByName("debug")
        }
    }
}

// The downloader runs Python as a separate process, which needs its native
// libraries extracted to disk. Only the full flavor pays that install size.
androidComponents {
    onVariants(selector().withFlavor("distribution" to "full")) { variant ->
        variant.packaging.jniLibs.useLegacyPackaging.set(true)
        // arm64 only: the Python library also ships armeabi-v7a, x86 and x86_64
        // builds, which the ndk filter above does not remove from the APK.
        variant.packaging.jniLibs.excludes.addAll(
            listOf("**/armeabi-v7a/**", "**/x86/**", "**/x86_64/**"),
        )
    }
}

dependencies {
    // yt-dlp for Android: an embedded Python plus yt-dlp, which the app updates
    // itself from yt-dlp's releases. Not in the Play flavor.
    "fullImplementation"("io.github.junkfood02.youtubedl-android:library:0.18.1")
}

flutter {
    source = "../.."
}
