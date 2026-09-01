package com.example.hoza_send

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Context
import android.content.Intent
import android.content.pm.ServiceInfo
import android.os.Build
import android.os.IBinder
import androidx.core.app.NotificationCompat
import androidx.core.app.ServiceCompat

/**
 * Keeps HozaSend running while a session is live and the app is not on screen.
 *
 * The Wi-Fi locks MainActivity holds keep the *radio* awake. They do nothing
 * about the *process*: Android freezes an app's threads and sockets shortly
 * after its last activity stops, so a user who switches away mid-transfer -
 * to answer a message, to check the time - comes back to a connection that
 * died while they were gone. On a small file nobody notices. On a four
 * gigabyte one it is the difference between the feature working and not.
 *
 * A foreground service is the only sanctioned way to say "this process has
 * work the user asked for". The price is a notification the user cannot
 * dismiss, which is the right price: something is using their network and
 * their battery, and they should be able to see it and get back to it.
 *
 * Deliberately not sticky. If Android kills this under memory pressure the
 * TCP session is gone with it, and restarting the service alone would put up
 * a notification for a transfer that is no longer happening.
 */
class TransferService : Service() {

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        if (intent?.action == ACTION_STOP) {
            stop()
            return START_NOT_STICKY
        }

        val title = intent?.getStringExtra(EXTRA_TITLE) ?: "HozaSend"
        val text = intent?.getStringExtra(EXTRA_TEXT).orEmpty()
        // Below zero means "no measurable progress yet" - connected, or
        // waiting on the other user - which reads as an indeterminate bar
        // rather than a stalled one at 0%.
        val progress = intent?.getIntExtra(EXTRA_PROGRESS, -1) ?: -1

        try {
            ServiceCompat.startForeground(
                this,
                NOTIFICATION_ID,
                buildNotification(title, text, progress),
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                    ServiceInfo.FOREGROUND_SERVICE_TYPE_DATA_SYNC
                } else {
                    0
                },
            )
        } catch (error: Exception) {
            // Android 12 and later refuse a foreground service started from
            // the background, and Android 14 is stricter again. A refusal is
            // not fatal: the transfer carries on exactly as it did before this
            // service existed, and only loses its protection from being
            // frozen. Crashing the app over it would be far worse.
            stop()
        }
        return START_NOT_STICKY
    }

    /**
     * The user swiped HozaSend out of the recents list.
     *
     * The Dart isolate goes with it, and the session with that, so there is
     * nothing left for this notification to describe. Without this it would
     * sit there advertising a transfer that stopped the moment the task did.
     */
    override fun onTaskRemoved(rootIntent: Intent?) {
        stop()
        super.onTaskRemoved(rootIntent)
    }

    private fun stop() {
        ServiceCompat.stopForeground(this, ServiceCompat.STOP_FOREGROUND_REMOVE)
        stopSelf()
    }

    private fun buildNotification(
        title: String,
        text: String,
        progress: Int,
    ): Notification {
        createChannel()

        // Tapping it comes back to the transfer rather than to a fresh copy of
        // the app: singleTop plus CLEAR_TOP means the existing activity is
        // brought forward with whatever was on screen still there.
        val open = Intent(this, MainActivity::class.java).apply {
            flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP
        }
        val pending = PendingIntent.getActivity(
            this,
            0,
            open,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )

        val builder = NotificationCompat.Builder(this, CHANNEL_ID)
            .setContentTitle(title)
            .setContentText(text)
            .setSmallIcon(android.R.drawable.stat_sys_upload)
            .setContentIntent(pending)
            .setOngoing(true)
            // The transfer screen is the place to act; this is a status line,
            // and it should not buzz a phone that is already in the user's
            // hand every time the percentage moves.
            .setSilent(true)
            .setPriority(NotificationCompat.PRIORITY_LOW)
            .setCategory(NotificationCompat.CATEGORY_PROGRESS)
            // Nothing here is private - a device name and a percentage - but
            // there is no reason for it to be readable from a locked screen.
            .setVisibility(NotificationCompat.VISIBILITY_SECRET)

        if (progress in 0..100) {
            builder.setProgress(100, progress, false)
        } else {
            builder.setProgress(0, 0, true)
        }
        return builder.build()
    }

    private fun createChannel() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return
        val manager = getSystemService(Context.NOTIFICATION_SERVICE)
            as? NotificationManager ?: return
        if (manager.getNotificationChannel(CHANNEL_ID) != null) return

        // Separate from the "Transfers" channel the alerts use, and quieter.
        // One channel for "something happened" and one for "something is
        // happening" lets a user silence either without losing the other.
        val channel = NotificationChannel(
            CHANNEL_ID,
            "Active session",
            NotificationManager.IMPORTANCE_LOW,
        ).apply {
            description = "Shown while a transfer is in progress"
            setShowBadge(false)
            enableVibration(false)
        }
        manager.createNotificationChannel(channel)
    }

    companion object {
        const val ACTION_STOP = "com.example.hoza_send.STOP_SESSION"
        const val EXTRA_TITLE = "title"
        const val EXTRA_TEXT = "text"
        const val EXTRA_PROGRESS = "progress"

        private const val CHANNEL_ID = "session"

        /** Distinct from the alert notification ids, which live in Dart. */
        private const val NOTIFICATION_ID = 42
    }
}
