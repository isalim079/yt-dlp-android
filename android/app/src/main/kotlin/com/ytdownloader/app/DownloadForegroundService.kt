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

class DownloadForegroundService : Service() {
    override fun onBind(intent: Intent?): IBinder? = null

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        val activeCount = intent?.getIntExtra(EXTRA_ACTIVE_COUNT, 1) ?: 1
        ensureChannel()
        startForeground(NOTIFICATION_ID, buildNotification(activeCount))
        return START_STICKY
    }

    private fun buildNotification(activeCount: Int): Notification {
        val text = if (activeCount > 1) {
            "$activeCount downloads running in background"
        } else {
            "Download running in background"
        }
        return NotificationCompat.Builder(this, CHANNEL_ID)
            .setSmallIcon(R.mipmap.ic_launcher)
            .setContentTitle("yt-dlp")
            .setContentText(text)
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
            "Background Downloads",
            NotificationManager.IMPORTANCE_LOW,
        )
        channel.description = "Keeps downloads running when app is backgrounded"
        manager.createNotificationChannel(channel)
    }

    companion object {
        private const val CHANNEL_ID = "yt_dlp_downloads"
        private const val NOTIFICATION_ID = 42001
        private const val EXTRA_ACTIVE_COUNT = "active_count"

        fun start(context: Context, activeCount: Int) {
            val intent = Intent(context, DownloadForegroundService::class.java)
            intent.putExtra(EXTRA_ACTIVE_COUNT, activeCount)
            androidx.core.content.ContextCompat.startForegroundService(
                context,
                intent,
            )
        }

        fun stop(context: Context) {
            context.stopService(Intent(context, DownloadForegroundService::class.java))
        }
    }
}
