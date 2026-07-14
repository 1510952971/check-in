package com.clockin.assistant;

import android.content.BroadcastReceiver;
import android.content.Context;
import android.content.Intent;
import android.content.SharedPreferences;

public class AlarmWatchdogReceiver extends BroadcastReceiver {
    private static final long RECENT_TRIGGER_WINDOW_MILLIS = 2 * 60 * 1_000L;

    @Override
    public void onReceive(Context context, Intent intent) {
        if (!AlarmScheduler.isEnabled(context)) {
            return;
        }

        int type = intent.getIntExtra(
                AlarmScheduler.EXTRA_TYPE,
                AlarmScheduler.TYPE_MORNING
        );
        long epochDay = intent.getLongExtra(AlarmScheduler.EXTRA_EPOCH_DAY, 0L);
        SharedPreferences prefs = AlarmScheduler.preferences(context);
        long firedAt = prefs.getLong(AlarmScheduler.markerKey(type, epochDay), 0L);
        long age = Math.abs(System.currentTimeMillis() - firedAt);

        if (firedAt == 0L || age > RECENT_TRIGGER_WINDOW_MILLIS) {
            if (!LaunchCompletionTracker.isPendingFor(context, type, epochDay)) {
                LaunchCompletionTracker.begin(context, type, epochDay, false);
            }
            NotificationHelper.showAlarm(
                    context,
                    type,
                    epochDay,
                    false,
                    false
            );
            boolean launched = ClockInAccessibilityService.launchTrigger(
                    context,
                    type,
                    epochDay,
                    false
            );
            if (launched) {
                AlarmScheduler.recordTrigger(
                        context,
                        context.getString(R.string.log_watchdog_launch_sent)
                );
            } else {
                AlarmScheduler.recordTrigger(
                        context,
                        context.getString(R.string.log_watchdog_notification)
                );
                NotificationHelper.showAlarm(
                        context,
                        type,
                        epochDay,
                        false,
                        true
                );
            }
        }

        PendingResult pendingResult = goAsync();
        new Thread(() -> {
            try {
                AlarmScheduler.scheduleAll(context.getApplicationContext());
            } finally {
                pendingResult.finish();
            }
        }, "clock-in-reschedule").start();
    }
}
