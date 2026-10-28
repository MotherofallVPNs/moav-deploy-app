package org.motherofallvpns.moavdeploy

import android.app.Activity
import android.content.ComponentName
import android.content.Context
import android.content.pm.PackageManager
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodChannel

/**
 * Switches the launcher identity between the two predeclared aliases.
 *
 * `.MoavLauncher` (label "MoaV Deploy", MoaV icon, targets MainActivity) is
 * enabled by default; `.NotesLauncher` (label "Notes", Notes icon, targets
 * DecoyActivity) is disabled in the manifest. Enabling one and disabling the
 * other is all the platform needs: the launcher re-reads the package and
 * shows the enabled entry. The new entry is always enabled before the old one
 * is disabled so there is never a moment with no launcher entry at all.
 */
object DecoyChannel {
    const val NAME = "org.motherofallvpns.moavdeploy/decoy"

    private fun moav(context: Context) =
        ComponentName(context, "org.motherofallvpns.moavdeploy.MoavLauncher")

    private fun notes(context: Context) =
        ComponentName(context, "org.motherofallvpns.moavdeploy.NotesLauncher")

    fun register(activity: Activity, messenger: BinaryMessenger) {
        MethodChannel(messenger, NAME).setMethodCallHandler { call, result ->
            try {
                when (call.method) {
                    "capabilities" -> result.success(
                        mapOf("renameLauncher" to true, "switchIcon" to true)
                    )
                    "getIdentity" -> result.success(
                        if (isNotes(activity)) "notes" else "moav"
                    )
                    "setIdentity" -> {
                        val notes = call.argument<Boolean>("notes") ?: false
                        apply(activity, notes)
                        result.success(true)
                    }
                    "closeApp" -> {
                        result.success(true)
                        activity.finishAndRemoveTask()
                    }
                    else -> result.notImplemented()
                }
            } catch (e: RuntimeException) {
                result.error("decoy", e.javaClass.simpleName, null)
            }
        }
    }

    /** True when the Notes alias is the enabled launcher entry. */
    fun isNotes(context: Context): Boolean {
        val pm = context.packageManager
        return isEnabled(pm, notes(context), manifestDefault = false) &&
            !isEnabled(pm, moav(context), manifestDefault = true)
    }

    /** Makes exactly one alias the launcher entry. Idempotent. */
    fun apply(context: Context, notes: Boolean) {
        val pm = context.packageManager
        val on = if (notes) notes(context) else moav(context)
        val off = if (notes) moav(context) else notes(context)
        set(pm, on, PackageManager.COMPONENT_ENABLED_STATE_ENABLED)
        set(pm, off, PackageManager.COMPONENT_ENABLED_STATE_DISABLED)
    }

    private fun isEnabled(
        pm: PackageManager,
        component: ComponentName,
        manifestDefault: Boolean,
    ): Boolean = when (pm.getComponentEnabledSetting(component)) {
        PackageManager.COMPONENT_ENABLED_STATE_ENABLED -> true
        PackageManager.COMPONENT_ENABLED_STATE_DISABLED -> false
        else -> manifestDefault
    }

    private fun set(pm: PackageManager, component: ComponentName, state: Int) {
        if (pm.getComponentEnabledSetting(component) == state) return
        pm.setComponentEnabledSetting(component, state, PackageManager.DONT_KILL_APP)
    }
}
