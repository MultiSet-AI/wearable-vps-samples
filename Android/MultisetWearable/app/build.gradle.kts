/*
Copyright (c) 2026 MultiSet AI. All rights reserved.
Licensed under the MultiSet License. You may not use this file except in compliance with the License. and you can't re-distribute this file without a prior notice
For license details, visit www.multiset.ai.
Redistribution in source or binary forms must retain this notice.
*/

import java.util.Properties

plugins {
  alias(libs.plugins.android.application)
  alias(libs.plugins.jetbrains.kotlin.android)
  alias(libs.plugins.compose.compiler)
}

// ============================================================
// MULTISET SDK CONFIGURATION
// Configure your credentials and map in: multiset.properties (project root, gitignored)
// Get credentials at: https://developer.multiset.ai/credentials
// ============================================================
val multisetProperties = Properties().apply {
  val propsFile = rootProject.file("multiset.properties")
  if (propsFile.exists()) {
    propsFile.inputStream().use { load(it) }
  }
}

fun getMultisetProperty(key: String, default: String = ""): String =
    multisetProperties.getProperty(key, default)

android {
  namespace = "com.multiset.wearable.vps"
  compileSdk = 35

  buildFeatures { buildConfig = true }

  defaultConfig {
    applicationId = "com.multiset.wearable.vps"
    minSdk = 31
    targetSdk = 34
    versionCode = 1
    versionName = "1.0"

    testInstrumentationRunner = "androidx.test.runner.AndroidJUnitRunner"
    vectorDrawables { useSupportLibrary = true }

    // MultiSet SDK Configuration (loaded from multiset.properties)
    buildConfigField(
      "String",
      "MULTISET_CLIENT_ID",
      "\"${getMultisetProperty("MULTISET_CLIENT_ID")}\""
    )
    buildConfigField(
      "String",
      "MULTISET_CLIENT_SECRET",
      "\"${getMultisetProperty("MULTISET_CLIENT_SECRET")}\""
    )
    buildConfigField(
      "String",
      "MULTISET_MAP_CODE",
      "\"${getMultisetProperty("MULTISET_MAP_CODE")}\""
    )
    buildConfigField(
      "String",
      "MULTISET_MAP_SET_CODE",
      "\"${getMultisetProperty("MULTISET_MAP_SET_CODE")}\""
    )
  }

  buildTypes {
    debug {
      // Enable verbose logging in debug builds
      buildConfigField("Boolean", "ENABLE_VERBOSE_LOGGING", "true")
    }
    release {
      isMinifyEnabled = false
      proguardFiles(getDefaultProguardFile("proguard-android-optimize.txt"), "proguard-rules.pro")
      signingConfig = signingConfigs.getByName("debug")
      // Disable verbose logging in release builds
      buildConfigField("Boolean", "ENABLE_VERBOSE_LOGGING", "false")
    }
  }
  compileOptions {
    sourceCompatibility = JavaVersion.VERSION_1_8
    targetCompatibility = JavaVersion.VERSION_1_8
  }
  kotlinOptions { jvmTarget = "1.8" }
  buildFeatures { compose = true }
  composeOptions { kotlinCompilerExtensionVersion = "1.5.1" }
  packaging { resources { excludes += "/META-INF/{AL2.0,LGPL2.1}" } }
  signingConfigs {
    getByName("debug") {
      storeFile = file("sample.keystore")
      storePassword = "sample"
      keyAlias = "sample"
      keyPassword = "sample"
    }
  }
}

dependencies {
  implementation(libs.androidx.activity.compose)
  implementation(platform(libs.androidx.compose.bom))
  implementation(libs.androidx.exifinterface)
  implementation(libs.androidx.lifecycle.runtime.compose)
  implementation(libs.androidx.lifecycle.viewmodel.compose)
  implementation(libs.androidx.material.icons.extended)
  implementation(libs.androidx.material3)
  implementation(libs.kotlinx.collections.immutable)
  implementation(libs.mwdat.core)
  implementation(libs.mwdat.camera)
  implementation(libs.mwdat.mockdevice)
  implementation(libs.okhttp)
  // Media session for capturing glasses button events
  implementation("androidx.media:media:1.7.0")
  androidTestImplementation(libs.androidx.ui.test.junit4)
  androidTestImplementation(libs.androidx.test.uiautomator)
  androidTestImplementation(libs.androidx.test.rules)
}
