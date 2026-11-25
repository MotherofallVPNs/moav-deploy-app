package org.motherofallvpns.moavdeploy

import android.content.ActivityNotFoundException
import android.content.Intent
import android.content.pm.PackageManager
import android.content.pm.Signature
import android.net.Uri
import android.os.Build
import android.provider.Settings
import io.flutter.embedding.android.FlutterFragmentActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.security.MessageDigest

// open: DecoyActivity (disguise mode) is this activity under another theme.
open class MainActivity : FlutterFragmentActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        DecoyChannel.register(this, flutterEngine.dartExecutor.binaryMessenger)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, SIGNING_CHANNEL)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "signingFingerprints" -> result.success(signingFingerprints())
                    else -> result.notImplemented()
                }
            }
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, SETTINGS_CHANNEL)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "openAppSettings" -> result.success(openAppSettings())
                    else -> result.notImplemented()
                }
            }
    }

    /** Opens this app's "App info" page in system Settings; false if no activity handles it. */
    private fun openAppSettings(): Boolean =
        try {
            startActivity(
                Intent(
                    Settings.ACTION_APPLICATION_DETAILS_SETTINGS,
                    Uri.fromParts("package", packageName, null),
                ).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            )
            true
        } catch (e: ActivityNotFoundException) {
            false
        }

    /** SHA-256 of each signing certificate, colon-separated as keytool and Play Console print it. */
    private fun signingFingerprints(): List<String> =
        currentSigners().map { sig ->
            MessageDigest.getInstance("SHA-256")
                .digest(sig.toByteArray())
                .joinToString(":") { "%02X".format(it) }
        }

    @Suppress("DEPRECATION")
    private fun currentSigners(): List<Signature> {
        val pm = packageManager
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
            val info = pm.getPackageInfo(packageName, PackageManager.GET_SIGNING_CERTIFICATES)
            // Current signers only, not the rotation history (what apksigner verifies).
            return info.signingInfo?.apkContentsSigners?.toList() ?: emptyList()
        }
        return pm.getPackageInfo(packageName, PackageManager.GET_SIGNATURES)
            .signatures?.toList() ?: emptyList()
    }

    companion object {
        // Mirrored in lib/core/app_identity.dart.
        const val SIGNING_CHANNEL = "org.motherofallvpns.moavdeploy/signing"

        // Mirrored in lib/core/app_settings.dart.
        const val SETTINGS_CHANNEL = "org.motherofallvpns.moavdeploy/settings"
    }
}
