import java.util.Properties

plugins {
    alias(libs.plugins.android.application)
    alias(libs.plugins.kotlin.android)
}

// Your SDK key and base URL go in android/local.properties (never committed):
//   unolink.sampleKey=ulk_…
//   unolink.baseUrl=https://api-uat.unolink.dev
//   unolink.simulateReferrer=unolink_click_id=clk_…&unolink_deep_link=%2Fpromo   (optional, debug builds only)
val local = Properties().apply { rootProject.file("local.properties").takeIf { it.exists() }?.inputStream()?.use(::load) }
fun prop(name: String, default: String = "") = "\"" + (local.getProperty(name) ?: default) + "\""

android {
    namespace = "dev.unolink.sample"
    compileSdk = 36

    defaultConfig {
        applicationId = "dev.unolink.sample"
        minSdk = 23
        targetSdk = 36
        versionCode = 1
        versionName = "0.1.0"
        buildConfigField("String", "UNOLINK_KEY", prop("unolink.sampleKey"))
        buildConfigField("String", "UNOLINK_BASE_URL", prop("unolink.baseUrl", "https://api-uat.unolink.dev"))
        buildConfigField("String", "SIMULATE_REFERRER", prop("unolink.simulateReferrer"))
    }

    buildFeatures { buildConfig = true }

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }
}

kotlin { compilerOptions { jvmTarget.set(org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17) } }

dependencies {
    implementation(project(":unolink"))
}
