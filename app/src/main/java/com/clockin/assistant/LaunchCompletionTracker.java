package com.clockin.assistant;

import android.content.Context;
import android.content.SharedPreferences;

/**
 * Persists one scheduled launch until accessibility confirms WeCom is visible.
 *
 * <p>The persistent notification is intentionally not cancelled when an
 * activity launch request merely returns successfully. OEM firmware can accept
 * that request and still block the target app behind a lock screen.</p>
 */
public final class LaunchCompletionTracker {
    private static final String KEY_PENDING = "launch_pending";
    private static final String KEY_PENDING_TYPE = "launch_pending_type";
    private static final String KEY_PENDING_EPOCH_DAY = "launch_pending_epoch_day";
    private static final String KEY_PENDING_TEST = "launch_pending_test";
    private static final String KEY_PENDING_STARTED_AT = "launch_pending_started_at";

    private LaunchCompletionTracker() {
    }

    public static void begin(
            Context context,
            int type,
            long epochDay,
            boolean test
    ) {
        AlarmScheduler.preferences(context)
                .edit()
                .putBoolean(KEY_PENDING, true)
                .putInt(KEY_PENDING_TYPE, type)
                .putLong(KEY_PENDING_EPOCH_DAY, epochDay)
                .putBoolean(KEY_PENDING_TEST, test)
                .putLong(KEY_PENDING_STARTED_AT, System.currentTimeMillis())
                .apply();
    }

    public static boolean isPending(Context context) {
        return AlarmScheduler.preferences(context)
                .getBoolean(KEY_PENDING, false);
    }

    public static boolean isPendingFor(
            Context context,
            int type,
            long epochDay
    ) {
        SharedPreferences prefs = AlarmScheduler.preferences(context);
        return prefs.getBoolean(KEY_PENDING, false)
                && prefs.getInt(KEY_PENDING_TYPE, -1) == type
                && prefs.getLong(KEY_PENDING_EPOCH_DAY, Long.MIN_VALUE)
                == epochDay;
    }

    public static void confirmWeComVisible(Context context) {
        SharedPreferences prefs = AlarmScheduler.preferences(context);
        if (!prefs.getBoolean(KEY_PENDING, false)) {
            return;
        }

        int type = prefs.getInt(
                KEY_PENDING_TYPE,
                AlarmScheduler.TYPE_MORNING
        );
        long epochDay = prefs.getLong(KEY_PENDING_EPOCH_DAY, 0L);
        boolean test = prefs.getBoolean(KEY_PENDING_TEST, false);
        NotificationHelper.cancelAlarm(context, type, epochDay, test);
        prefs.edit()
                .remove(KEY_PENDING)
                .remove(KEY_PENDING_TYPE)
                .remove(KEY_PENDING_EPOCH_DAY)
                .remove(KEY_PENDING_TEST)
                .remove(KEY_PENDING_STARTED_AT)
                .apply();
        AlarmScheduler.recordTrigger(
                context,
                context.getString(R.string.log_wecom_visible_confirmed)
        );
    }
}
