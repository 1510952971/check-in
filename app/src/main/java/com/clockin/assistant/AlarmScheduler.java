package com.clockin.assistant;

import android.app.ActivityOptions;
import android.app.AlarmManager;
import android.app.PendingIntent;
import android.content.Context;
import android.content.Intent;
import android.content.SharedPreferences;
import android.os.Build;
import android.os.Bundle;

import java.time.DayOfWeek;
import java.time.LocalDate;
import java.time.LocalTime;
import java.time.ZoneId;
import java.time.ZonedDateTime;
import java.util.concurrent.ExecutorService;
import java.util.concurrent.Executors;
import java.util.concurrent.atomic.AtomicBoolean;

public final class AlarmScheduler {
    public static final String PREFS = "clock_in_settings";
    public static final String KEY_ENABLED = "enabled";
    public static final String KEY_WEEKDAYS_ONLY = "weekdays_only";
    public static final String KEY_MORNING_HOUR = "morning_hour";
    public static final String KEY_MORNING_MINUTE = "morning_minute";
    public static final String KEY_EVENING_HOUR = "evening_hour";
    public static final String KEY_EVENING_MINUTE = "evening_minute";
    public static final String KEY_LAST_TRIGGER_AT = "last_trigger_at";
    public static final String KEY_LAST_TRIGGER_MESSAGE = "last_trigger_message";
    private static final String KEY_LONG_HORIZON_CLEANED = "long_horizon_cleaned";

    public static final String EXTRA_TYPE = "alarm_type";
    public static final String EXTRA_EPOCH_DAY = "epoch_day";
    public static final String EXTRA_TEST = "test_trigger";

    public static final int TYPE_MORNING = 1;
    public static final int TYPE_EVENING = 2;

    private static final String ACTION_PRIMARY = "com.clockin.assistant.PRIMARY.";
    private static final String ACTION_WATCHDOG = "com.clockin.assistant.WATCHDOG.";
    private static final String ACTION_TEST = "com.clockin.assistant.TEST.";
    private static final int EXACT_HORIZON_DAYS = 7;
    private static final int APPROXIMATE_HORIZON_DAYS = 2;
    private static final int LEGACY_CANCEL_HORIZON_DAYS = 60;
    private static final long WATCHDOG_DELAY_MILLIS = 5_000L;
    private static final ExecutorService SCHEDULER_EXECUTOR =
            Executors.newSingleThreadExecutor();
    private static final AtomicBoolean SCHEDULE_REQUESTED = new AtomicBoolean();
    private static final AtomicBoolean SCHEDULER_RUNNING = new AtomicBoolean();

    private AlarmScheduler() {
    }

    public static SharedPreferences preferences(Context context) {
        return context.getSharedPreferences(PREFS, Context.MODE_PRIVATE);
    }

    public static void ensureDefaults(Context context) {
        SharedPreferences prefs = preferences(context);
        if (!prefs.contains(KEY_ENABLED)) {
            prefs.edit()
                    .putBoolean(KEY_ENABLED, true)
                    .putBoolean(KEY_WEEKDAYS_ONLY, false)
                    .putInt(KEY_MORNING_HOUR, 8)
                    .putInt(KEY_MORNING_MINUTE, 33)
                    .putInt(KEY_EVENING_HOUR, 17)
                    .putInt(KEY_EVENING_MINUTE, 31)
                    .apply();
        }
    }

    public static boolean isEnabled(Context context) {
        return preferences(context).getBoolean(KEY_ENABLED, true);
    }

    public static boolean canScheduleExact(Context context) {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.S) {
            return true;
        }
        AlarmManager alarmManager = context.getSystemService(AlarmManager.class);
        return alarmManager != null && alarmManager.canScheduleExactAlarms();
    }

    public static synchronized void scheduleAll(Context context) {
        ensureDefaults(context);
        cancelKnownAlarms(context);
        if (!isEnabled(context)) {
            return;
        }

        SharedPreferences prefs = preferences(context);
        boolean weekdaysOnly = prefs.getBoolean(KEY_WEEKDAYS_ONLY, false);
        boolean exact = canScheduleExact(context);
        int horizon = exact ? EXACT_HORIZON_DAYS : APPROXIMATE_HORIZON_DAYS;
        long now = System.currentTimeMillis();
        LocalDate today = LocalDate.now();

        for (int offset = 0; offset <= horizon; offset++) {
            LocalDate date = today.plusDays(offset);
            if (weekdaysOnly && isWeekend(date)) {
                continue;
            }
            scheduleOccurrence(context, date, TYPE_MORNING, now, exact);
            scheduleOccurrence(context, date, TYPE_EVENING, now, exact);
        }
    }

    public static void scheduleAllAsync(Context context) {
        Context applicationContext = context.getApplicationContext();
        SCHEDULE_REQUESTED.set(true);
        if (!SCHEDULER_RUNNING.compareAndSet(false, true)) {
            return;
        }
        SCHEDULER_EXECUTOR.execute(() -> runScheduleLoop(applicationContext));
    }

    private static void runScheduleLoop(Context context) {
        try {
            while (SCHEDULE_REQUESTED.getAndSet(false)) {
                scheduleAll(context);
            }
        } finally {
            SCHEDULER_RUNNING.set(false);
            if (SCHEDULE_REQUESTED.get()) {
                scheduleAllAsync(context);
            }
        }
    }

    public static NextEvent getNextEvent(Context context) {
        ensureDefaults(context);
        if (!isEnabled(context)) {
            return null;
        }

        SharedPreferences prefs = preferences(context);
        boolean weekdaysOnly = prefs.getBoolean(KEY_WEEKDAYS_ONLY, false);
        long now = System.currentTimeMillis();
        LocalDate today = LocalDate.now();
        NextEvent best = null;

        for (int offset = 0; offset <= 8; offset++) {
            LocalDate date = today.plusDays(offset);
            if (weekdaysOnly && isWeekend(date)) {
                continue;
            }
            for (int type : new int[]{TYPE_MORNING, TYPE_EVENING}) {
                long triggerAt = triggerAtMillis(prefs, date, type);
                if (triggerAt > now && (best == null || triggerAt < best.triggerAtMillis)) {
                    best = new NextEvent(type, triggerAt);
                }
            }
        }
        return best;
    }

    public static String markerKey(int type, long epochDay) {
        return "fired_" + type + "_" + epochDay;
    }

    public static void recordTrigger(Context context, String message) {
        preferences(context)
                .edit()
                .putLong(KEY_LAST_TRIGGER_AT, System.currentTimeMillis())
                .putString(KEY_LAST_TRIGGER_MESSAGE, message)
                .apply();
    }

    public static long scheduleScreenOffTest(Context context) {
        long triggerAt = System.currentTimeMillis() + 60_000L;
        long epochDay = LocalDate.now().toEpochDay();
        Intent intent = new Intent(context, AlarmTriggerReceiver.class)
                .setAction(ACTION_TEST + triggerAt)
                .putExtra(EXTRA_TYPE, TYPE_MORNING)
                .putExtra(EXTRA_EPOCH_DAY, epochDay)
                .putExtra(EXTRA_TEST, true);
        PendingIntent operation = PendingIntent.getBroadcast(
                context,
                980_001,
                intent,
                PendingIntent.FLAG_UPDATE_CURRENT | PendingIntent.FLAG_IMMUTABLE
        );
        AlarmManager alarmManager = context.getSystemService(AlarmManager.class);
        if (alarmManager == null) {
            return 0L;
        }
        try {
            if (canScheduleExact(context)) {
                alarmManager.setAlarmClock(
                        new AlarmManager.AlarmClockInfo(triggerAt, showAppPendingIntent(context)),
                        operation
                );
            } else {
                alarmManager.setAndAllowWhileIdle(
                        AlarmManager.RTC_WAKEUP,
                        triggerAt,
                        operation
                );
            }
            recordTrigger(context, context.getString(R.string.log_test_scheduled));
            return triggerAt;
        } catch (SecurityException ignored) {
            alarmManager.setAndAllowWhileIdle(
                    AlarmManager.RTC_WAKEUP,
                    triggerAt,
                    operation
            );
            recordTrigger(context, context.getString(R.string.log_test_scheduled_approximate));
            return triggerAt;
        }
    }

    static Bundle creatorActivityOptions() {
        if (Build.VERSION.SDK_INT >= 35) {
            ActivityOptions options = ActivityOptions.makeBasic();
            options.setPendingIntentCreatorBackgroundActivityStartMode(
                    ActivityOptions.MODE_BACKGROUND_ACTIVITY_START_ALLOWED
            );
            return options.toBundle();
        }
        return null;
    }

    private static void scheduleOccurrence(
            Context context,
            LocalDate date,
            int type,
            long now,
            boolean exact
    ) {
        SharedPreferences prefs = preferences(context);
        long triggerAt = triggerAtMillis(prefs, date, type);
        if (triggerAt <= now + 1_000L) {
            return;
        }

        AlarmManager alarmManager = context.getSystemService(AlarmManager.class);
        if (alarmManager == null) {
            return;
        }

        long epochDay = date.toEpochDay();
        PendingIntent primary = primaryPendingIntent(context, type, epochDay);
        PendingIntent showApp = showAppPendingIntent(context);

        try {
            if (exact) {
                AlarmManager.AlarmClockInfo info =
                        new AlarmManager.AlarmClockInfo(triggerAt, showApp);
                alarmManager.setAlarmClock(info, primary);
            } else {
                alarmManager.setAndAllowWhileIdle(
                        AlarmManager.RTC_WAKEUP,
                        triggerAt,
                        primary
                );
            }
        } catch (SecurityException ignored) {
            alarmManager.setAndAllowWhileIdle(
                    AlarmManager.RTC_WAKEUP,
                    triggerAt,
                    primary
            );
        }

        PendingIntent watchdog = watchdogPendingIntent(context, type, epochDay);
        long watchdogAt = triggerAt + WATCHDOG_DELAY_MILLIS;
        try {
            if (exact) {
                alarmManager.setExactAndAllowWhileIdle(
                        AlarmManager.RTC_WAKEUP,
                        watchdogAt,
                        watchdog
                );
            } else {
                alarmManager.setAndAllowWhileIdle(
                        AlarmManager.RTC_WAKEUP,
                        watchdogAt,
                        watchdog
                );
            }
        } catch (SecurityException ignored) {
            alarmManager.setAndAllowWhileIdle(
                    AlarmManager.RTC_WAKEUP,
                    watchdogAt,
                    watchdog
            );
        }
    }

    private static void cancelKnownAlarms(Context context) {
        AlarmManager alarmManager = context.getSystemService(AlarmManager.class);
        if (alarmManager == null) {
            return;
        }

        SharedPreferences prefs = preferences(context);
        boolean needsLongCleanup =
                !prefs.getBoolean(KEY_LONG_HORIZON_CLEANED, false);
        int cancelHorizon = needsLongCleanup
                ? LEGACY_CANCEL_HORIZON_DAYS
                : EXACT_HORIZON_DAYS + 2;
        LocalDate start = LocalDate.now().minusDays(2);
        for (int offset = 0; offset <= cancelHorizon + 2; offset++) {
            long epochDay = start.plusDays(offset).toEpochDay();
            for (int type : new int[]{TYPE_MORNING, TYPE_EVENING}) {
                alarmManager.cancel(primaryPendingIntent(context, type, epochDay));
                alarmManager.cancel(legacyPrimaryActivityPendingIntent(
                        context,
                        type,
                        epochDay
                ));
                alarmManager.cancel(watchdogPendingIntent(context, type, epochDay));
            }
        }
        if (needsLongCleanup) {
            prefs.edit().putBoolean(KEY_LONG_HORIZON_CLEANED, true).apply();
        }
    }

    private static PendingIntent primaryPendingIntent(
            Context context,
            int type,
            long epochDay
    ) {
        Intent intent = new Intent(context, AlarmTriggerReceiver.class)
                .setAction(ACTION_PRIMARY + type + "." + epochDay)
                .putExtra(EXTRA_TYPE, type)
                .putExtra(EXTRA_EPOCH_DAY, epochDay);
        return PendingIntent.getBroadcast(
                context,
                requestCode(type, epochDay, false),
                intent,
                PendingIntent.FLAG_UPDATE_CURRENT | PendingIntent.FLAG_IMMUTABLE
        );
    }

    private static PendingIntent legacyPrimaryActivityPendingIntent(
            Context context,
            int type,
            long epochDay
    ) {
        Intent intent = new Intent(context, TriggerActivity.class)
                .setAction(ACTION_PRIMARY + type + "." + epochDay)
                .putExtra(EXTRA_TYPE, type)
                .putExtra(EXTRA_EPOCH_DAY, epochDay)
                .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK | Intent.FLAG_ACTIVITY_CLEAR_TOP);
        return PendingIntent.getActivity(
                context,
                requestCode(type, epochDay, false),
                intent,
                PendingIntent.FLAG_UPDATE_CURRENT | PendingIntent.FLAG_IMMUTABLE
        );
    }

    private static PendingIntent watchdogPendingIntent(
            Context context,
            int type,
            long epochDay
    ) {
        Intent intent = new Intent(context, AlarmWatchdogReceiver.class)
                .setAction(ACTION_WATCHDOG + type + "." + epochDay)
                .putExtra(EXTRA_TYPE, type)
                .putExtra(EXTRA_EPOCH_DAY, epochDay);
        return PendingIntent.getBroadcast(
                context,
                requestCode(type, epochDay, true),
                intent,
                PendingIntent.FLAG_UPDATE_CURRENT | PendingIntent.FLAG_IMMUTABLE
        );
    }

    static int requestCode(int type, long epochDay, boolean watchdog) {
        int dayPart = (int) Math.floorMod(epochDay, 70_000L);
        return dayPart + (type * 70_000) + (watchdog ? 280_000 : 0);
    }

    private static PendingIntent showAppPendingIntent(Context context) {
        return PendingIntent.getActivity(
                context,
                910_000,
                new Intent(context, MainActivity.class)
                        .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK | Intent.FLAG_ACTIVITY_CLEAR_TOP),
                PendingIntent.FLAG_UPDATE_CURRENT | PendingIntent.FLAG_IMMUTABLE
        );
    }

    private static long triggerAtMillis(
            SharedPreferences prefs,
            LocalDate date,
            int type
    ) {
        int hour = type == TYPE_MORNING
                ? prefs.getInt(KEY_MORNING_HOUR, 8)
                : prefs.getInt(KEY_EVENING_HOUR, 17);
        int minute = type == TYPE_MORNING
                ? prefs.getInt(KEY_MORNING_MINUTE, 33)
                : prefs.getInt(KEY_EVENING_MINUTE, 31);
        ZonedDateTime zoned = ZonedDateTime.of(
                date,
                LocalTime.of(hour, minute),
                ZoneId.systemDefault()
        );
        return zoned.toInstant().toEpochMilli();
    }

    private static boolean isWeekend(LocalDate date) {
        DayOfWeek day = date.getDayOfWeek();
        return day == DayOfWeek.SATURDAY || day == DayOfWeek.SUNDAY;
    }

    public static final class NextEvent {
        public final int type;
        public final long triggerAtMillis;

        NextEvent(int type, long triggerAtMillis) {
            this.type = type;
            this.triggerAtMillis = triggerAtMillis;
        }
    }
}
