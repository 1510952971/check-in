package com.clockin.assistant;

import android.app.Activity;
import android.app.KeyguardManager;
import android.os.Build;
import android.os.Bundle;
import android.os.Handler;
import android.os.Looper;
import android.view.View;
import android.view.WindowManager;
import android.widget.Button;
import android.widget.TextView;

public class TriggerActivity extends Activity {
    private static final long INITIAL_ACTION_DELAY_MILLIS = 240L;

    private final Handler handler = new Handler(Looper.getMainLooper());

    private int type;
    private long epochDay;
    private boolean test;
    private boolean dismissRequested;
    private boolean launchCompleted;
    private KeyguardManager keyguardManager;
    private TextView title;
    private TextView message;
    private Button primaryButton;
    private Button closeButton;

    @Override
    protected void onCreate(Bundle savedInstanceState) {
        super.onCreate(savedInstanceState);
        wakeScreen();
        setContentView(R.layout.activity_trigger);

        type = getIntent().getIntExtra(
                AlarmScheduler.EXTRA_TYPE,
                AlarmScheduler.TYPE_MORNING
        );
        epochDay = getIntent().getLongExtra(AlarmScheduler.EXTRA_EPOCH_DAY, 0L);
        test = getIntent().getBooleanExtra(AlarmScheduler.EXTRA_TEST, false);
        keyguardManager = getSystemService(KeyguardManager.class);
        title = findViewById(R.id.text_trigger_title);
        message = findViewById(R.id.text_trigger_message);
        primaryButton = findViewById(R.id.button_trigger_retry);
        closeButton = findViewById(R.id.button_trigger_close);

        AlarmScheduler.recordTrigger(
                this,
                getString(R.string.log_trigger_activity_started)
        );
        markTriggerReached();

        primaryButton.setOnClickListener(view -> requestUnlockAndOpen());
        closeButton.setOnClickListener(view -> finishAndRemoveTask());
        handler.postDelayed(
                this::requestUnlockAndOpen,
                INITIAL_ACTION_DELAY_MILLIS
        );
    }

    @Override
    protected void onDestroy() {
        handler.removeCallbacksAndMessages(null);
        super.onDestroy();
    }

    @Override
    public void onWindowFocusChanged(boolean hasFocus) {
        super.onWindowFocusChanged(hasFocus);
        if (hasFocus && !launchCompleted && !isKeyguardLocked()) {
            handler.postDelayed(this::openWeCom, 140L);
        }
    }

    private void wakeScreen() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O_MR1) {
            setShowWhenLocked(true);
            setTurnScreenOn(true);
        } else {
            getWindow().addFlags(
                    WindowManager.LayoutParams.FLAG_SHOW_WHEN_LOCKED
                            | WindowManager.LayoutParams.FLAG_TURN_SCREEN_ON
            );
        }
    }

    private void requestUnlockAndOpen() {
        if (launchCompleted) {
            return;
        }
        if (!isKeyguardLocked()) {
            openWeCom();
            return;
        }

        showUnlockGate(R.string.unlock_required_message);
        if (dismissRequested || keyguardManager == null) {
            return;
        }

        dismissRequested = true;
        AlarmScheduler.recordTrigger(
                this,
                getString(R.string.log_unlock_required)
        );
        keyguardManager.requestDismissKeyguard(
                this,
                new KeyguardManager.KeyguardDismissCallback() {
                    @Override
                    public void onDismissSucceeded() {
                        dismissRequested = false;
                        AlarmScheduler.recordTrigger(
                                TriggerActivity.this,
                                getString(R.string.log_unlock_succeeded)
                        );
                        handler.postDelayed(
                                TriggerActivity.this::openWeCom,
                                180L
                        );
                    }

                    @Override
                    public void onDismissCancelled() {
                        dismissRequested = false;
                        showUnlockGate(R.string.unlock_cancelled_message);
                    }

                    @Override
                    public void onDismissError() {
                        dismissRequested = false;
                        showUnlockGate(R.string.unlock_error_message);
                    }
                }
        );
    }

    private boolean isKeyguardLocked() {
        return keyguardManager != null && keyguardManager.isKeyguardLocked();
    }

    private void showUnlockGate(int messageId) {
        title.setText(R.string.unlock_required_title);
        message.setText(messageId);
        message.setVisibility(View.VISIBLE);
        primaryButton.setText(R.string.unlock_and_open);
        primaryButton.setVisibility(View.VISIBLE);
        closeButton.setVisibility(View.VISIBLE);
    }

    private void showOpeningState() {
        title.setText(R.string.opening_wecom);
        message.setText(R.string.unlock_success_message);
        message.setVisibility(View.VISIBLE);
        primaryButton.setVisibility(View.GONE);
        closeButton.setVisibility(View.GONE);
    }

    private void openWeCom() {
        if (launchCompleted) {
            return;
        }
        if (isKeyguardLocked()) {
            requestUnlockAndOpen();
            return;
        }

        showOpeningState();
        if (WeComLauncher.launch(this)) {
            launchCompleted = true;
            AlarmScheduler.recordTrigger(
                    this,
                    getString(R.string.log_wecom_launch_sent)
            );
            finishAndRemoveTask();
            return;
        }

        AlarmScheduler.recordTrigger(
                this,
                getString(R.string.log_wecom_missing)
        );
        title.setText(R.string.wecom_missing_title);
        message.setText(R.string.wecom_missing_message);
        message.setVisibility(View.VISIBLE);
        primaryButton.setText(R.string.open_app);
        primaryButton.setVisibility(View.VISIBLE);
        closeButton.setVisibility(View.VISIBLE);
    }

    private void markTriggerReached() {
        if (epochDay == 0L || test) {
            return;
        }
        AlarmScheduler.preferences(this)
                .edit()
                .putLong(
                        AlarmScheduler.markerKey(type, epochDay),
                        System.currentTimeMillis()
                )
                .apply();
    }
}
