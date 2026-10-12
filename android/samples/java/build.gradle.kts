plugins {
    alias(libs.plugins.android.application)
}

android {
    namespace = "dev.unolink.samplejava"
    compileSdk = 36

    defaultConfig {
        applicationId = "dev.unolink.samplejava"
        minSdk = 23
        targetSdk = 36
        versionCode = 1
        versionName = "0.1.0"
    }

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }
}

dependencies {
    implementation(project(":unolink"))
}
