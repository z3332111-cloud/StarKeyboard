plugins {
    id("com.android.application")
    id("org.jetbrains.kotlin.android")
}

// 雲端打包時給版本號和簽名金鑰；自己在電腦上編譯就用測試金鑰
val buildNumber = (System.getenv("BUILD_NUMBER") ?: "1").toInt()
val keystorePath: String? = System.getenv("KEYSTORE_PATH")

android {
    namespace = "com.startown.starkeyboard"
    compileSdk = 34

    defaultConfig {
        applicationId = "com.startown.starkeyboard"
        minSdk = 26
        targetSdk = 34
        versionCode = buildNumber
        versionName = rootProject.projectDir.parentFile.resolve("VERSION").readText().trim()
        // 只放手機用的 CPU 版本，安裝檔小很多（Google 手寫、翻譯的程式庫每種 CPU 各一份）
        ndk {
            abiFilters += listOf("arm64-v8a", "armeabi-v7a")
        }
    }

    signingConfigs {
        create("release") {
            if (keystorePath != null) {
                storeFile = file(keystorePath)
                storePassword = System.getenv("KEYSTORE_PASSWORD")
                keyAlias = "starkeyboard"
                keyPassword = System.getenv("KEYSTORE_PASSWORD")
            }
        }
    }

    buildTypes {
        release {
            isMinifyEnabled = false
            signingConfig = if (keystorePath != null) signingConfigs.getByName("release") else signingConfigs.getByName("debug")
        }
    }

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }
    kotlinOptions {
        jvmTarget = "17"
    }
    testOptions {
        unitTests.isReturnDefaultValues = true
    }
}

dependencies {
    implementation("androidx.core:core-ktx:1.13.1")
    implementation("com.google.mlkit:digital-ink-recognition:18.1.0")
    implementation("com.google.mlkit:translate:17.0.3")
    testImplementation("junit:junit:4.13.2")
    testImplementation("org.json:json:20231013")
}
