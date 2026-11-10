package com.medlinkconnect.medlink_connect

import android.content.Intent
import android.content.pm.PackageManager
import android.content.pm.ResolveInfo
import android.net.ConnectivityManager
import android.net.LinkProperties
import android.net.Network
import android.net.NetworkCapabilities
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
import java.util.concurrent.TimeUnit
import java.util.regex.Pattern

class MainActivity : FlutterActivity() {

    private val CHANNEL_NET = "com.medlinkconnect/network_diagnostics"
    private val CHANNEL_ROUTE = "com.medlinkconnect/route_manager"
    private val CHANNEL_RDP = "com.medlinkconnect/rdp_launcher"

    private data class TrackedRoute(
        val destination: String,
        val gateway: String,
        val interfaceName: String
    )

    private val trackedRoutes: MutableList<TrackedRoute> = mutableListOf()
    private val routeLock = Any()

    private val safeHost = Regex("^[A-Za-z0-9._:%-]+$")
    private val safeInterface = Regex("^[A-Za-z0-9_.:-]+$")

    private fun isSafeIpv4(value: String): Boolean {
        val parts = value.split(".")
        if (parts.size != 4) return false
        return parts.all { part ->
            part.isNotEmpty() && part.all { it.isDigit() } &&
                (part.toIntOrNull()?.let { it in 0..255 } == true)
        }
    }

    private fun isSafeCidr(value: String): Boolean {
        val parts = value.split("/")
        if (parts.size > 2 || !isSafeIpv4(parts[0])) return false
        if (parts.size == 1) return true
        return parts[1].toIntOrNull()?.let { it in 1..32 } == true
    }

    private fun isDefaultCidr(value: String): Boolean =
        value.substringAfter('/', "").toIntOrNull() == 0

    private fun ipUnspecified(value: String): Boolean =
        value == "0.0.0.0" || value == "::"

    private fun stripHostPrefix(value: String): String =
        if (value.endsWith("/32")) value.dropLast(3) else value

    private fun prefixMatches(a: String, b: String): Boolean =
        stripHostPrefix(a) == stripHostPrefix(b)

    private fun routeLineMatches(
        line: String,
        destination: String,
        gateway: String,
        interfaceName: String
    ): Boolean {
        val tokens = line.trim().split(Regex("\\s+")).filter { it.isNotEmpty() }
        if (tokens.isEmpty() || !prefixMatches(tokens.first(), destination)) {
            return false
        }
        var viaMatches = false
        var devMatches = false
        for (i in 0 until tokens.size - 1) {
            if (tokens[i] == "via" && tokens[i + 1] == gateway) {
                viaMatches = true
            } else if (tokens[i] == "dev" && tokens[i + 1] == interfaceName) {
                devMatches = true
            }
        }
        return viaMatches && devMatches
    }

    private fun routeExists(
        destination: String,
        gateway: String,
        interfaceName: String
    ): Boolean {
        val output = runShell("ip route show $destination 2>&1").second
        return output.lineSequence().any {
            routeLineMatches(it, destination, gateway, interfaceName)
        }
    }

    private fun routeExistsAny(destination: String): Boolean {
        val output = runShell("ip route show $destination 2>&1").second
        return output.lineSequence().any { line ->
            val first = line.trim().split(Regex("\\s+")).firstOrNull() ?: return@any false
            prefixMatches(first, destination)
        }
    }

    private fun hasTrackedFor(destination: String): Boolean =
        synchronized(routeLock) { trackedRoutes.any { it.destination == destination } }

    private fun removeTrackedFor(destination: String): Boolean {
        val matches = synchronized(routeLock) {
            trackedRoutes.filter { it.destination == destination }
        }
        val removed = mutableListOf<TrackedRoute>()
        val kept = mutableListOf<TrackedRoute>()
        for (route in matches) {
            val r = runShell(
                "su -c 'ip route del ${route.destination} via ${route.gateway} " +
                    "dev ${route.interfaceName}' 2>&1"
            )
            val gone = r.first == 0 || !routeExists(
                route.destination, route.gateway, route.interfaceName
            )
            if (gone) removed.add(route) else kept.add(route)
        }
        synchronized(routeLock) {
            trackedRoutes.removeAll { it.destination == destination }
            trackedRoutes.addAll(kept)
        }
        return removed.isNotEmpty()
    }

    private fun removeTrackedExact(
        destination: String,
        gateway: String,
        interfaceName: String
    ) {
        synchronized(routeLock) {
            trackedRoutes.removeAll {
                it.destination == destination &&
                    it.gateway == gateway &&
                    it.interfaceName == interfaceName
            }
        }
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        val messenger = flutterEngine.dartExecutor.binaryMessenger

        // -------- Network Diagnostics --------
        MethodChannel(messenger, CHANNEL_NET).setMethodCallHandler { call, result ->
            when (call.method) {
                "flushDns" -> handleFlushDns(result)
                "clearNetworkCaches" -> handleClearCaches(result)
                "ping" -> {
                    val host = call.argument<String>("host")
                    if (host == null) {
                        result.error("argumento_invalido", "Falta host", null)
                        return@setMethodCallHandler
                    }
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
                    handleRemoveRoute(
                        dest,
                        call.argument<String>("gateway") ?: "",
                        call.argument<String>("interfaceName") ?: "",
                        result
                    )
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
            val proc = ProcessBuilder("sh", "-c", cmd)
                .redirectErrorStream(true)
                .start()
            val output = StringBuilder()
            val reader = Thread {
                try {
                    BufferedReader(
                        InputStreamReader(proc.inputStream, Charsets.UTF_8)
                    ).use { output.append(it.readText()) }
                } catch (_: Throwable) {
                    // The process may be destroyed on timeout; keep partial output.
                }
            }
            reader.start()
            val finished = proc.waitFor(20, TimeUnit.SECONDS)
            if (!finished) {
                proc.destroyForcibly()
                reader.join(2000)
                return Pair(-1, "Tiempo de espera agotado al ejecutar el comando.")
            }
            reader.join(2000)
            Pair(proc.exitValue(), output.toString().trim())
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
            if (!isUptimeAsRoot()) {
                withContext(Dispatchers.Main) {
                    result.error(
                        "permiso_denegado",
                        "Se requieren privilegios ROOT (su) para limpiar la caché DNS.",
                        null
                    )
                }
                return@launch
            }
            // Android does not expose per-app DNS flush; ndc is best-effort and
            // is not present on every Android version.
            val r1 = runShell("su -c 'ndc resolver clearnetdns' 2>&1")
            val r2 = runShell("su -c 'ndc resolver flushdefaultif' 2>&1")
            val ok = r1.first == 0 || r2.first == 0
            val detail = "ndc clearnetdns=${r1.first} (${r1.second.take(120)}), " +
                "flushdefaultif=${r2.first} (${r2.second.take(120)})"
            withContext(Dispatchers.Main) {
                if (ok) {
                    result.success("Caché DNS limpiada. $detail")
                } else {
                    result.error(
                        "error_comando",
                        "No se pudo limpiar la caché DNS. $detail",
                        null
                    )
                }
            }
        }
    }

    private fun handleClearCaches(result: MethodChannel.Result) {
        CoroutineScope(Dispatchers.IO).launch {
            if (!isUptimeAsRoot()) {
                withContext(Dispatchers.Main) {
                    result.error(
                        "permiso_denegado",
                        "Se requieren privilegios ROOT (su) para limpiar la tabla ARP/neigh.",
                        null
                    )
                }
                return@launch
            }
            val r1 = runShell("su -c 'ip -s -s neigh flush all' 2>&1")
            withContext(Dispatchers.Main) {
                if (r1.first == 0) {
                    result.success("Caché ARP/neigh limpiada. ${r1.second.take(200)}")
                } else {
                    result.error(
                        "error_comando",
                        "No se pudo limpiar la caché ARP/neigh: ${r1.second.take(200)}",
                        null
                    )
                }
            }
        }
    }

    private fun handlePing(host: String, result: MethodChannel.Result) {
        if (!safeHost.matches(host)) {
            result.error("argumento_invalido", "Host contiene caracteres no permitidos", null)
            return
        }
        CoroutineScope(Dispatchers.IO).launch {
            // Try 1: Java InetAddress isReachable (needs ICMP, often uses echo TCP/7)
            val javaPing = try {
                val addr = InetAddress.getByName(host)
                val start = System.currentTimeMillis()
                val ok = addr.isReachable(2000)
                if (ok) System.currentTimeMillis() - start else -1L
            } catch (_: Exception) { -1L }
            if (javaPing > 0) {
                withContext(Dispatchers.Main) { result.success(javaPing.toInt()) }
                return@launch
            }
            // Try 2: shell `ping -c 2 -W 2`
            val r = runShell("ping -c 2 -W 2 $host 2>&1")
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
        if (host.isBlank() || !safeHost.matches(host) || port <= 0 || port > 65535) {
            result.error("argumento_invalido", "Host o puerto inválido", null)
            return
        }
        CoroutineScope(Dispatchers.IO).launch {
            try {
                val socket = Socket()
                val start = System.currentTimeMillis()
                socket.connect(InetSocketAddress(host, port), 5000)
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
        if (!isSafeCidr(dest) || !isSafeIpv4(gw) || !safeInterface.matches(iface)) {
            result.error("argumento_invalido", "Parámetros de ruta inválidos", null)
            return
        }
        if (isDefaultCidr(dest)) {
            result.error("argumento_invalido", "No se permite agregar la ruta por defecto /0.", null)
            return
        }
        if (ipUnspecified(gw)) {
            result.error("argumento_invalido", "Gateway inválido", null)
            return
        }
        CoroutineScope(Dispatchers.IO).launch {
            if (routeExists(dest, gw, iface)) {
                withContext(Dispatchers.Main) {
                    result.success("La ruta ya existe para la interfaz indicada.")
                }
                return@launch
            }
            if (!isUptimeAsRoot()) {
                withContext(Dispatchers.Main) {
                    result.error("permiso_denegado",
                        "Requiere ROOT (su) para cambiar rutas. Alternativa: usar VpnService de Android.",
                        null)
                }
                return@launch
            }
            removeTrackedFor(dest)
            if (routeExistsAny(dest)) {
                withContext(Dispatchers.Main) {
                    result.error("conflicto_ruta",
                        "Ya existe una ruta para $dest en otra interfaz. Revísala antes de continuar.",
                        null)
                }
                return@launch
            }
            val cmd = "su -c 'ip route add $dest via $gw dev $iface' 2>&1"
            val r = runShell(cmd)
            if (r.first != 0) {
                withContext(Dispatchers.Main) {
                    result.error("error_comando", "Error al agregar ruta: ${r.second}", null)
                }
                return@launch
            }
            if (!routeExists(dest, gw, iface)) {
                runShell("su -c 'ip route del $dest via $gw dev $iface' 2>&1")
                withContext(Dispatchers.Main) {
                    result.error("error_verificacion",
                        "La ruta $dest no pudo verificarse tras agregarla.", null)
                }
                return@launch
            }
            synchronized(routeLock) {
                if (trackedRoutes.none {
                        it.destination == dest && it.gateway == gw && it.interfaceName == iface
                    }) {
                    trackedRoutes.add(TrackedRoute(dest, gw, iface))
                }
            }
            withContext(Dispatchers.Main) { result.success("Ruta $dest agregada exitosamente.") }
        }
    }

    private fun handleRemoveRoute(
        dest: String,
        gw: String,
        iface: String,
        result: MethodChannel.Result
    ) {
        if (!isSafeCidr(dest) || isDefaultCidr(dest)) {
            result.error("argumento_invalido", "CIDR inválido", null)
            return
        }
        if ((gw.isNotEmpty() && !isSafeIpv4(gw)) ||
            (iface.isNotEmpty() && !safeInterface.matches(iface))
        ) {
            result.error("argumento_invalido", "Gateway o interfaz inválidos", null)
            return
        }
        val exact = gw.isNotEmpty() && iface.isNotEmpty()
        CoroutineScope(Dispatchers.IO).launch {
            if (exact) {
                if (!routeExists(dest, gw, iface)) {
                    removeTrackedExact(dest, gw, iface)
                    withContext(Dispatchers.Main) {
                        result.success("La ruta $dest ya no existe; nada que limpiar.")
                    }
                    return@launch
                }
                if (!isUptimeAsRoot()) {
                    withContext(Dispatchers.Main) {
                        result.error("permiso_denegado",
                            "Requiere ROOT (su) para cambiar rutas. Alternativa: usar VpnService de Android.",
                            null)
                    }
                    return@launch
                }
                val primary = runShell("su -c 'ip route del $dest via $gw dev $iface' 2>&1")
                if (primary.first == 0 || !routeExists(dest, gw, iface)) {
                    removeTrackedExact(dest, gw, iface)
                    withContext(Dispatchers.Main) { result.success("Ruta $dest eliminada.") }
                } else {
                    withContext(Dispatchers.Main) {
                        result.error("error_comando",
                            "Error al eliminar ruta: ${primary.second}", null)
                    }
                }
                return@launch
            }

            if (!hasTrackedFor(dest)) {
                withContext(Dispatchers.Main) {
                    result.success("La ruta $dest no fue agregada por la aplicación; no se modificó.")
                }
                return@launch
            }
            if (!isUptimeAsRoot()) {
                withContext(Dispatchers.Main) {
                    result.error("permiso_denegado",
                        "Requiere ROOT (su) para cambiar rutas. Alternativa: usar VpnService de Android.",
                        null)
                }
                return@launch
            }
            removeTrackedFor(dest)
            if (hasTrackedFor(dest)) {
                withContext(Dispatchers.Main) {
                    result.error("error_comando", "No se pudo eliminar la ruta $dest.", null)
                }
            } else {
                withContext(Dispatchers.Main) {
                    result.success("Ruta $dest eliminada (solo si fue agregada por la aplicación).")
                }
            }
        }
    }

    private fun handleEnableSplit(
        subnets: List<String>, gw: String, iface: String,
        result: MethodChannel.Result
    ) {
        if (!isSafeIpv4(gw) || !safeInterface.matches(iface) ||
            subnets.any { !isSafeCidr(it.trim()) || isDefaultCidr(it.trim()) }
        ) {
            result.error("argumento_invalido", "Parámetros de túnel inválidos", null)
            return
        }
        if (ipUnspecified(gw)) {
            result.error("argumento_invalido", "Gateway inválido", null)
            return
        }
        CoroutineScope(Dispatchers.IO).launch {
            val pending = subnets.map { it.trim() }.filter { it.isNotEmpty() }
                .filterNot { routeExists(it, gw, iface) }
            if (pending.isEmpty()) {
                withContext(Dispatchers.Main) {
                    result.success("Las rutas del túnel dividido ya existen.")
                }
                return@launch
            }
            if (!isUptimeAsRoot()) {
                withContext(Dispatchers.Main) {
                    result.error("permiso_denegado",
                        "Se requieren privilegios ROOT (su). Si tu dispositivo no es rooteado, usa VpnService.",
                        null)
                }
                return@launch
            }
            val added = mutableListOf<TrackedRoute>()
            fun rollback() {
                for (prev in added) {
                    runShell(
                        "su -c 'ip route del ${prev.destination} via ${prev.gateway} " +
                            "dev ${prev.interfaceName}' 2>&1"
                    )
                }
            }
            for (subnet in pending) {
                removeTrackedFor(subnet)
                if (routeExistsAny(subnet)) {
                    rollback()
                    withContext(Dispatchers.Main) {
                        result.error("conflicto_ruta",
                            "Ya existe una ruta para $subnet en otra interfaz. Revísala antes de continuar.",
                            null)
                    }
                    return@launch
                }
                val cmd = "su -c 'ip route add $subnet via $gw dev $iface' 2>&1"
                val r = runShell(cmd)
                if (r.first != 0 || !routeExists(subnet, gw, iface)) {
                    rollback()
                    withContext(Dispatchers.Main) {
                        result.error("error_tunel_dividido",
                            "Error en ruta $subnet. Se revirtieron los cambios.", null)
                    }
                    return@launch
                }
                added.add(TrackedRoute(subnet, gw, iface))
            }
            synchronized(routeLock) {
                for (route in added) {
                    if (trackedRoutes.none {
                            it.destination == route.destination &&
                                it.gateway == route.gateway &&
                                it.interfaceName == route.interfaceName
                        }) {
                        trackedRoutes.add(route)
                    }
                }
            }
            withContext(Dispatchers.Main) {
                result.success("Túnel dividido habilitado exitosamente. ${added.size} ruta(s) agregada(s).")
            }
        }
    }

    private fun handleDisableSplit(result: MethodChannel.Result) {
        CoroutineScope(Dispatchers.IO).launch {
            val current = synchronized(routeLock) { ArrayList(trackedRoutes) }
            if (current.isEmpty()) {
                withContext(Dispatchers.Main) {
                    result.success("No hay rutas de túnel dividido activas.")
                }
                return@launch
            }
            val msgs = mutableListOf<String>()
            val failed = mutableListOf<TrackedRoute>()
            for (route in current) {
                val r = runShell(
                    "su -c 'ip route del ${route.destination} via ${route.gateway} " +
                        "dev ${route.interfaceName}' 2>&1"
                )
                val alreadyGone = r.second.contains("no such process", ignoreCase = true) ||
                    r.second.contains("not in table", ignoreCase = true)
                val gone = r.first == 0 || alreadyGone ||
                    !routeExists(route.destination, route.gateway, route.interfaceName)
                if (gone) {
                    msgs.add("Ruta ${route.destination} eliminada.")
                } else {
                    failed.add(route)
                    msgs.add("Error al eliminar ${route.destination}: ${r.second.take(120)}")
                }
            }
            synchronized(routeLock) {
                trackedRoutes.clear()
                trackedRoutes.addAll(failed)
            }
            withContext(Dispatchers.Main) {
                if (failed.isEmpty()) {
                    result.success(msgs.joinToString(" "))
                } else {
                    result.error("error_comando", msgs.joinToString(" "), null)
                }
            }
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
                val network = active ?: cm.allNetworks.firstOrNull { candidate ->
                    cm.getNetworkCapabilities(candidate)
                        ?.hasTransport(NetworkCapabilities.TRANSPORT_WIFI) == true
                }
                val props = network?.let { cm.getLinkProperties(it) }
                if (props != null) {
                    out["interfaceName"] = props.interfaceName ?: ""
                    val defaultRoute = props.routes.firstOrNull {
                        it.isDefaultRoute && it.gateway != null &&
                            !ipUnspecified(it.gateway?.hostAddress ?: "")
                    }
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
        if (!isSafeIpv4(gw) || !safeInterface.matches(iface) ||
            subnets.any { !isSafeCidr(it.trim()) }
        ) {
            result.error("argumento_invalido", "Parámetros de verificación inválidos", null)
            return
        }
        CoroutineScope(Dispatchers.IO).launch {
            val missing = mutableListOf<String>()
            for (rawSubnet in subnets) {
                val subnet = rawSubnet.trim()
                if (subnet.isEmpty()) continue
                if (!routeExists(subnet, gw, iface)) {
                    missing.add(subnet)
                }
            }
            withContext(Dispatchers.Main) { result.success(missing) }
        }
    }

    // ============================================================
    // RDP Launcher
    // ============================================================
    private fun externalRdpHandlers(intent: Intent): List<ResolveInfo> {
        val matches = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            packageManager.queryIntentActivities(intent,
                PackageManager.ResolveInfoFlags.of(0))
        } else {
            @Suppress("DEPRECATION")
            packageManager.queryIntentActivities(intent, 0)
        }
        return matches.filter { it.activityInfo.packageName != packageName }
    }

    private fun handlePreLaunch(result: MethodChannel.Result) {
        val testIntent = Intent(Intent.ACTION_VIEW, Uri.parse("rdp://example.com:3389"))
        if (externalRdpHandlers(testIntent).isNotEmpty()) {
            result.success(true)
            return
        }
        result.error("sin_manejador_rdp",
            "Instala Microsoft Remote Desktop (o cliente RDP) desde Play Store.", null)
    }

    private fun handleRdpAvailable(result: MethodChannel.Result) {
        val testIntent = Intent(Intent.ACTION_VIEW, Uri.parse("rdp://example.com:3389"))
        result.success(externalRdpHandlers(testIntent).isNotEmpty())
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
                val userInfo = buildString {
                    if (domain.isNotBlank()) append(domain).append('\\')
                    if (username.isNotBlank()) append(username)
                }
                if (userInfo.isNotEmpty()) {
                    append(percentEncode(userInfo)).append("@")
                }
                append("${percentEncode(host)}:$port")
            }
        }
        val intent = Intent(Intent.ACTION_VIEW, Uri.parse(uri))
        intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
        val handlers = externalRdpHandlers(intent)
        if (handlers.isEmpty()) {
            result.error("sin_manejador_rdp",
                "Instala Microsoft Remote Desktop (o cliente RDP) desde Play Store.", null)
            return
        }
        val launchIntent = if (handlers.size == 1) {
            Intent(intent).setPackage(handlers.first().activityInfo.packageName)
        } else {
            Intent.createChooser(intent, "Selecciona cliente RDP")
                .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
        }
        try {
            startActivity(launchIntent)
            result.success("Conexión RDP lanzada a $host:$port correctamente.")
        } catch (t: Throwable) {
            result.error("lanzamiento_fallido",
                "No se pudo lanzar cliente RDP: ${t.message}", null)
        }
    }
}
