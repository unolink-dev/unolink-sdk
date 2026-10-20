package dev.unolink

import dev.unolink.internal.AndroidDevice
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

/** Builds the developer installs themselves (adb, Android Studio) are test devices; any store install is real. */
class TestDeviceTest {
    @Test
    fun self_installed_builds_are_test_devices_store_installs_are_not() {
        assertTrue(AndroidDevice.isSelfInstalled(null))
        assertTrue(AndroidDevice.isSelfInstalled("com.android.shell"))
        assertFalse(AndroidDevice.isSelfInstalled("com.android.vending"))
        assertFalse(AndroidDevice.isSelfInstalled("com.sec.android.app.samsungapps"))
        assertFalse(AndroidDevice.isSelfInstalled("com.google.android.packageinstaller"))
    }
}
