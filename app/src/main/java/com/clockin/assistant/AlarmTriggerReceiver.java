package com.clockin.assistant;

import android.content.BroadcastReceiver;
import android.content.Context;
import android.content.Intent;
import android.os.PowerManager;

public class AlarmTriggerReceiver extends BroadcastReceiver {
    @Override
    public void onReceive(Context context, Intent intent) {
        if (!AlarmScheduler.isEnabled(context)) {
            return;
        }

        int type = intent.getIntExtra(
                AlarmScheduler.EXTRA_TYPE,
                AlarmScheduler.TYPE_MORNING
        );
        long epochDay = intent.getLongExtra(
                AlarmScheduler.EXTRA_EPOCH_DAY,
                0L
        );
        boolean test = intent.getBooleanExtra(AlarmScheduler.EXTRA_TEST, false);

        PowerManager manager = context.getSystemService(PowerManager.class);
        PowerManager.WakeLock wakeLock = null;
        if (manager != null) {
            wakeLock = manager.newWakeLock(
                    PowerManager.PARTIAL_WAKE_LOCK,
                    "clockin:alarm-trigger"
            );
            wakeLock.acquire(10_000L);
        }

        try {
            AlarmScheduler.recordTrigger(
                    context,
                    context.getString(
                            test
                                    ? R.string.log_test_alarm_received
                            : R.string.log_alarm_received
                    )
            );
            LaunchCompletionTracker.begin(context, type, epochDay, test);
            NotificationHelper.showAlarm(
                    context,
                    type,
                    epochDay,
                    test,
                    false
            );
            boolean launched = ClockInAccessibilityService.launchTrigger(
                    context,
                    type,
                    epochDay,
                    test
            );
            if (launched) {
                AlarmScheduler.recordTrigger(
                        context,
                        context.getString(R.string.log_accessibility_launch_sent)
                );
            } else {
                AlarmScheduler.recordTrigger(
                        context,
                        context.getString(R.string.log_accessibility_missing)
                );
                NotificationHelper.showAlarm(
                        context,
                        type,
                        epochDay,
                        test,
                        true
                );
            }
        } finally {
            if (wakeLock != null && wakeLock.isHeld()) {
                wakeLock.release();
            }
        }
    }
}
