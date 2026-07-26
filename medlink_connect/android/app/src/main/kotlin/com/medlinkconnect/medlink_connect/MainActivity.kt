package com.medlinkconnect.medlink_connect

import android.content.Intent
import android.net.Uri
import io.flutter.embedding.android.FlutterActivity

class MainActivity: FlutterActivity() {
    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        
        // Handle RDP deep links
        if (intent.action == Intent.ACTION_VIEW) {
            val uri = intent.data
            if (uri != null && (uri.scheme == "rdp" || uri.scheme == "ms-rd-web")) {
                // Forward to Flutter channel
                val channel = "com.medlinkconnect/rdp_launcher"
                val method = "handleDeepLink"
                val args = mapOf("uri" to uri.toString())
                // Handle in Flutter
            }
        }
    }
}
