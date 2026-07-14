package com.clockin.assistant;

import android.Manifest;
import android.app.Notification;
import android.app.NotificationChannel;
import android.app.NotificationManager;
import android.app.PendingIntent;
import android.content.Context;
import android.content.Intent;
import android.content.pm.PackageManager;
import android.graphics.Color;
import android.os.Build;
import android.os.Bundle;

public final class NotificationHelper {
    private static final String CHANNEL_ID = "clock_in_alarm";

    private NotificationHelper() {
    }

    public static void ensureChannel(Context context) {
        NotificationManager manager = context.getSystemService(NotificationManager.class);
        if (manager == null) {
            return;
        }
        NotificationChannel channel = new NotificationChannel(
                CHANNEL_ID,
                context.getString(R.string.alarm_channel_name),
                NotificationManager.IMPORTANCE_HIGH
        );
        channel.setDescription(context.getString(R.string.alarm_channel_description));
        channel.enableVibration(true);
        channel.enableLights(true);
        channel.setLightColor(Color.rgb(8, 126, 120));
        channel.setLockscreenVisibility(Notification.VISIBILITY_PUBLIC);
        manager.createNotificationChannel(channel);
    }

    public static boolean canPostNotifications(Context context) {
        if (Build.VERSION.SDK_INT >= 33) {
            return context.checkSelfPermission(Manifest.permission.POST_NOTIFICATIONS)
                    == PackageManager.PERMISSION_GRANTED;
        }
        NotificationManager manager = context.getSystemService(NotificationManager.class);
        return manager == null || manager.areNotificationsEnabled();
    }

    public static boolean canUseFullScreenIntent(Context context) {
        if (Build.VERSION.SDK_INT < 34) {
            return true;
        }
        NotificationManager manager = context.getSystemService(NotificationManager.class);
        return manager != null && manager.canUseFullScreenIntent();
    }

    public static void showAlarm(
            Context context,
            int type,
            long epochDay
    ) {
        showAlarm(context, type, epochDay, false, true);
    }

    public static void showAlarm(
            Context context,
            int type,
            long epochDay,
            boolean test,
            boolean fullScreen
    ) {
        if (!canPostNotifications(context)) {
            return;
        }
        ensureChannel(context);

        Intent triggerIntent = new Intent(context, TriggerActivity.class)
                .setAction("com.clockin.assistant.NOTIFICATION." + type + "." + epochDay)
                .putExtra(AlarmScheduler.EXTRA_TYPE, type)
                .putExtra(AlarmScheduler.EXTRA_EPOCH_DAY, epochDay)
                .putExtra(AlarmScheduler.EXTRA_TEST, test)
                .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK | Intent.FLAG_ACTIVITY_CLEAR_TOP);
        int flags = PendingIntent.FLAG_UPDATE_CURRENT | PendingIntent.FLAG_IMMUTABLE;
        Bundle options = AlarmScheduler.creatorActivityOptions();
        PendingIntent openIntent;
        if (options != null) {
            openIntent = PendingIntent.getActivity(
                    context,
                    notificationRequestCode(type, epochDay, test),
                    triggerIntent,
                    flags,
                    options
            );
        } else {
            openIntent = PendingIntent.getActivity(
                    context,
                    notificationRequestCode(type, epochDay, test),
                    triggerIntent,
                    flags
            );
        }

        String title = context.getString(
                test
                        ? R.string.test_notification_title
                        : type == AlarmScheduler.TYPE_MORNING
                                ? R.string.morning_notification_title
                                : R.string.evening_notification_title
        );
        Notification.Builder builder = new Notification.Builder(context, CHANNEL_ID)
                .setSmallIcon(R.drawable.ic_notification)
                .setContentTitle(title)
                .setContentText(context.getString(R.string.notification_text))
                .setCategory(Notification.CATEGORY_ALARM)
                .setVisibility(Notification.VISIBILITY_PUBLIC)
                .setPriority(Notification.PRIORITY_MAX)
                .setAutoCancel(false)
                .setOngoing(true)
                .setContentIntent(openIntent)
                .setOnlyAlertOnce(!fullScreen);
        if (fullScreen) {
            builder.setFullScreenIntent(openIntent, true);
        }
        Notification notification = builder.build();

        NotificationManager manager = context.getSystemService(NotificationManager.class);
        if (manager == null) {
            return;
        }
        try {
            manager.notify(notificationId(type, epochDay, test), notification);
        } catch (SecurityException ignored) {
            // The settings screen will continue showing that notification access is missing.
        }
    }

    public static void cancelAlarm(Context context, int type, long epochDay) {
        cancelAlarm(context, type, epochDay, false);
    }

    public static void cancelAlarm(
            Context context,
            int type,
            long epochDay,
            boolean test
    ) {
        NotificationManager manager = context.getSystemService(NotificationManager.class);
        if (manager != null) {
            manager.cancel(notificationId(type, epochDay, test));
        }
    }

    private static int notificationRequestCode(
            int type,
            long epochDay,
            boolean test
    ) {
        return AlarmScheduler.requestCode(type, epochDay, false)
                + 10_000
                + (test ? 900_000 : 0);
    }

    private static int notificationId(
            int type,
            long epochDay,
            boolean test
    ) {
        return 1_000
                + AlarmScheduler.requestCode(type, epochDay, false)
                + (test ? 900_000 : 0);
    }
}
