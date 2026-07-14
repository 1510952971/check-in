package com.clockin.assistant;

import android.app.Activity;
import android.content.ComponentName;
import android.content.Intent;
import android.net.Uri;
import android.os.Build;
import android.provider.Settings;

import java.util.ArrayList;
import java.util.List;
import java.util.Locale;

/**
 * Maps common Android manufacturer families to their background-start screens.
 *
 * <p>OEM component names are best-effort only. Every path falls back to
 * Android's standard app details page so a vendor rename after a system update
 * does not leave the user without a settings entry point.</p>
 */
public final class DeviceCompatibility {
    public static final class Profile {
        public final String family;
        public final String system;
        private final List<ComponentName> settingsCandidates;

        private Profile(
                String family,
                String system,
                List<ComponentName> settingsCandidates
        ) {
            this.family = family;
            this.system = system;
            this.settingsCandidates = settingsCandidates;
        }
    }

    private DeviceCompatibility() {
    }

    public static Profile current() {
        String identity = (
                Build.MANUFACTURER
                        + " "
                        + Build.BRAND
                        + " "
                        + Build.DEVICE
        ).toLowerCase(Locale.US);
        List<ComponentName> candidates = new ArrayList<>();

        if (containsAny(identity, "xiaomi", "redmi", "poco")) {
            candidates.add(component(
                    "com.miui.securitycenter",
                    "com.miui.permcenter.autostart.AutoStartManagementActivity"
            ));
            candidates.add(component(
                    "com.miui.powerkeeper",
                    "com.miui.powerkeeper.ui.HiddenAppsContainerManagementActivity"
            ));
            return new Profile("小米 / Redmi / POCO", "HyperOS / MIUI", candidates);
        }
        if (containsAny(identity, "huawei")) {
            candidates.add(component(
                    "com.huawei.systemmanager",
                    "com.huawei.systemmanager.startupmgr.ui.StartupNormalAppListActivity"
            ));
            candidates.add(component(
                    "com.huawei.systemmanager",
                    "com.huawei.systemmanager.optimize.process.ProtectActivity"
            ));
            return new Profile("华为", "HarmonyOS / EMUI", candidates);
        }
        if (containsAny(identity, "honor", "hihonor")) {
            candidates.add(component(
                    "com.hihonor.systemmanager",
                    "com.hihonor.systemmanager.startupmgr.ui.StartupNormalAppListActivity"
            ));
            return new Profile("荣耀", "MagicOS", candidates);
        }
        if (containsAny(identity, "oppo", "oneplus", "realme")) {
            candidates.add(component(
                    "com.coloros.safecenter",
                    "com.coloros.safecenter.permission.startup.StartupAppListActivity"
            ));
            candidates.add(component(
                    "com.oplus.battery",
                    "com.oplus.powermanager.fuelgaue.PowerUsageModelActivity"
            ));
            return new Profile(
                    "OPPO / 一加 / realme",
                    "ColorOS / OxygenOS / realme UI",
                    candidates
            );
        }
        if (containsAny(identity, "vivo", "iqoo")) {
            candidates.add(component(
                    "com.vivo.permissionmanager",
                    "com.vivo.permissionmanager.activity.BgStartUpManagerActivity"
            ));
            candidates.add(component(
                    "com.iqoo.secure",
                    "com.iqoo.secure.safeguard.PurviewTabActivity"
            ));
            return new Profile("vivo / iQOO", "OriginOS / Funtouch OS", candidates);
        }
        if (containsAny(identity, "samsung")) {
            candidates.add(component(
                    "com.samsung.android.lool",
                    "com.samsung.android.sm.ui.battery.BatteryActivity"
            ));
            return new Profile("三星", "One UI", candidates);
        }
        if (containsAny(identity, "meizu")) {
            candidates.add(component(
                    "com.meizu.safe",
                    "com.meizu.safe.permission.SmartBGActivity"
            ));
            return new Profile("魅族", "Flyme", candidates);
        }
        return new Profile("Android 通用机型", "标准 Android", candidates);
    }

    public static String deviceName() {
        String brand = Build.BRAND == null ? "" : Build.BRAND.trim();
        String model = Build.MODEL == null ? "" : Build.MODEL.trim();
        if (brand.isEmpty() || model.toLowerCase(Locale.US)
                .startsWith(brand.toLowerCase(Locale.US))) {
            return model;
        }
        return brand + " " + model;
    }

    public static boolean openBackgroundSettings(Activity activity) {
        Profile profile = current();
        for (ComponentName component : profile.settingsCandidates) {
            Intent intent = new Intent().setComponent(component);
            try {
                activity.startActivity(intent);
                return true;
            } catch (RuntimeException ignored) {
                // The manufacturer may rename this screen in a system update.
            }
        }

        Intent details = new Intent(
                Settings.ACTION_APPLICATION_DETAILS_SETTINGS,
                Uri.parse("package:" + activity.getPackageName())
        );
        try {
            activity.startActivity(details);
            return true;
        } catch (RuntimeException ignored) {
            try {
                activity.startActivity(
                        new Intent(Settings.ACTION_SETTINGS)
                );
                return true;
            } catch (RuntimeException alsoIgnored) {
                return false;
            }
        }
    }

    private static ComponentName component(
            String packageName,
            String className
    ) {
        return new ComponentName(packageName, className);
    }

    private static boolean containsAny(String value, String... needles) {
        for (String needle : needles) {
            if (value.contains(needle)) {
                return true;
            }
        }
        return false;
    }
}
