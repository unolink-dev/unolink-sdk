package dev.unolink

import com.fasterxml.jackson.databind.ObjectMapper
import com.networknt.schema.JsonSchemaFactory
import com.networknt.schema.SchemaValidatorsConfig
import com.networknt.schema.SpecVersion
import dev.unolink.internal.Clock
import dev.unolink.internal.DeviceInfo
import dev.unolink.internal.Engine
import dev.unolink.internal.HttpResponse
import dev.unolink.internal.KeyValueStore
import dev.unolink.internal.Logger
import dev.unolink.internal.QueueStore
import dev.unolink.internal.Scheduler
import dev.unolink.internal.Transport
import org.json.JSONObject
import org.junit.Assert.fail
import java.io.File
import java.io.IOException

/** The shared contract at the repo root (schemas, canned responses). */
internal object Contract {
    val dir = File(System.getProperty("unolink.contractDir") ?: "../../contract")
    private val mapper = ObjectMapper()
    private val factory = JsonSchemaFactory.getInstance(SpecVersion.VersionFlag.V202012)
    private val config = SchemaValidatorsConfig.builder().formatAssertionsEnabled(true).build()

    /** Fails the test if [json] doesn't match contract/schemas/<name>.schema.json. */
    fun assertValid(name: String, json: String) {
        val schema = factory.getSchema(File(dir, "schemas/$name.schema.json").readText(), config)
        val errors = schema.validate(mapper.readTree(json))
        if (errors.isNotEmpty()) fail("Doesn't match $name: ${errors.joinToString { it.message }}\n$json")
    }

    /** A canned server answer from contract/responses. */
    fun response(name: String): HttpResponse {
        val r = JSONObject(File(dir, "responses/$name.json").readText())
        return HttpResponse(r.getInt("status"), r.getJSONObject("body").toString())
    }
}

internal class Request(val method: String, val path: String, val body: String?) {
    val json: JSONObject get() = JSONObject(body!!)
}

/** Answers from a script; records every request. An empty script answers like a healthy server. */
internal class FakeServer : Transport {
    val requests = mutableListOf<Request>()
    private val script = ArrayDeque<() -> HttpResponse>()

    fun next(vararg responses: HttpResponse) = responses.forEach { r -> script.addLast { r } }
    fun networkError() = script.addLast { throw IOException("offline") }

    override fun send(method: String, path: String, body: String?): HttpResponse {
        requests += Request(method, path, body)
        script.removeFirstOrNull()?.let { return it() }
        return if (path == "/v1/install") Contract.response("install-unattributed")
        else HttpResponse(202, """{"accepted":${JSONObject(body!!).getJSONArray("events").length()},"duplicates":0,"rejected":[]}""")
    }

    fun paths() = requests.map { it.path }
    fun eventNames() = requests.filter { it.path == "/v1/events" }
        .flatMap { r -> r.json.getJSONArray("events").let { a -> (0 until a.length()).map { a.getJSONObject(it).getString("name") } } }
}

internal class MemoryStore : KeyValueStore {
    val values = mutableMapOf<String, String>()
    override fun getString(key: String) = values[key]
    override fun putString(key: String, value: String?) { if (value == null) values.remove(key) else values[key] = value }
}

internal class MemoryQueue : QueueStore {
    var lines: List<String> = emptyList()
    override fun load() = lines
    override fun save(lines: List<String>) { this.lines = lines }
}

/** Runs tasks immediately; delayed tasks wait for [advance]. */
internal class ManualScheduler(private val clock: FakeClock) : Scheduler {
    private val delayed = mutableListOf<Pair<Long, () -> Unit>>()
    override fun execute(task: () -> Unit) = task()
    override fun schedule(delayMillis: Long, task: () -> Unit) { delayed += (clock.time + delayMillis) to task }

    fun advance(millis: Long) {
        val until = clock.time + millis
        while (true) {
            val next = delayed.filter { it.first <= until }.minByOrNull { it.first } ?: break
            delayed.remove(next)
            clock.time = maxOf(clock.time, next.first)
            next.second()
        }
        clock.time = until
    }

    fun pending() = delayed.size
}

internal class FakeClock(var time: Long = 1_760_000_000_000) : Clock {
    override fun now() = time
}

internal class QuietLogger : Logger {
    val errors = mutableListOf<String>()
    override fun error(message: String) { errors += message }
    override fun warn(message: String) {}
    override fun info(message: String) {}
    override fun debug(message: String) {}
}

internal class Harness(
    val server: FakeServer = FakeServer(),
    val store: MemoryStore = MemoryStore(),
    val queue: MemoryQueue = MemoryQueue(),
    val clock: FakeClock = FakeClock(),
) {
    val scheduler = ManualScheduler(clock)
    val log = QuietLogger()
    val engine = Engine(
        device = DeviceInfo("android", "android", "0.1.0", "15", "1.9.5", "phone", "en-GB", false),
        transport = server, store = store, queueStore = queue, scheduler = scheduler, clock = clock, log = log,
        runOnMain = { it() }, random = { 0.5 },
    )

    /** A later app launch over the same disk state. */
    fun relaunch() = Harness(server, store, queue, clock)
}
