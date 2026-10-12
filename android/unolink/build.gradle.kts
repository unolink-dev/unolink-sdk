plugins {
    alias(libs.plugins.android.library)
    alias(libs.plugins.kotlin.android)
}

android {
    namespace = "dev.unolink"
    compileSdk = 36

    defaultConfig {
        minSdk = 23
        consumerProguardFiles("consumer-rules.pro")
    }

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_1_8
        targetCompatibility = JavaVersion.VERSION_1_8
    }

    testOptions {
        unitTests.isReturnDefaultValues = true
    }
}

kotlin {
    explicitApi()
    compilerOptions {
        jvmTarget.set(org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_1_8)
    }
}

dependencies {
    implementation(libs.installreferrer)
    implementation(libs.lifecycle.process)

    testImplementation(libs.junit)
    // Real org.json on the JVM (Android's copy is stubbed in unit tests).
    testImplementation(libs.orgjson)
    testImplementation(libs.jsonschema)
}

// The contract (schemas, canned responses) lives at the repo root, shared with every SDK.
tasks.withType<Test>().configureEach {
    systemProperty("unolink.contractDir", rootProject.projectDir.resolve("../contract").canonicalPath)
}
