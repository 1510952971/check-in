package com.clockin.assistant;

import android.content.Context;
import android.content.Intent;
import android.content.pm.PackageManager;

public final class WeComLauncher {
    public static final String WECOM_PACKAGE = "com.tencent.wework";

    private WeComLauncher() {
    }

    public static boolean isInstalled(Context context) {
        PackageManager packageManager = context.getPackageManager();
        Intent launchIntent = packageManager.getLaunchIntentForPackage(WECOM_PACKAGE);
        return launchIntent != null;
    }

    public static boolean launch(Context context) {
        Intent launchIntent =
                context.getPackageManager().getLaunchIntentForPackage(WECOM_PACKAGE);
        if (launchIntent == null) {
            return false;
        }

        launchIntent.addFlags(
                Intent.FLAG_ACTIVITY_NEW_TASK
                        | Intent.FLAG_ACTIVITY_RESET_TASK_IF_NEEDED
        );
        try {
            context.startActivity(launchIntent);
            return true;
        } catch (RuntimeException ignored) {
            return false;
        }
    }
}
