package dev.unolink.internal

import android.content.Context
import android.content.pm.ApplicationInfo
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.util.Log
import com.android.installreferrer.api.InstallReferrerClient
import com.android.installreferrer.api.InstallReferrerStateListener
import dev.unolink.LogLevel
import java.io.File
import java.io.IOException
import java.net.HttpURLConnection
import java.net.URL
import java.util.Locale
import java.util.Properties
import java.util.concurrent.Executors
import java.util.concurrent.ScheduledExecutorService
import java.util.concurrent.TimeUnit

/**
 * SDK state in the app's no-backup directory: Android's cloud backup never copies it to another device, so a
 * restored or new phone gets a new install ID, like a reinstall.
 */
internal class FileKeyValueStore(dir: File) : KeyValueStore {
    private val file = File(dir, "unolink-state.properties")
    private val props = Properties().apply { if (file.exists()) runCatching { file.inputStream().use(::load) } }

    override fun getString(key: String): String? = props.getProperty(key)

    override fun putString(key: String, value: String?) {
        if (value == null) props.remove(key) else props.setProperty(key, value)
        runCatching { atomicWrite(file) { out -> props.store(out, null) } }
    }
}

internal class FileQueueStore(dir: File) : QueueStore {
    private val file = File(dir, "unolink-queue.jsonl")

    override fun load(): List<String> = runCatching { if (file.exists()) file.readLines().filter { it.isNotBlank() } else emptyList() }
        .getOrDefault(emptyList())

    override fun save(lines: List<String>) {
        runCatching { atomicWrite(file) { out -> out.write(lines.joinToString("\n").toByteArray()) } }
    }
}

private fun atomicWrite(target: File, write: (java.io.OutputStream) -> Unit) {
    val tmp = File(target.parentFile, target.name + ".tmp")
    tmp.outputStream().use(write)
    if (!tmp.renameTo(target)) {
        target.delete()
        tmp.renameTo(target)
    }
}

internal class HttpTransport(private val baseUrl: String, private val apiKey: String, private val userAgent: String) : Transport {
    override fun send(method: String, path: String, body: String?): HttpResponse {
        val connection = URL(baseUrl.trimEnd('/') + path).openConnection() as HttpURLConnection
        try {
            connection.requestMethod = method
            connection.connectTimeout = 10_000
            connection.readTimeout = 15_000
            connection.useCaches = false
            connection.setRequestProperty("X-Unolink-Key", apiKey)
            connection.setRequestProperty("User-Agent", userAgent)
            connection.setRequestProperty("Accept", "application/json")
            if (body != null) {
                connection.doOutput = true
                connection.setRequestProperty("Content-Type", "application/json; charset=utf-8")
                connection.outputStream.use { it.write(body.toByteArray(Charsets.UTF_8)) }
            }
            val status = connection.responseCode
            val stream = if (status >= 400) connection.errorStream else connection.inputStream
            return HttpResponse(status, stream?.bufferedReader(Charsets.UTF_8)?.use { it.readText() })
        } catch (e: IOException) {
            throw e
        } finally {
            connection.disconnect()
        }
    }
}

internal class ExecutorScheduler : Scheduler {
    private val executor: ScheduledExecutorService = Executors.newSingleThreadScheduledExecutor { r ->
        Thread(r, "unolink").apply { isDaemon = true }
    }

    override fun execute(task: () -> Unit) {
        executor.execute { runCatching(task).onFailure { Log.e("Unolink", "Internal error", it) } }
    }

    override fun schedule(delayMillis: Long, task: () -> Unit) {
        executor.schedule({ runCatching(task).onFailure { Log.e("Unolink", "Internal error", it) } }, delayMillis, TimeUnit.MILLISECONDS)
    }
}

internal class LogcatLogger(private val level: LogLevel) : Logger {
    override fun error(message: String) { if (level >= LogLevel.ERROR) Log.e(TAG, message) }
    override fun warn(message: String) { if (level >= LogLevel.WARN) Log.w(TAG, message) }
    override fun info(message: String) { if (level >= LogLevel.INFO) Log.i(TAG, message) }
    override fun debug(message: String) { if (level >= LogLevel.DEBUG) Log.d(TAG, message) }

    private companion object { const val TAG = "Unolink" }
}

internal object SystemClock : Clock {
    override fun now(): Long = System.currentTimeMillis()
}

internal object AndroidDevice {
    fun info(context: Context, sdkName: String, sdkVersion: String, debug: Boolean?): DeviceInfo {
        val appVersion = runCatching {
            @Suppress("DEPRECATION")
            context.packageManager.getPackageInfo(context.packageName, 0).versionName
        }.getOrNull()
        val tablet = context.resources.configuration.smallestScreenWidthDp >= 600
        val debuggable = context.applicationInfo.flags and ApplicationInfo.FLAG_DEBUGGABLE != 0
        return DeviceInfo(
            platform = "android",
            sdkName = sdkName,
            sdkVersion = sdkVersion,
            osVersion = Build.VERSION.RELEASE,
            appVersion = appVersion,
            deviceClass = if (tablet) "tablet" else "phone",
            locale = Locale.getDefault().toLanguageTag(),
            isDebug = debug ?: debuggable,
        )
    }

    fun isDebuggable(context: Context) = context.applicationInfo.flags and ApplicationInfo.FLAG_DEBUGGABLE != 0
}

/** Reads Google Play's install referrer once. Calls back with null when Play can't say. */
internal object PlayInstallReferrer {
    fun read(context: Context, log: Logger, done: (ReferrerDetails?) -> Unit) {
        val client = runCatching { InstallReferrerClient.newBuilder(context).build() }.getOrElse {
            done(null)
            return
        }
        try {
            client.startConnection(object : InstallReferrerStateListener {
                override fun onInstallReferrerSetupFinished(responseCode: Int) {
                    val details = if (responseCode == InstallReferrerClient.InstallReferrerResponse.OK) {
                        runCatching {
                            val r = client.installReferrer
                            ReferrerDetails(r.installReferrer ?: "", r.referrerClickTimestampSeconds, r.installBeginTimestampSeconds)
                        }.getOrNull()
                    } else {
                        log.debug("Install referrer unavailable (code $responseCode).")
                        null
                    }
                    runCatching { client.endConnection() }
                    done(details)
                }

                override fun onInstallReferrerServiceDisconnected() = Unit
            })
        } catch (e: RuntimeException) {
            log.debug("Install referrer failed: ${e.message}")
            done(null)
        }
    }
}

internal val mainHandler by lazy { Handler(Looper.getMainLooper()) }
