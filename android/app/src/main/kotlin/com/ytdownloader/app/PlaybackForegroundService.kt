package com.ytdownloader.app

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.Service
import android.content.Context
import android.content.Intent
import android.os.Build
import android.os.IBinder
import androidx.core.app.NotificationCompat

class PlaybackForegroundService : Service() {
    override fun onBind(intent: Intent?): IBinder? = null

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        ensureChannel()
        startForeground(NOTIFICATION_ID, buildNotification())
        return START_STICKY
    }

    private fun buildNotification(): Notification {
        return NotificationCompat.Builder(this, CHANNEL_ID)
            .setSmallIcon(R.mipmap.ic_launcher)
            .setContentTitle("yt-dlp")
            .setContentText("Playing in background")
            .setOngoing(true)
            .setOnlyAlertOnce(true)
            .build()
    }

    private fun ensureChannel() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) {
            return
        }
        val manager =
            getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        val channel = NotificationChannel(
            CHANNEL_ID,
            "Background Playback",
            NotificationManager.IMPORTANCE_LOW,
        )
        channel.description = "Keeps playback running when the app is backgrounded"
        manager.createNotificationChannel(channel)
    }

    companion object {
        private const val CHANNEL_ID = "yt_dlp_playback"
        private const val NOTIFICATION_ID = 42002

        fun start(context: Context) {
            val intent = Intent(context, PlaybackForegroundService::class.java)
            androidx.core.content.ContextCompat.startForegroundService(
                context,
                intent,
            )
        }

        fun stop(context: Context) {
            context.stopService(Intent(context, PlaybackForegroundService::class.java))
        }
    }
}
