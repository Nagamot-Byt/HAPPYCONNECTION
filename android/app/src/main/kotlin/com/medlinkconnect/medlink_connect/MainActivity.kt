package com.medlinkconnect.medlink_connect

import android.content.Intent
import android.content.pm.PackageManager
import android.net.ConnectivityManager
import android.net.LinkProperties
import android.net.Network
import android.net.Uri
import android.net.VpnService
import android.os.Build
import android.os.Bundle
import android.system.Os
import android.system.OsConstants
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import java.io.BufferedReader
import java.io.InputStreamReader
import java.net.InetAddress
import java.net.InetSocketAddress
import java.net.NetworkInterface
import java.net.Socket
import java.nio.charset.Charset
import java.text.ParseException
import java.util.regex.Pattern

class MainActivity : FlutterActivity() {

    private val CHANNEL_NET = "com.medlinkconnect/network_diagnostics"
    private val CHANNEL_ROUTE = "com.medlinkconnect/route_manager"
    private val CHANNEL_RDP = "com.medlinkconnect/rdp_launcher"

    private var trackedRoutes: MutableList<String> = mutableListOf()

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        val messenger = flutterEngine.dartExecutor.binaryMessenger

        // -------- Network Diagnostics --------
        MethodChannel(messenger, CHANNEL_NET).setMethodCallHandler { call, result ->
            when (call.method) {
                "flushDns" -> handleFlushDns(result)
                "clearNetworkCaches" -> handleClearCaches(result)
                "ping" -> {
                    val host = call.argument<String>("host") ?: "8.8.8.8"
                    handlePing(host, result)
                }
                "checkTcpPort" -> {
                    val host = call.argument<String>("host") ?: ""
                    val port = call.argument<Int>("port") ?: 0
                    handleCheckTcpPort(host, port, result)
                }
                else -> result.notImplemented()
            }
        }

        // -------- Route Manager --------
        MethodChannel(messenger, CHANNEL_ROUTE).setMethodCallHandler { call, result ->
            when (call.method) {
                "addRoute" -> {
                    val dest = call.argument<String>("destinationCidr")
                    val gw = call.argument<String>("gateway")
                    val iface = call.argument<String>("interfaceName")
                    if (dest == null || gw == null || iface == null) {
                        result.error("argumento_invalido", "Faltan parámetros", null)
                        return@setMethodCallHandler
                    }
                    handleAddRoute(dest, gw, iface, result)
                }
                "removeRoute" -> {
                    val dest = call.argument<String>("destinationCidr")
                    if (dest == null) {
                        result.error("argumento_invalido", "Falta destinationCidr", null)
                        return@setMethodCallHandler
                    }
                    handleRemoveRoute(dest, result)
                }
                "enableSplitTunnel" -> {
                    val subnets = call.argument<List<String>>("hospitalSubnets")
                    val gw = call.argument<String>("gateway")
                    val iface = call.argument<String>("interfaceName")
                    if (subnets == null || gw == null || iface == null) {
                        result.error("argumento_invalido", "Se requieren hospitalSubnets, gateway, interfaceName.", null)
                        return@setMethodCallHandler
                    }
                    handleEnableSplit(subnets, gw, iface, result)
                }
                "disableSplitTunnel" -> handleDisableSplit(result)
                "getRoutes" -> handleGetRoutes(result)
                "getPrimaryDefaultRouteInfo" -> handleGetPrimaryDefaultRouteInfo(result)
                "listInterfaces" -> handleListIfaces(result)
                "verifyRoutes" -> {
                    val subnets = call.argument<List<String>>("hospitalSubnets")
                    val gw = call.argument<String>("gateway")
                    val iface = call.argument<String>("interfaceName")
                    if (subnets == null || gw == null || iface == null) {
                        result.error("argumento_invalido", "Se requieren hospitalSubnets, gateway, interfaceName.", null)
                        return@setMethodCallHandler
                    }
                    handleVerifyRoutes(subnets, gw, iface, result)
                }
                else -> result.notImplemented()
            }
        }

        // -------- RDP Launcher --------
        MethodChannel(messenger, CHANNEL_RDP).setMethodCallHandler { call, result ->
            when (call.method) {
                "preLaunch" -> handlePreLaunch(result)
                "isRdpClientAvailable" -> handleRdpAvailable(result)
                "launchRdp" -> {
                    val host = call.argument<String>("host")
                    if (host == null) {
                        result.error("argumento_invalido", "Falta host", null)
                        return@setMethodCallHandler
                    }
                    val port = call.argument<Int>("port") ?: 3389
                    val username = call.argument<String>("username") ?: ""
                    val domain = call.argument<String>("domain") ?: ""
                    val webFeed = call.argument<Boolean>("useWebFeed") ?: false
                    handleLaunchRdp(host, port, username, domain, webFeed, result)
                }
                else -> result.notImplemented()
            }
        }
    }

    // ============================================================
    // Helpers
    // ============================================================
    private fun runShell(cmd: String): Pair<Int, String> {
        return try {
            val proc = Runtime.getRuntime().exec(arrayOf("sh", "-c", cmd))
            val reader = BufferedReader(InputStreamReader(proc.inputStream, Charsets.UTF_8))
            val errReader = BufferedReader(InputStreamReader(proc.errorStream, Charsets.UTF_8))
            val out = StringBuilder()
            reader.lineSequence().forEach { out.append(it).append('\n') }
            errReader.lineSequence().forEach { out.append(it).append('\n') }
            val code = proc.waitFor()
            Pair(code, out.toString().trim())
        } catch (t: Throwable) {
            Pair(-1, "Excepción: ${t.message}")
        }
    }

    private fun isUptimeAsRoot(): Boolean {
        // Best effort: check `su -c id` returns uid 0
        val r = runShell("su -c 'id -u' 2>/dev/null")
        return r.second == "0"
    }

    private fun percentEncode(s: String): String {
        val sb = StringBuilder()
        for (c in s) {
            when {
                c.isLetterOrDigit() || "-._~".contains(c) -> sb.append(c)
                else -> sb.append("%").append(String.format("%02X", c.code))
            }
        }
        return sb.toString()
    }

    // ============================================================
    // Network Diagnostics
    // ============================================================
    private fun handleFlushDns(result: MethodChannel.Result) {
        CoroutineScope(Dispatchers.IO).launch {
            // Note: Android doesn't expose per-app DNS flush; try connectvity tricks + release network cache.
            // For best results we require `su` with ndc resolver clearnetdns.
            val r1 = runShell("su -c 'ndc resolver clearnetdns' 2>&1 || true")
            val r2 = runShell("su -c 'ndc resolver flushdefaultif' 2>&1 || true")
            val msg = "flush: DNS cleared (ndc resolver clearnetdns exit ${r1.first}, flushdefaultif ${r2.first})."
            withContext(Dispatchers.Main) { result.success(msg) }
        }
    }

    private fun handleClearCaches(result: MethodChannel.Result) {
        CoroutineScope(Dispatchers.IO).launch {
            val r1 = runShell("su -c 'ip -s -s neigh flush all' 2>&1 || true")
            val msg = "arp/neigh flush: exit ${r1.first} → ${r1.second.take(200)}"
            withContext(Dispatchers.Main) { result.success(msg) }
        }
    }

    private fun handlePing(host: String, result: MethodChannel.Result) {
        CoroutineScope(Dispatchers.IO).launch {
            // Try 1: Java InetAddress isReachable (needs ICMP, often uses echo TCP/7)
            val javaPing = try {
                val addr = InetAddress.getByName(host)
                val start = System.currentTimeMillis()
                val ok = addr.isReachable(3000)
                if (ok) System.currentTimeMillis() - start else -1L
            } catch (_: Exception) { -1L }
            if (javaPing > 0) {
                withContext(Dispatchers.Main) { result.success(javaPing.toInt()) }
                return@launch
            }
            // Try 2: shell `ping -c 4 -W 2`
            val r = runShell("ping -c 4 -W 2 $host 2>&1")
            if (r.first != 0) {
                withContext(Dispatchers.Main) {
                    result.error("inaccesible", "Host inaccesible", null)
                }
                return@launch
            }
            // Parse avg: rtt min/avg/max/mdev = X/X/X/X ms
            val avg = parsePingAvg(r.second)
            if (avg != null) {
                withContext(Dispatchers.Main) { result.success(avg) }
            } else {
                withContext(Dispatchers.Main) {
                    result.error("ping_error", "No se pudo parsear ping", null)
                }
            }
        }
    }

    private fun handleCheckTcpPort(host: String, port: Int, result: MethodChannel.Result) {
        CoroutineScope(Dispatchers.IO).launch {
            if (host.isBlank() || port <= 0 || port > 65535) {
                withContext(Dispatchers.Main) {
                    result.error("argumento_invalido", "Host o puerto inválido", null)
                }
                return@launch
            }
            try {
                val socket = Socket()
                val start = System.currentTimeMillis()
                socket.connect(InetSocketAddress(host, port), 1500)
                val elapsed = (System.currentTimeMillis() - start).toInt()
                socket.close()
                withContext(Dispatchers.Main) { result.success(elapsed) }
            } catch (_: Throwable) {
                withContext(Dispatchers.Main) {
                    result.error("inaccesible", "No se pudo establecer conexión TCP con el puerto", null)
                }
            }
        }
    }

    private fun parsePingAvg(output: String): Int? {
        val patterns = listOf(
            "rtt min/avg/max/(mdev|stddev) = [\\d.]+/([\\d.]+)/",
            "round-trip min/avg/max/(stddev|mdev) = [\\d.]+/([\\d.]+)/",
            "= [\\d.]+/([\\d.]+)/"
        )
        for (p in patterns) {
            val m = Pattern.compile(p).matcher(output)
            if (m.find()) {
                val group = try { m.group(2) ?: m.group(1) } catch (_: Exception) { m.group(1) }
                if (group != null) {
                    return try { Math.round(group.toDouble()).toInt() } catch (_: Exception) { null }
                }
            }
        }
        return null
    }

    // ============================================================
    // Route Manager
    // ============================================================
    private fun handleAddRoute(dest: String, gw: String, iface: String, result: MethodChannel.Result) {
        CoroutineScope(Dispatchers.IO).launch {
            if (!isUptimeAsRoot()) {
                withContext(Dispatchers.Main) {
                    result.error("permiso_denegado",
                        "Requiere ROOT (su) para cambiar rutas. Alternativa: usar VpnService de Android.",
                        null)
                }
                return@launch
            }
            // Try ip route add, fallback route add
            val cmd = "su -c 'ip route add $dest via $gw dev $iface' 2>&1"
            val r = runShell(cmd)
            if (r.first != 0) {
                val fallback = "su -c 'route add -net $dest gw $gw dev $iface' 2>&1"
                val r2 = runShell(fallback)
                if (r2.first != 0) {
                    val msg = if (r.second.isNotBlank()) r.second else r2.second
                    withContext(Dispatchers.Main) {
                        result.error("error_comando", "Error al agregar ruta: $msg", null)
                    }
                    return@launch
                }
            }
            withContext(Dispatchers.Main) { result.success("Ruta $dest agregada exitosamente.") }
        }
    }

    private fun handleRemoveRoute(dest: String, result: MethodChannel.Result) {
        CoroutineScope(Dispatchers.IO).launch {
            val r = runShell("su -c 'ip route del $dest' 2>&1")
            if (r.first != 0) {
                val r2 = runShell("su -c 'route del -net $dest' 2>&1")
                if (r2.first != 0) {
                    withContext(Dispatchers.Main) {
                        result.error("error_comando", "Error al eliminar ruta: ${r.second.ifBlank { r2.second }}", null)
                    }
                    return@launch
                }
            }
            withContext(Dispatchers.Main) { result.success("Ruta $dest eliminada.") }
        }
    }

    private fun handleEnableSplit(
        subnets: List<String>, gw: String, iface: String,
        result: MethodChannel.Result
    ) {
        CoroutineScope(Dispatchers.IO).launch {
            if (!isUptimeAsRoot()) {
                withContext(Dispatchers.Main) {
                    result.error("permiso_denegado",
                        "Se requieren privilegios ROOT (su). Si tu dispositivo no es rooteado, usa VpnService.",
                        null)
                }
                return@launch
            }
            val added = mutableListOf<String>()
            for (rawSubnet in subnets) {
                val subnet = rawSubnet.trim()
                if (subnet.isEmpty()) continue
                val cmd = "su -c 'ip route add $subnet via $gw dev $iface' 2>&1"
                val r = runShell(cmd)
                if (r.first != 0) {
                    val r2 = runShell("su -c 'route add -net $subnet gw $gw dev $iface' 2>&1")
                    if (r2.first != 0) {
                        // Rollback
                        for (prev in added) {
                            runShell("su -c 'ip route del $prev' 2>&1 || true")
                        }
                        withContext(Dispatchers.Main) {
                            result.error("error_tunel_dividido",
                                "Error en ruta $subnet. Se revirtieron los cambios.", null)
                        }
                        return@launch
                    }
                }
                added.add(subnet)
            }
            trackedRoutes.addAll(added)
            withContext(Dispatchers.Main) {
                result.success("Túnel dividido habilitado exitosamente. ${added.size} ruta(s) agregada(s).")
            }
        }
    }

    private fun handleDisableSplit(result: MethodChannel.Result) {
        CoroutineScope(Dispatchers.IO).launch {
            val current = ArrayList(trackedRoutes)
            trackedRoutes.clear()
            if (current.isEmpty()) {
                withContext(Dispatchers.Main) {
                    result.success("No hay rutas de túnel dividido activas.")
                }
                return@launch
            }
            val msgs = mutableListOf<String>()
            for (dest in current) {
                val r = runShell("su -c 'ip route del $dest' 2>&1 || true")
                msgs.add(if (r.first == 0) "Ruta $dest eliminada." else "Error al eliminar $dest: ${r.second.take(120)}")
            }
            withContext(Dispatchers.Main) { result.success(msgs.joinToString(" ")) }
        }
    }

    private fun handleGetRoutes(result: MethodChannel.Result) {
        CoroutineScope(Dispatchers.IO).launch {
            val r = runShell("ip route 2>&1 || cat /proc/net/route 2>&1")
            withContext(Dispatchers.Main) { result.success(r.second) }
        }
    }

    private fun handleGetPrimaryDefaultRouteInfo(result: MethodChannel.Result) {
        CoroutineScope(Dispatchers.IO).launch {
            val out = hashMapOf<String, String>(
                "interfaceName" to "",
                "gateway" to "",
                "routeMetric" to ""
            )
            try {
                val cm = getSystemService(CONNECTIVITY_SERVICE) as ConnectivityManager
                val active = cm.activeNetwork
                val props = cm.getLinkProperties(active)
                if (props != null) {
                    out["interfaceName"] = props.interfaceName ?: ""
                    val defaultRoute = props.routes.firstOrNull { it.isDefaultRoute && it.gateway != null }
                    out["gateway"] = defaultRoute?.gateway?.hostAddress ?: ""
                }
            } catch (_: Throwable) {
            }
            withContext(Dispatchers.Main) { result.success(out) }
        }
    }

    private fun handleListIfaces(result: MethodChannel.Result) {
        CoroutineScope(Dispatchers.IO).launch {
            val out = mutableListOf<String>()
            try {
                val nis = NetworkInterface.getNetworkInterfaces()
                while (nis.hasMoreElements()) {
                    val ni = nis.nextElement()
                    out.add(ni.name)
                }
            } catch (_: Exception) { }
            if (out.isEmpty()) {
                // fallback shell
                val r = runShell("ls /sys/class/net 2>&1")
                out.addAll(r.second.split('\n').map { it.trim() }.filter { it.isNotBlank() })
            }
            withContext(Dispatchers.Main) { result.success(out) }
        }
    }

    private fun handleVerifyRoutes(
        subnets: List<String>,
        gw: String,
        iface: String,
        result: MethodChannel.Result
    ) {
        CoroutineScope(Dispatchers.IO).launch {
            val routesOutput = runShell("ip route 2>&1").second
            val missing = mutableListOf<String>()
            for (rawSubnet in subnets) {
                val subnet = rawSubnet.trim()
                if (subnet.isEmpty()) continue
                val present = routesOutput.contains(subnet) &&
                    (gw.isBlank() || routesOutput.contains(gw)) &&
                    (iface.isBlank() || routesOutput.contains(iface))
                if (!present) {
                    missing.add(subnet)
                }
            }
            withContext(Dispatchers.Main) { result.success(missing) }
        }
    }

    // ============================================================
    // RDP Launcher
    // ============================================================
    private fun handlePreLaunch(result: MethodChannel.Result) {
        // Known packages that handle RDP URIs
        val knownPkgs = listOf(
            "com.microsoft.rdc.android",
            "com.microsoft.rdc.android.beta",
            "com.microsoft.rdc.internal",
            "net.remmina",
            "ch.cern.rdp"
        )
        for (pkg in knownPkgs) {
            try {
                packageManager.getPackageInfo(pkg, 0)
                result.success(true)
                return
            } catch (_: PackageManager.NameNotFoundException) { }
        }
        // Fallback: can we resolve Intent rdp:// ?
        val testIntent = Intent(Intent.ACTION_VIEW, Uri.parse("rdp://example.com:3389"))
        val matches = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            packageManager.queryIntentActivities(testIntent,
                PackageManager.ResolveInfoFlags.of(0))
        } else {
            @Suppress("DEPRECATION")
            packageManager.queryIntentActivities(testIntent, 0)
        }
        if (matches.isNotEmpty()) {
            result.success(true)
            return
        }
        result.error("sin_manejador_rdp",
            "Instala Microsoft Remote Desktop (o cliente RDP) desde Play Store.", null)
    }

    private fun handleRdpAvailable(result: MethodChannel.Result) {
        // Same as preLaunch but returns bool, no error
        val knownPkgs = listOf(
            "com.microsoft.rdc.android",
            "com.microsoft.rdc.android.beta",
            "com.microsoft.rdc.internal",
            "net.remmina",
            "ch.cern.rdp"
        )
        for (pkg in knownPkgs) {
            try {
                packageManager.getPackageInfo(pkg, 0)
                result.success(true)
                return
            } catch (_: PackageManager.NameNotFoundException) { }
        }
        val testIntent = Intent(Intent.ACTION_VIEW, Uri.parse("rdp://example.com:3389"))
        val matches = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            packageManager.queryIntentActivities(testIntent,
                PackageManager.ResolveInfoFlags.of(0))
        } else {
            @Suppress("DEPRECATION")
            packageManager.queryIntentActivities(testIntent, 0)
        }
        result.success(matches.isNotEmpty())
    }

    private fun handleLaunchRdp(
        host: String, port: Int, username: String,
        domain: String, webFeed: Boolean,
        result: MethodChannel.Result
    ) {
        if (port <= 0 || port > 65535) {
            result.error("argumento_invalido", "Puerto inválido", null)
            return
        }
        val uri = buildString {
            if (webFeed) {
                append("ms-rd-web://${percentEncode(host)}")
            } else {
                append("rdp://")
                var hasAuth = false
                if (domain.isNotBlank()) {
                    append(percentEncode(domain)).append("\\")
                    hasAuth = true
                }
                if (username.isNotBlank()) {
                    append(percentEncode(username))
                    hasAuth = true
                }
                if (hasAuth) append("@")
                append("${percentEncode(host)}:$port")
            }
        }
        val intent = Intent(Intent.ACTION_VIEW, Uri.parse(uri))
        intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
        try {
            startActivity(intent)
            result.success("Conexión RDP lanzada a $host:$port correctamente.")
        } catch (t: Throwable) {
            result.error("lanzamiento_fallido",
                "No se pudo lanzar cliente RDP: ${t.message}", null)
        }
    }
}
