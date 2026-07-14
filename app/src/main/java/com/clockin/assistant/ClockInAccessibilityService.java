package com.clockin.assistant;

import android.accessibilityservice.AccessibilityService;
import android.accessibilityservice.AccessibilityServiceInfo;
import android.content.Context;
import android.content.Intent;
import android.view.accessibility.AccessibilityEvent;
import android.view.accessibility.AccessibilityManager;

import java.util.List;

public class ClockInAccessibilityService extends AccessibilityService {
    private static volatile ClockInAccessibilityService connectedInstance;

    @Override
    protected void onServiceConnected() {
        super.onServiceConnected();
        connectedInstance = this;
    }

    @Override
    public void onAccessibilityEvent(AccessibilityEvent event) {
        if (event == null
                || event.getEventType()
                != AccessibilityEvent.TYPE_WINDOW_STATE_CHANGED) {
            return;
        }
        CharSequence packageName = event.getPackageName();
        if (packageName != null
                && WeComLauncher.WECOM_PACKAGE.contentEquals(packageName)) {
            LaunchCompletionTracker.confirmWeComVisible(this);
        }
    }

    @Override
    public void onInterrupt() {
        // No continuous accessibility operation needs recovery.
    }

    @Override
    public void onDestroy() {
        if (connectedInstance == this) {
            connectedInstance = null;
        }
        super.onDestroy();
    }

    public static boolean isEnabled(Context context) {
        if (connectedInstance != null) {
            return true;
        }
        AccessibilityManager manager =
                context.getSystemService(AccessibilityManager.class);
        if (manager == null || !manager.isEnabled()) {
            return false;
        }
        List<AccessibilityServiceInfo> services =
                manager.getEnabledAccessibilityServiceList(
                        AccessibilityServiceInfo.FEEDBACK_ALL_MASK
                );
        String packageName = context.getPackageName();
        String className = ClockInAccessibilityService.class.getName();
        for (AccessibilityServiceInfo info : services) {
            if (info.getResolveInfo() == null
                    || info.getResolveInfo().serviceInfo == null) {
                continue;
            }
            String servicePackage =
                    info.getResolveInfo().serviceInfo.packageName;
            String serviceName = info.getResolveInfo().serviceInfo.name;
            if (serviceName != null && serviceName.startsWith(".")) {
                serviceName = servicePackage + serviceName;
            }
            if (packageName.equals(servicePackage)
                    && className.equals(serviceName)) {
                return true;
            }
        }
        return false;
    }

    public static boolean launchTrigger(
            Context context,
            int type,
            long epochDay,
            boolean test
    ) {
        if (!isEnabled(context)) {
            return false;
        }
        Context launchContext = connectedInstance != null
                ? connectedInstance
                : context.getApplicationContext();
        Intent intent = new Intent(launchContext, TriggerActivity.class)
                .setAction(
                        "com.clockin.assistant.ACCESSIBILITY."
                                + type
                                + "."
                                + epochDay
                                + "."
                                + System.currentTimeMillis()
                )
                .putExtra(AlarmScheduler.EXTRA_TYPE, type)
                .putExtra(AlarmScheduler.EXTRA_EPOCH_DAY, epochDay)
                .putExtra(AlarmScheduler.EXTRA_TEST, test)
                .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK | Intent.FLAG_ACTIVITY_CLEAR_TOP);
        try {
            launchContext.startActivity(intent);
            return true;
        } catch (RuntimeException ignored) {
            return false;
        }
    }
}
