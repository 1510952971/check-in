package com.clockin.assistant;

import android.app.Activity;
import android.graphics.Color;
import android.graphics.Insets;
import android.os.Build;
import android.os.Bundle;
import android.view.View;
import android.view.WindowInsets;
import android.view.WindowInsetsController;

import com.clockin.assistant.ui.MoodBackgroundView;

/**
 * In-app reference for setup, lock-screen behavior, tests, and updates.
 */
public class ManualActivity extends Activity {
    @Override
    protected void onCreate(Bundle savedInstanceState) {
        super.onCreate(savedInstanceState);
        getWindow().setStatusBarColor(Color.TRANSPARENT);
        getWindow().setNavigationBarColor(Color.rgb(10, 17, 25));
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            getWindow().setNavigationBarContrastEnforced(false);
        }
        setContentView(R.layout.activity_manual);
        applySystemBarInsets();

        MoodBackgroundView background = findViewById(R.id.manual_background);
        background.setNightMode(false);
        findViewById(R.id.button_manual_back)
                .setOnClickListener(view -> finish());

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
            WindowInsetsController controller = getWindow().getInsetsController();
            if (controller != null) {
                int lightStatus =
                        WindowInsetsController.APPEARANCE_LIGHT_STATUS_BARS;
                controller.setSystemBarsAppearance(
                        lightStatus,
                        lightStatus
                );
            }
        }
    }

    @SuppressWarnings("deprecation")
    private void applySystemBarInsets() {
        View scroll = findViewById(R.id.manual_scroll);
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
                Insets bars = windowInsets.getInsets(
                        WindowInsets.Type.systemBars()
                );
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
}
