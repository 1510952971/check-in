package com.clockin.assistant;

import android.Manifest;
import android.annotation.SuppressLint;
import android.app.Activity;
import android.app.Dialog;
import android.app.NotificationManager;
import android.content.Intent;
import android.content.SharedPreferences;
import android.content.pm.PackageManager;
import android.graphics.Color;
import android.graphics.Insets;
import android.graphics.drawable.ColorDrawable;
import android.net.Uri;
import android.os.Build;
import android.os.Bundle;
import android.os.Handler;
import android.os.Looper;
import android.os.PowerManager;
import android.provider.Settings;
import android.view.HapticFeedbackConstants;
import android.view.MotionEvent;
import android.view.View;
import android.view.Window;
import android.view.WindowInsets;
import android.view.WindowInsetsController;
import android.view.WindowManager;
import android.widget.Button;
import android.widget.NumberPicker;
import android.widget.RadioButton;
import android.widget.RadioGroup;
import android.widget.TextView;
import android.widget.Toast;

import com.clockin.assistant.ui.GlowToggleView;
import com.clockin.assistant.ui.MoodBackgroundView;
import com.clockin.assistant.ui.ShiftProgressView;

import java.time.Instant;
import java.time.LocalTime;
import java.time.ZoneId;
import java.time.format.DateTimeFormatter;
import java.util.Locale;

public class MainActivity extends Activity {
    private static final int REQUEST_NOTIFICATIONS = 1001;
    private static final String KEY_MOOD_TAG = "mood_tag";
    private static final long COUNTDOWN_WINDOW_MILLIS = 12 * 60 * 60 * 1_000L;

    private final Handler clockHandler = new Handler(Looper.getMainLooper());
    private final Runnable clockTicker = new Runnable() {
        @Override
        public void run() {
            if (prefs != null) {
                boolean enabled = AlarmScheduler.isEnabled(MainActivity.this);
                renderAmbientUi(enabled);
                renderNextRun(enabled);
            }
            clockHandler.postDelayed(this, 1_000L);
        }
    };

    private SharedPreferences prefs;
    private MoodBackgroundView moodBackground;
    private GlowToggleView enabledSwitch;
    private RadioButton dailyRadio;
    private RadioButton weekdaysRadio;
    private TextView greeting;
    private TextView headerStatus;
    private TextView moodBadge;
    private TextView morningTime;
    private TextView eveningTime;
    private TextView nextRun;
    private TextView countdown;
    private TextView lastTrigger;
    private TextView deviceProfile;
    private ShiftProgressView shiftProgress;
    private Button deviceSettingsButton;
    private Button checkUpdateButton;
    private TextView updateStatus;
    private GitHubUpdateManager updateManager;
    private boolean bindingUi;

    @Override
    protected void onCreate(Bundle savedInstanceState) {
        super.onCreate(savedInstanceState);
        getWindow().setStatusBarColor(Color.TRANSPARENT);
        getWindow().setNavigationBarColor(Color.rgb(10, 17, 25));
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            getWindow().setNavigationBarContrastEnforced(false);
        }
        setContentView(R.layout.activity_main);
        applySystemBarInsets();
        AlarmScheduler.ensureDefaults(this);
        NotificationHelper.ensureChannel(this);
        prefs = AlarmScheduler.preferences(this);

        bindViews();
        updateManager = new GitHubUpdateManager(
                this,
                updateStatus,
                checkUpdateButton
        );
        bindActions();
        renderSettings();
    }

    @Override
    protected void onResume() {
        super.onResume();
        if (prefs != null && AlarmScheduler.isEnabled(this)) {
            AlarmScheduler.scheduleAllAsync(this);
        }
        if (prefs != null) {
            renderSettings();
        }
        if (updateManager != null) {
            updateManager.onResume();
        }
        clockHandler.removeCallbacks(clockTicker);
        clockHandler.post(clockTicker);
    }

    @Override
    protected void onPause() {
        clockHandler.removeCallbacks(clockTicker);
        super.onPause();
    }

    @Override
    protected void onDestroy() {
        if (updateManager != null) {
            updateManager.destroy();
        }
        super.onDestroy();
    }

    @Override
    public void onRequestPermissionsResult(
            int requestCode,
            String[] permissions,
            int[] grantResults
    ) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults);
        if (requestCode == REQUEST_NOTIFICATIONS) {
            renderSettings();
        }
    }

    private void bindViews() {
        moodBackground = findViewById(R.id.mood_background);
        enabledSwitch = findViewById(R.id.switch_enabled);
        dailyRadio = findViewById(R.id.radio_daily);
        weekdaysRadio = findViewById(R.id.radio_weekdays);
        greeting = findViewById(R.id.text_greeting);
        headerStatus = findViewById(R.id.text_header_status);
        moodBadge = findViewById(R.id.text_mood_badge);
        morningTime = findViewById(R.id.text_morning_time);
        eveningTime = findViewById(R.id.text_evening_time);
        nextRun = findViewById(R.id.text_next_run);
        countdown = findViewById(R.id.text_countdown);
        lastTrigger = findViewById(R.id.text_last_trigger);
        deviceProfile = findViewById(R.id.text_device_profile);
        shiftProgress = findViewById(R.id.shift_progress);
        deviceSettingsButton = findViewById(R.id.button_device_settings);
        checkUpdateButton = findViewById(R.id.button_check_update);
        updateStatus = findViewById(R.id.text_update_status);
    }

    @SuppressWarnings("deprecation")
    private void applySystemBarInsets() {
        View scroll = findViewById(R.id.main_scroll);
        int initialLeft = scroll.getPaddingLeft();
        int initialTop = scroll.getPaddingTop();
        int initialRight = scroll.getPaddingRight();
        int initialBottom = scroll.getPaddingBottom();
        scroll.setOnApplyWindowInsetsListener((view, windowInsets) -> {
            int left;
            int top;
            int right;
            int bottom;
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
                Insets bars = windowInsets.getInsets(WindowInsets.Type.systemBars());
                left = bars.left;
                top = bars.top;
                right = bars.right;
                bottom = bars.bottom;
            } else {
                left = windowInsets.getSystemWindowInsetLeft();
                top = windowInsets.getSystemWindowInsetTop();
                right = windowInsets.getSystemWindowInsetRight();
                bottom = windowInsets.getSystemWindowInsetBottom();
            }
            view.setPadding(
                    initialLeft + left,
                    initialTop + top,
                    initialRight + right,
                    initialBottom + bottom
            );
            return windowInsets;
        });
        scroll.requestApplyInsets();
    }

    private void bindActions() {
        enabledSwitch.setOnCheckedChangeListener(checked -> {
            if (bindingUi) {
                return;
            }
            prefs.edit().putBoolean(AlarmScheduler.KEY_ENABLED, checked).apply();
            AlarmScheduler.scheduleAllAsync(this);
            renderSettings();
        });

        RadioGroup frequency = findViewById(R.id.radio_frequency);
        frequency.setOnCheckedChangeListener((group, checkedId) -> {
            if (bindingUi) {
                return;
            }
            boolean weekdaysOnly = checkedId == R.id.radio_weekdays;
            prefs.edit()
                    .putBoolean(AlarmScheduler.KEY_WEEKDAYS_ONLY, weekdaysOnly)
                    .apply();
            group.performHapticFeedback(HapticFeedbackConstants.VIRTUAL_KEY);
            AlarmScheduler.scheduleAllAsync(this);
            renderSettings();
        });

        View morningCard = findViewById(R.id.card_morning);
        View eveningCard = findViewById(R.id.card_evening);
        morningCard.setOnClickListener(view -> showShiftPicker(AlarmScheduler.TYPE_MORNING));
        eveningCard.setOnClickListener(view -> showShiftPicker(AlarmScheduler.TYPE_EVENING));
        bindPressEffect(morningCard);
        bindPressEffect(eveningCard);

        View testButton = findViewById(R.id.button_test);
        testButton.setOnClickListener(view -> {
            view.performHapticFeedback(HapticFeedbackConstants.VIRTUAL_KEY);
            if (!WeComLauncher.launch(this)) {
                Toast.makeText(
                        this,
                        R.string.wecom_missing_message,
                        Toast.LENGTH_LONG
                ).show();
            }
        });
        findViewById(R.id.button_screen_off_test).setOnClickListener(view -> {
            view.performHapticFeedback(HapticFeedbackConstants.VIRTUAL_KEY);
            if (!ClockInAccessibilityService.isEnabled(this)) {
                Toast.makeText(
                        this,
                        R.string.enable_accessibility_first,
                        Toast.LENGTH_LONG
                ).show();
                openAccessibilitySettings();
                return;
            }
            long triggerAt = AlarmScheduler.scheduleScreenOffTest(this);
            if (triggerAt == 0L) {
                Toast.makeText(this, R.string.test_schedule_failed, Toast.LENGTH_LONG)
                        .show();
                return;
            }
            String time = DateTimeFormatter.ofPattern("HH:mm:ss", Locale.US)
                    .format(
                            Instant.ofEpochMilli(triggerAt)
                                    .atZone(ZoneId.systemDefault())
                    );
            Toast.makeText(
                    this,
                    getString(R.string.test_scheduled_toast, time),
                    Toast.LENGTH_LONG
            ).show();
            renderSettings();
        });

        bindStatusTile(R.id.status_wecom, view -> {
            if (!WeComLauncher.launch(this)) {
                Toast.makeText(this, R.string.wecom_missing_message, Toast.LENGTH_LONG)
                        .show();
            }
        });
        bindStatusTile(R.id.status_accessibility, view -> openAccessibilitySettings());
        bindStatusTile(R.id.status_exact, view -> openExactAlarmSettings());
        bindStatusTile(
                R.id.status_notification,
                view -> requestOrOpenNotificationSettings()
        );
        bindStatusTile(R.id.status_full_screen, view -> openFullScreenSettings());
        bindStatusTile(R.id.status_battery, view -> openBatterySettings());

        deviceSettingsButton.setOnClickListener(view -> {
            view.performHapticFeedback(HapticFeedbackConstants.VIRTUAL_KEY);
            if (!DeviceCompatibility.openBackgroundSettings(this)) {
                Toast.makeText(
                        this,
                        R.string.device_settings_missing,
                        Toast.LENGTH_LONG
                ).show();
            }
        });
        findViewById(R.id.button_manual).setOnClickListener(view -> {
            view.performHapticFeedback(HapticFeedbackConstants.VIRTUAL_KEY);
            startActivity(new Intent(this, ManualActivity.class));
        });
        updateManager.bind();
    }

    private void renderSettings() {
        bindingUi = true;
        boolean enabled = prefs.getBoolean(AlarmScheduler.KEY_ENABLED, true);
        boolean weekdaysOnly =
                prefs.getBoolean(AlarmScheduler.KEY_WEEKDAYS_ONLY, false);
        int moodIndex = prefs.getInt(KEY_MOOD_TAG, 0);

        enabledSwitch.setChecked(enabled);
        dailyRadio.setChecked(!weekdaysOnly);
        weekdaysRadio.setChecked(weekdaysOnly);
        morningTime.setText(formatTime(
                prefs.getInt(AlarmScheduler.KEY_MORNING_HOUR, 8),
                prefs.getInt(AlarmScheduler.KEY_MORNING_MINUTE, 33)
        ));
        eveningTime.setText(formatTime(
                prefs.getInt(AlarmScheduler.KEY_EVENING_HOUR, 17),
                prefs.getInt(AlarmScheduler.KEY_EVENING_MINUTE, 31)
        ));
        moodBadge.setText(getString(R.string.mood_current, moodLabel(moodIndex)));
        moodBackground.setMoodIndex(moodIndex);

        renderAmbientUi(enabled);
        renderNextRun(enabled);
        renderLastTrigger();

        boolean wecomGood = WeComLauncher.isInstalled(this);
        boolean accessibilityGood = ClockInAccessibilityService.isEnabled(this);
        boolean exactGood = AlarmScheduler.canScheduleExact(this);
        boolean notificationGood = NotificationHelper.canPostNotifications(this);
        boolean fullScreenGood = NotificationHelper.canUseFullScreenIntent(this);
        boolean batteryGood = isIgnoringBatteryOptimizations();

        setStatus(
                R.id.status_wecom,
                R.string.wecom_status,
                R.string.status_icon_wecom,
                wecomGood,
                R.string.status_ready
        );
        setStatus(
                R.id.status_accessibility,
                R.string.accessibility_status,
                R.string.status_icon_accessibility,
                accessibilityGood,
                R.string.status_active
        );
        setStatus(
                R.id.status_exact,
                R.string.exact_alarm_status,
                R.string.status_icon_exact,
                exactGood,
                R.string.status_active
        );
        setStatus(
                R.id.status_notification,
                R.string.notification_status,
                R.string.status_icon_notification,
                notificationGood,
                R.string.status_secure
        );
        setStatus(
                R.id.status_full_screen,
                R.string.full_screen_status,
                R.string.status_icon_full_screen,
                fullScreenGood,
                R.string.status_active
        );
        setStatus(
                R.id.status_battery,
                R.string.battery_status,
                R.string.status_icon_battery,
                batteryGood,
                R.string.status_secure
        );

        boolean hasIssue = !wecomGood
                || !accessibilityGood
                || !exactGood
                || !notificationGood
                || !fullScreenGood
                || !batteryGood;
        DeviceCompatibility.Profile profile = DeviceCompatibility.current();
        deviceProfile.setText(getString(
                R.string.device_profile,
                DeviceCompatibility.deviceName(),
                profile.family,
                profile.system,
                Build.VERSION.SDK_INT
        ));
        deviceSettingsButton.setText(getString(
                R.string.open_device_settings,
                profile.family
        ));
        deviceSettingsButton.setActivated(hasIssue);
        deviceSettingsButton.setAlpha(hasIssue ? 1f : 0.72f);
        bindingUi = false;
    }

    private void renderAmbientUi(boolean enabled) {
        int hour = LocalTime.now().getHour();
        boolean night = hour >= 18 || hour < 5;
        moodBackground.setNightMode(night);
        greeting.setText(night ? R.string.greeting_night : R.string.greeting_morning);
        headerStatus.setText(enabled ? R.string.header_ready : R.string.header_paused);

        int primaryText = night ? Color.WHITE : getColor(R.color.ink);
        int secondaryText = night
                ? Color.argb(218, 235, 247, 250)
                : getColor(R.color.ink_muted);
        greeting.setTextColor(primaryText);
        headerStatus.setTextColor(secondaryText);
        setTextColor(R.id.text_schedule_title, primaryText);
        setTextColor(R.id.text_schedule_subtitle, secondaryText);
        setTextColor(R.id.text_health_title, primaryText);
        setTextColor(R.id.text_health_subtitle, secondaryText);
        setTextColor(R.id.text_setup_hint, secondaryText);

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
            WindowInsetsController controller = getWindow().getInsetsController();
            if (controller != null) {
                int lightStatus = WindowInsetsController.APPEARANCE_LIGHT_STATUS_BARS;
                controller.setSystemBarsAppearance(night ? 0 : lightStatus, lightStatus);
            }
        } else {
            @SuppressWarnings("deprecation")
            int systemUi = night ? 0 : View.SYSTEM_UI_FLAG_LIGHT_STATUS_BAR;
            @SuppressWarnings("deprecation")
            View decorView = getWindow().getDecorView();
            decorView.setSystemUiVisibility(systemUi);
        }
    }

    private void renderLastTrigger() {
        long triggeredAt = prefs.getLong(AlarmScheduler.KEY_LAST_TRIGGER_AT, 0L);
        String message = prefs.getString(
                AlarmScheduler.KEY_LAST_TRIGGER_MESSAGE,
                getString(R.string.no_trigger_record)
        );
        if (triggeredAt == 0L) {
            lastTrigger.setText(R.string.no_trigger_record);
            return;
        }
        DateTimeFormatter formatter = DateTimeFormatter.ofPattern(
                "M月d日 HH:mm:ss",
                Locale.SIMPLIFIED_CHINESE
        );
        String time = formatter.format(
                Instant.ofEpochMilli(triggeredAt).atZone(ZoneId.systemDefault())
        );
        lastTrigger.setText(getString(R.string.last_trigger_value, time, message));
    }

    private void renderNextRun(boolean enabled) {
        if (!enabled) {
            nextRun.setText(R.string.paused_next_run);
            countdown.setText(R.string.countdown_paused);
            shiftProgress.setProgress(0.04f);
            return;
        }
        AlarmScheduler.NextEvent event = AlarmScheduler.getNextEvent(this);
        if (event == null) {
            nextRun.setText(R.string.paused_next_run);
            countdown.setText(R.string.countdown_paused);
            shiftProgress.setProgress(0.04f);
            return;
        }

        DateTimeFormatter formatter = DateTimeFormatter.ofPattern(
                "MM-dd EEE HH:mm",
                Locale.US
        );
        String label = event.type == AlarmScheduler.TYPE_MORNING
                ? getString(R.string.morning_label)
                : getString(R.string.evening_label);
        String dateValue = formatter.format(
                Instant.ofEpochMilli(event.triggerAtMillis)
                        .atZone(ZoneId.systemDefault())
        ).toUpperCase(Locale.US);
        if (!AlarmScheduler.canScheduleExact(this)) {
            dateValue += "  ~";
        }
        nextRun.setText(getString(R.string.next_run_value, dateValue, label));

        long remaining = Math.max(0L, event.triggerAtMillis - System.currentTimeMillis());
        countdown.setText(getString(
                R.string.countdown_value,
                label,
                formatDuration(remaining)
        ));
        float progress = 1f - Math.min(1f, (float) remaining / COUNTDOWN_WINDOW_MILLIS);
        shiftProgress.setProgress(progress);
    }

    private void setStatus(
            int rowId,
            int labelId,
            int iconId,
            boolean good,
            int goodTextId
    ) {
        View row = findViewById(rowId);
        TextView icon = row.findViewById(R.id.status_icon);
        TextView label = row.findViewById(R.id.status_label);
        TextView value = row.findViewById(R.id.status_value);
        View dot = row.findViewById(R.id.status_dot);

        icon.setText(iconId);
        label.setText(labelId);
        value.setText(good ? goodTextId : R.string.status_setup);
        value.setTextColor(getColor(good ? R.color.primary : R.color.accent));
        icon.setTextColor(getColor(good ? R.color.primary_dark : R.color.accent));
        dot.setBackgroundResource(
                good
                        ? R.drawable.bg_status_dot_good
                        : R.drawable.bg_status_dot_warn
        );
        row.setContentDescription(
                label.getText() + " " + value.getText()
        );
    }

    private void showShiftPicker(int type) {
        String hourKey = type == AlarmScheduler.TYPE_MORNING
                ? AlarmScheduler.KEY_MORNING_HOUR
                : AlarmScheduler.KEY_EVENING_HOUR;
        String minuteKey = type == AlarmScheduler.TYPE_MORNING
                ? AlarmScheduler.KEY_MORNING_MINUTE
                : AlarmScheduler.KEY_EVENING_MINUTE;
        int defaultHour = type == AlarmScheduler.TYPE_MORNING ? 8 : 17;
        int defaultMinute = type == AlarmScheduler.TYPE_MORNING ? 33 : 31;

        Dialog dialog = new Dialog(this);
        dialog.requestWindowFeature(Window.FEATURE_NO_TITLE);
        dialog.setContentView(R.layout.dialog_shift_picker);

        TextView title = dialog.findViewById(R.id.dialog_title);
        title.setText(
                type == AlarmScheduler.TYPE_MORNING
                        ? R.string.picker_morning_title
                        : R.string.picker_evening_title
        );

        NumberPicker hourPicker = dialog.findViewById(R.id.picker_hour);
        NumberPicker minutePicker = dialog.findViewById(R.id.picker_minute);
        hourPicker.setMinValue(0);
        hourPicker.setMaxValue(23);
        hourPicker.setWrapSelectorWheel(true);
        hourPicker.setFormatter(value -> String.format(Locale.US, "%02d", value));
        hourPicker.setValue(prefs.getInt(hourKey, defaultHour));
        minutePicker.setMinValue(0);
        minutePicker.setMaxValue(59);
        minutePicker.setWrapSelectorWheel(true);
        minutePicker.setFormatter(value -> String.format(Locale.US, "%02d", value));
        minutePicker.setValue(prefs.getInt(minuteKey, defaultMinute));

        RadioGroup moodGroup = dialog.findViewById(R.id.radio_mood);
        moodGroup.check(moodRadioId(prefs.getInt(KEY_MOOD_TAG, 0)));

        dialog.findViewById(R.id.dialog_cancel)
                .setOnClickListener(view -> dialog.dismiss());
        dialog.findViewById(R.id.dialog_save).setOnClickListener(view -> {
            view.performHapticFeedback(HapticFeedbackConstants.VIRTUAL_KEY);
            int moodIndex = moodIndexFromRadio(moodGroup.getCheckedRadioButtonId());
            prefs.edit()
                    .putInt(hourKey, hourPicker.getValue())
                    .putInt(minuteKey, minutePicker.getValue())
                    .putInt(KEY_MOOD_TAG, moodIndex)
                    .apply();
            AlarmScheduler.scheduleAllAsync(this);
            renderSettings();
            dialog.dismiss();
        });

        Window window = dialog.getWindow();
        if (window != null) {
            window.setBackgroundDrawable(new ColorDrawable(Color.TRANSPARENT));
            window.addFlags(WindowManager.LayoutParams.FLAG_DIM_BEHIND);
            WindowManager.LayoutParams params = window.getAttributes();
            params.dimAmount = 0.48f;
            window.setAttributes(params);
        }
        dialog.show();
        if (window != null) {
            int width = (int) (
                    getResources().getDisplayMetrics().widthPixels * 0.91f
            );
            window.setLayout(width, WindowManager.LayoutParams.WRAP_CONTENT);
        }
    }

    private void bindStatusTile(int id, View.OnClickListener listener) {
        View tile = findViewById(id);
        tile.setOnClickListener(view -> {
            view.performHapticFeedback(HapticFeedbackConstants.VIRTUAL_KEY);
            listener.onClick(view);
        });
        bindPressEffect(tile);
    }

    @SuppressLint("ClickableViewAccessibility")
    private void bindPressEffect(View view) {
        view.setOnTouchListener((target, event) -> {
            if (event.getActionMasked() == MotionEvent.ACTION_DOWN) {
                target.animate().scaleX(0.975f).scaleY(0.975f).setDuration(90L).start();
            } else if (event.getActionMasked() == MotionEvent.ACTION_UP
                    || event.getActionMasked() == MotionEvent.ACTION_CANCEL) {
                target.animate().scaleX(1f).scaleY(1f).setDuration(150L).start();
            }
            return false;
        });
    }

    private void setTextColor(int viewId, int color) {
        TextView view = findViewById(viewId);
        view.setTextColor(color);
    }

    private String moodLabel(int moodIndex) {
        int[] labels = {
                R.string.mood_working,
                R.string.mood_slacking,
                R.string.mood_home,
                R.string.mood_zen
        };
        int safeIndex = Math.max(0, Math.min(labels.length - 1, moodIndex));
        return getString(labels[safeIndex]);
    }

    private int moodRadioId(int moodIndex) {
        int[] ids = {
                R.id.mood_working,
                R.id.mood_slacking,
                R.id.mood_home,
                R.id.mood_zen
        };
        int safeIndex = Math.max(0, Math.min(ids.length - 1, moodIndex));
        return ids[safeIndex];
    }

    private int moodIndexFromRadio(int radioId) {
        if (radioId == R.id.mood_slacking) {
            return 1;
        }
        if (radioId == R.id.mood_home) {
            return 2;
        }
        if (radioId == R.id.mood_zen) {
            return 3;
        }
        return 0;
    }

    private String formatDuration(long millis) {
        long totalSeconds = millis / 1_000L;
        long days = totalSeconds / 86_400L;
        long hours = (totalSeconds % 86_400L) / 3_600L;
        long minutes = (totalSeconds % 3_600L) / 60L;
        long seconds = totalSeconds % 60L;
        if (days > 0L) {
            return String.format(
                    Locale.US,
                    "%dd %02d:%02d:%02d",
                    days,
                    hours,
                    minutes,
                    seconds
            );
        }
        return String.format(
                Locale.US,
                "%02d:%02d:%02d",
                hours,
                minutes,
                seconds
        );
    }

    private void openExactAlarmSettings() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.S) {
            return;
        }
        Intent intent = new Intent(
                Settings.ACTION_REQUEST_SCHEDULE_EXACT_ALARM,
                Uri.parse("package:" + getPackageName())
        );
        safeStart(intent, new Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS)
                .setData(Uri.parse("package:" + getPackageName())));
    }

    private void openAccessibilitySettings() {
        Intent details = new Intent("android.settings.ACCESSIBILITY_DETAILS_SETTINGS")
                .setData(Uri.parse("package:" + getPackageName()));
        safeStart(details, new Intent(Settings.ACTION_ACCESSIBILITY_SETTINGS));
    }

    private void requestOrOpenNotificationSettings() {
        if (Build.VERSION.SDK_INT >= 33
                && checkSelfPermission(Manifest.permission.POST_NOTIFICATIONS)
                != PackageManager.PERMISSION_GRANTED) {
            requestPermissions(
                    new String[]{Manifest.permission.POST_NOTIFICATIONS},
                    REQUEST_NOTIFICATIONS
            );
            return;
        }
        Intent intent = new Intent(Settings.ACTION_APP_NOTIFICATION_SETTINGS)
                .putExtra(Settings.EXTRA_APP_PACKAGE, getPackageName());
        safeStart(intent, new Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS)
                .setData(Uri.parse("package:" + getPackageName())));
    }

    private void openFullScreenSettings() {
        if (Build.VERSION.SDK_INT < 34) {
            return;
        }
        Intent intent = new Intent(
                Settings.ACTION_MANAGE_APP_USE_FULL_SCREEN_INTENT,
                Uri.parse("package:" + getPackageName())
        );
        safeStart(intent, new Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS)
                .setData(Uri.parse("package:" + getPackageName())));
    }

    @SuppressLint("BatteryLife")
    private void openBatterySettings() {
        Intent request = new Intent(
                Settings.ACTION_REQUEST_IGNORE_BATTERY_OPTIMIZATIONS,
                Uri.parse("package:" + getPackageName())
        );
        Intent fallback = new Intent(Settings.ACTION_IGNORE_BATTERY_OPTIMIZATION_SETTINGS);
        safeStart(request, fallback);
    }

    private boolean isIgnoringBatteryOptimizations() {
        PowerManager manager = getSystemService(PowerManager.class);
        return manager != null
                && manager.isIgnoringBatteryOptimizations(getPackageName());
    }

    private boolean safeStart(Intent primary, Intent fallback) {
        try {
            startActivity(primary);
            return true;
        } catch (RuntimeException ignored) {
            try {
                startActivity(fallback);
                return true;
            } catch (RuntimeException alsoIgnored) {
                return false;
            }
        }
    }

    private String formatTime(int hour, int minute) {
        return String.format(Locale.US, "%02d:%02d", hour, minute);
    }
}
