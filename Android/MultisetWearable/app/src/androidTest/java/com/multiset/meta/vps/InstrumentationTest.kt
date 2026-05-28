/*
Copyright (c) 2026 MultiSet AI. All rights reserved.
Licensed under the MultiSet License. You may not use this file except in compliance with the License. and you can't re-distribute this file without a prior notice
For license details, visit www.multiset.ai.
Redistribution in source or binary forms must retain this notice.
*/

// InstrumentationTest - DAT Integration Testing Suite
//
// This instrumentation test suite demonstrates testing for DAT applications using MockDeviceKit and
// UI automation, adapted to MetaCameraAccess's localization-first flow.
//
// Test Scenarios Covered:
// 1. App launch with no devices (HomeScreen)
// 2. App behavior with a mock device paired (LocalizationScreen shown when registered)
//
// Note: MetaCameraAccess shows LocalizationScreen (not the upstream NonStreamScreen) once a device
// is registered, and the live-stream screen is not part of the active flow, so the upstream
// streaming-capture test is intentionally omitted here.

package com.multiset.wearable.vps

import android.content.Context
import android.util.Log
import androidx.compose.ui.test.ExperimentalTestApi
import androidx.compose.ui.test.hasText
import androidx.compose.ui.test.junit4.createAndroidComposeRule
import androidx.compose.ui.test.onNodeWithText
import androidx.compose.ui.test.performClick
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.filters.LargeTest
import androidx.test.platform.app.InstrumentationRegistry
import com.meta.wearable.dat.mockdevice.MockDeviceKit
import java.io.IOException
import org.junit.After
import org.junit.Before
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith

@OptIn(ExperimentalTestApi::class)
@RunWith(AndroidJUnit4::class)
@LargeTest
class InstrumentationTest {

  companion object {
    private const val TAG = "InstrumentationTest"
  }

  @get:Rule val composeTestRule = createAndroidComposeRule<com.multiset.wearable.vps.MainActivity>()
  val targetContext: Context = InstrumentationRegistry.getInstrumentation().targetContext

  @Before
  fun setup() {
    grantPermissions()
    // Ensure a clean, unregistered baseline — registration is a process singleton that
    // can bleed across tests sharing the app process.
    MockDeviceKit.getInstance(targetContext).disable()
  }

  @After
  fun tearDown() {
    MockDeviceKit.getInstance(targetContext).disable()
  }

  @Test
  fun showsHomeScreenOnLaunch() {
    // HomeScreen renders the "Multiset Wearable VPS" title once the splash screen completes.
    composeTestRule.waitUntilExactlyOneExists(
        hasText("Multiset Wearable VPS"),
        timeoutMillis = 10000,
    )
  }

  @Test
  fun showsFeatureMenuWhenMockPaired() {
    val mockDeviceKit = MockDeviceKit.getInstance(targetContext)
    mockDeviceKit.enable()
    mockDeviceKit.pairRaybanMeta().powerOn()

    // Once a device is registered, MetaCameraAccess shows the feature-selection menu.
    composeTestRule.waitUntilExactlyOneExists(
        hasText("MultiSet Wearable VPS"),
        timeoutMillis = 10000,
    )
  }

  @Test
  fun opensLocalizationLanding() {
    // Localization requires VPS configuration; set a map code so the card is enabled.
    _root_ide_package_.com.multiset.wearable.vps.localization.SDKConfig.updateMapCodes("TEST_MAP_CODE", "")

    val mockDeviceKit = MockDeviceKit.getInstance(targetContext)
    mockDeviceKit.enable()
    mockDeviceKit.pairRaybanMeta().powerOn()

    composeTestRule.waitUntilExactlyOneExists(hasText("Localization Demo"), timeoutMillis = 10000)
    composeTestRule.onNodeWithText("Localization Demo").performClick()

    // The Localization Demo landing page renders its "Open Localization" button.
    composeTestRule.waitUntilExactlyOneExists(hasText("Open Localization"), timeoutMillis = 5000)
  }

  @Test
  fun opensRecordVideoLanding() {
    val mockDeviceKit = MockDeviceKit.getInstance(targetContext)
    mockDeviceKit.enable()
    mockDeviceKit.pairRaybanMeta().powerOn()

    composeTestRule.waitUntilExactlyOneExists(hasText("Record Video Stream"), timeoutMillis = 10000)
    composeTestRule.onNodeWithText("Record Video Stream").performClick()

    // The Record Video Stream landing page renders its "Start Camera Stream" button.
    composeTestRule.waitUntilExactlyOneExists(hasText("Start Camera Stream"), timeoutMillis = 5000)
  }

  private fun grantPermissions() {
    grantPermission("android.permission.BLUETOOTH")
    grantPermission("android.permission.BLUETOOTH_CONNECT")
    grantPermission("android.permission.CAMERA")
    grantPermission("android.permission.INTERNET")
  }

  private fun grantPermission(permission: String) {
    val packageName = targetContext.packageName
    try {
      val instrumentation = InstrumentationRegistry.getInstrumentation()
      instrumentation.uiAutomation.executeShellCommand("pm grant $packageName $permission")
      Log.d(TAG, "Granted permission: $permission")
    } catch (e: IOException) {
      Log.e(TAG, "Failed to grant permission", e)
    }
  }
}
