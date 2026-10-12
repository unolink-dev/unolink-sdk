package dev.unolink.internal

import java.io.IOException

/** An HTTP answer. Network failures are thrown as [IOException] instead. */
internal class HttpResponse(val status: Int, val body: String?)

internal interface Transport {
    @Throws(IOException::class)
    fun send(method: String, path: String, body: String?): HttpResponse
}

/** Small persistent key/value store for SDK state (install ID, flags). Never backed up to the cloud. */
internal interface KeyValueStore {
    fun getString(key: String): String?
    fun putString(key: String, value: String?)
    fun getBoolean(key: String): Boolean = getString(key) == "true"
    fun putBoolean(key: String, value: Boolean) = putString(key, if (value) "true" else null)
}

/** Where queued events survive app restarts (one JSON object per line). */
internal interface QueueStore {
    fun load(): List<String>
    fun save(lines: List<String>)
}

/** The SDK's single worker thread. All engine state is touched only from it. */
internal interface Scheduler {
    fun execute(task: () -> Unit)
    fun schedule(delayMillis: Long, task: () -> Unit)
}

internal interface Clock {
    fun now(): Long
}

internal interface Logger {
    fun error(message: String)
    fun warn(message: String)
    fun info(message: String)
    fun debug(message: String)
}

/** Facts about the app and device that go into /v1/install. Nothing here identifies a person or the device. */
internal class DeviceInfo(
    val platform: String,
    val sdkName: String,
    val sdkVersion: String,
    val osVersion: String?,
    val appVersion: String?,
    val deviceClass: String?,
    val locale: String?,
    val isDebug: Boolean,
)
