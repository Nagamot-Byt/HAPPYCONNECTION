package com.medlinkconnect.medlink_connect

import android.util.Log
import androidx.annotation.NonNull
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.MethodChannel.MethodCallHandler
import io.flutter.plugin.common.MethodChannel.Result
import java.net.InetAddress
import java.net.InetSocketAddress
import java.net.Socket

/**
 * Android implementation of the `com.medlinkconnect/network_diagnostics`
 * method channel.
 *
 * **DNS flush / cache clear:** These are no-ops on Android because the OS
 * sandboxes apps from manipulating system-level DNS and ARP caches. The
 * methods always return `true` to indicate "no action needed" rather than
 * "failure".
 *
 * **Ping:** ICMP is blocked on most Android devices (non-root). Instead,
 * we perform a TCP connect to the target host on port 3389 (RDP) and
 * measure the connection time. If port 3389 is not reachable, we fall
 * back to DNS resolution time measurement.
 */
class NetworkDiagnosticsPlugin : FlutterPlugin, MethodCallHandler {

    companion object {
        private const val TAG = "NetworkDiagnostics"
        private const val CHANNEL = "com.medlinkconnect/network_diagnostics"
        private const val DEFAULT_PORT = 3389
        private const val CONNECT_TIMEOUT_MS = 2000
    }

    private lateinit var channel: MethodChannel

    override fun onAttachedToEngine(@NonNull binding: FlutterPlugin.FlutterPluginBinding) {
        channel = MethodChannel(binding.binaryMessenger, CHANNEL)
        channel.setMethodCallHandler(this)
    }

    override fun onDetachedFromEngine(@NonNull binding: FlutterPlugin.FlutterPluginBinding) {
        channel.setMethodCallHandler(null)
    }

    override fun onMethodCall(@NonNull call: MethodCall, @NonNull result: Result) {
        when (call.method) {
            "flushDns" -> handleFlushDns(result)
            "clearNetworkCaches" -> handleClearCaches(result)
            "ping" -> handlePing(call, result)
            else -> result.notImplemented()
        }
    }

    // ── DNS flush ──────────────────────────────────────────────────────

    private fun handleFlushDns(result: Result) {
        // Android does not expose DNS cache flush to apps.
        // Return true as a no-op with a log note.
        Log.i(TAG, "flushDns: no-op on Android (sandboxed — cannot flush system DNS cache)")
        result.success(true)
    }

    // ── Cache clear ────────────────────────────────────────────────────

    private fun handleClearCaches(result: Result) {
        // ARP cache clearing is not available to Android apps.
        Log.i(TAG, "clearNetworkCaches: no-op on Android (sandboxed — cannot clear system ARP cache)")
        result.success(true)
    }

    // ── Ping (TCP connect / DNS proxy) ─────────────────────────────────

    private fun handlePing(call: MethodCall, result: Result) {
        val args = call.arguments as? Map<*, *>
        val host = args?.get("host") as? String ?: "8.8.8.8"
        val count = args?.get("count") as? Int ?: 4
        val timeoutMs = args?.get("timeoutMs") as? Int ?: 2000

        Thread {
            try {
                val latencies = mutableListOf<Long>()

                for (i in 1..count) {
                    val start = System.currentTimeMillis()
                    val reachable = tcpConnect(host, DEFAULT_PORT, timeoutMs)
                    val elapsed = System.currentTimeMillis() - start

                    if (reachable) {
                        latencies.add(elapsed)
                    }
                }

                if (latencies.isNotEmpty()) {
                    val avgMs = latencies.average().toLong().toInt()
                    runOnUiThread(channel) { result.success(avgMs) }
                } else {
                    // Fallback: DNS resolution time
                    val dnsStart = System.currentTimeMillis()
                    val addr = try {
                        InetAddress.getByName(host)
                    } catch (e: Exception) {
                        null
                    }
                    val dnsElapsed = System.currentTimeMillis() - dnsStart

                    if (addr != null) {
                        Log.i(TAG, "ping: TCP connect failed but DNS resolved in ${dnsElapsed}ms — using as proxy")
                        runOnUiThread(channel) { result.success(dnsElapsed.toInt()) }
                    } else {
                        Log.w(TAG, "ping: host $host unreachable via TCP:$DEFAULT_PORT and DNS")
                        runOnUiThread(channel) { result.success(null) }
                    }
                }
            } catch (e: Exception) {
                Log.e(TAG, "ping: unexpected error — ${e.message}", e)
                runOnUiThread(channel) { result.success(null) }
            }
        }.start()
    }

    // ── helpers ────────────────────────────────────────────────────────

    private fun tcpConnect(host: String, port: Int, timeoutMs: Int): Boolean {
        return try {
            val socket = Socket()
            socket.connect(InetSocketAddress(host, port), timeoutMs)
            socket.close()
            true
        } catch (e: Exception) {
            false
        }
    }

    private fun runOnUiThread(channel: MethodChannel, block: () -> Unit) {
        // The Flutter callback must happen on the main thread.
        // MethodChannel calls are already handled on the main thread,
        // but since we're on a background thread we post to the handler.
        android.os.Handler(android.os.Looper.getMainLooper()).post(block)
    }
}
