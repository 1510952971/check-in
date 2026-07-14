package com.clockin.assistant;

import android.content.BroadcastReceiver;
import android.content.Context;
import android.content.Intent;

public class RescheduleReceiver extends BroadcastReceiver {
    private static final String ACTION_EXACT_ALARM_PERMISSION_CHANGED =
            "android.app.action.SCHEDULE_EXACT_ALARM_PERMISSION_STATE_CHANGED";

    @Override
    public void onReceive(Context context, Intent intent) {
        String action = intent.getAction();
        if (action == null || !isExpectedSystemAction(action)) {
            return;
        }
        PendingResult pendingResult = goAsync();
        new Thread(() -> {
            try {
                AlarmScheduler.scheduleAll(context.getApplicationContext());
            } finally {
                pendingResult.finish();
            }
        }, "clock-in-system-reschedule").start();
    }

    private boolean isExpectedSystemAction(String action) {
        return Intent.ACTION_BOOT_COMPLETED.equals(action)
                || Intent.ACTION_MY_PACKAGE_REPLACED.equals(action)
                || Intent.ACTION_TIMEZONE_CHANGED.equals(action)
                || Intent.ACTION_TIME_CHANGED.equals(action)
                || ACTION_EXACT_ALARM_PERMISSION_CHANGED.equals(action);
    }
}
