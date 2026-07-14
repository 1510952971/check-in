package com.clockin.assistant;

import android.app.Activity;
import android.app.Dialog;
import android.content.Intent;
import android.content.SharedPreferences;
import android.content.pm.PackageInfo;
import android.content.pm.PackageManager;
import android.content.pm.Signature;
import android.graphics.Color;
import android.graphics.drawable.ColorDrawable;
import android.net.Uri;
import android.os.Build;
import android.os.Handler;
import android.os.Looper;
import android.provider.Settings;
import android.text.InputType;
import android.view.HapticFeedbackConstants;
import android.view.View;
import android.view.Window;
import android.view.WindowManager;
import android.widget.Button;
import android.widget.EditText;
import android.widget.TextView;
import android.widget.Toast;

import org.json.JSONArray;
import org.json.JSONObject;

import java.io.BufferedInputStream;
import java.io.BufferedOutputStream;
import java.io.ByteArrayOutputStream;
import java.io.File;
import java.io.FileOutputStream;
import java.io.InputStream;
import java.net.HttpURLConnection;
import java.net.URL;
import java.nio.charset.StandardCharsets;
import java.security.MessageDigest;
import java.util.Arrays;
import java.util.HashSet;
import java.util.Locale;
import java.util.Set;
import java.util.concurrent.ExecutorService;
import java.util.concurrent.Executors;
import java.util.regex.Pattern;

/**
 * Public GitHub Releases updater used by the main screen.
 *
 * <p>The downloaded file is accepted only when its package name and signing
 * certificate match the currently installed app. Android's package installer
 * performs its own checks as well; this earlier check gives the user a clearer
 * failure before opening the installer.</p>
 */
public final class GitHubUpdateManager {
    private static final String PREFS = "check_in_updates";
    private static final String KEY_REPOSITORY = "github_repository";
    private static final String KEY_PENDING_INSTALL = "pending_update_install";
    private static final String APK_MIME =
            "application/vnd.android.package-archive";
    private static final String API_VERSION = "2026-03-10";
    private static final long MAX_APK_BYTES = 200L * 1024L * 1024L;
    private static final Pattern REPOSITORY_PATTERN = Pattern.compile(
            "[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+"
    );

    private final Activity activity;
    private final TextView statusView;
    private final Button checkButton;
    private final SharedPreferences preferences;
    private final Handler mainHandler = new Handler(Looper.getMainLooper());
    private final ExecutorService executor = Executors.newSingleThreadExecutor();
    private boolean busy;

    public GitHubUpdateManager(
            Activity activity,
            TextView statusView,
            Button checkButton
    ) {
        this.activity = activity;
        this.statusView = statusView;
        this.checkButton = checkButton;
        this.preferences = activity.getSharedPreferences(PREFS, Activity.MODE_PRIVATE);
    }

    public void bind() {
        checkButton.setOnClickListener(view -> {
            view.performHapticFeedback(HapticFeedbackConstants.VIRTUAL_KEY);
            checkForUpdates();
        });
        checkButton.setOnLongClickListener(view -> {
            view.performHapticFeedback(HapticFeedbackConstants.LONG_PRESS);
            showRepositoryDialog();
            return true;
        });
        renderRepositoryStatus();
    }

    public void onResume() {
        renderRepositoryStatus();
        if (!preferences.getBoolean(KEY_PENDING_INSTALL, false)) {
            return;
        }
        File apk = UpdateFileProvider.updateFile(activity);
        if (!apk.isFile()) {
            preferences.edit().putBoolean(KEY_PENDING_INSTALL, false).apply();
            return;
        }
        if (canInstallPackages()) {
            preferences.edit().putBoolean(KEY_PENDING_INSTALL, false).apply();
            openInstaller();
        }
    }

    public void destroy() {
        executor.shutdownNow();
    }

    private void checkForUpdates() {
        if (busy) {
            return;
        }
        String repository = repository();
        if (repository.isEmpty()) {
            showRepositoryDialog();
            return;
        }

        setBusy(true);
        statusView.setText(R.string.update_checking);
        executor.execute(() -> {
            try {
                ReleaseInfo release = fetchLatestRelease(repository);
                mainHandler.post(() -> showReleaseResult(release));
            } catch (Exception error) {
                mainHandler.post(() -> showFailure(messageOf(error)));
            }
        });
    }

    private ReleaseInfo fetchLatestRelease(String repository) throws Exception {
        URL url = new URL(
                "https://api.github.com/repos/"
                        + repository
                        + "/releases/latest"
        );
        HttpURLConnection connection = openConnection(url);
        connection.setRequestProperty(
                "Accept",
                "application/vnd.github+json"
        );
        connection.setRequestProperty("X-GitHub-Api-Version", API_VERSION);
        int responseCode = connection.getResponseCode();
        String response = readResponse(connection, responseCode);
        connection.disconnect();

        if (responseCode == HttpURLConnection.HTTP_NOT_FOUND) {
            throw new UpdateException(
                    activity.getString(R.string.update_public_repo_required)
            );
        }
        if (responseCode != HttpURLConnection.HTTP_OK) {
            throw new UpdateException("GitHub API HTTP " + responseCode);
        }

        JSONObject json = new JSONObject(response);
        String tag = json.optString("tag_name", "");
        String version = normalizeVersion(tag);
        if (version.isEmpty()) {
            throw new UpdateException("Release 缺少有效版本号");
        }

        JSONArray assets = json.optJSONArray("assets");
        AssetInfo selectedAsset = selectApkAsset(assets);
        return new ReleaseInfo(
                version,
                json.optString("html_url", ""),
                selectedAsset
        );
    }

    private AssetInfo selectApkAsset(JSONArray assets) {
        if (assets == null) {
            return null;
        }
        AssetInfo best = null;
        int bestScore = Integer.MIN_VALUE;
        for (int index = 0; index < assets.length(); index++) {
            JSONObject asset = assets.optJSONObject(index);
            if (asset == null) {
                continue;
            }
            String name = asset.optString("name", "");
            String lowerName = name.toLowerCase(Locale.US);
            String downloadUrl = asset.optString("browser_download_url", "");
            if (!lowerName.endsWith(".apk")
                    || lowerName.contains("unsigned")
                    || downloadUrl.isEmpty()) {
                continue;
            }
            int score = lowerName.startsWith("check-in-") ? 20 : 0;
            if (lowerName.contains("release")) {
                score += 5;
            }
            if (score > bestScore) {
                bestScore = score;
                best = new AssetInfo(
                        name,
                        downloadUrl,
                        asset.optLong("size", 0L)
                );
            }
        }
        return best;
    }

    private void showReleaseResult(ReleaseInfo release) {
        setBusy(false);
        if (compareVersions(release.version, BuildConfig.VERSION_NAME) <= 0) {
            statusView.setText(getString(
                    R.string.update_latest,
                    BuildConfig.VERSION_NAME
            ));
            return;
        }
        if (release.asset == null) {
            showFailure(activity.getString(R.string.update_no_apk));
            return;
        }

        String sizeSuffix = release.asset.size > 0L
                ? " (" + formatBytes(release.asset.size) + ")"
                : "";
        String message = getString(
                R.string.update_available_message,
                BuildConfig.VERSION_NAME,
                release.asset.name,
                sizeSuffix
        );
        Dialog dialog = new Dialog(activity);
        dialog.requestWindowFeature(Window.FEATURE_NO_TITLE);
        dialog.setContentView(R.layout.dialog_update_available);
        TextView title = dialog.findViewById(R.id.dialog_title);
        TextView messageView = dialog.findViewById(R.id.dialog_message);
        title.setText(getString(
                R.string.update_available_title,
                release.version
        ));
        messageView.setText(message);
        dialog.findViewById(R.id.dialog_cancel)
                .setOnClickListener(view -> dialog.dismiss());
        Button githubButton = dialog.findViewById(R.id.button_view_github);
        if (release.pageUrl.isEmpty()) {
            githubButton.setVisibility(View.GONE);
        } else {
            githubButton.setOnClickListener(view -> {
                view.performHapticFeedback(HapticFeedbackConstants.VIRTUAL_KEY);
                dialog.dismiss();
                openWebPage(release.pageUrl);
            });
        }
        dialog.findViewById(R.id.button_download_update)
                .setOnClickListener(view -> {
                    view.performHapticFeedback(HapticFeedbackConstants.VIRTUAL_KEY);
                    dialog.dismiss();
                    downloadUpdate(release);
                });
        showDialog(dialog);
    }

    private void downloadUpdate(ReleaseInfo release) {
        if (busy || release.asset == null) {
            return;
        }
        setBusy(true);
        statusView.setText(getString(
                R.string.update_downloading,
                release.version,
                0
        ));
        executor.execute(() -> {
            File destination = UpdateFileProvider.updateFile(activity);
            File partial = new File(
                    destination.getParentFile(),
                    destination.getName() + ".part"
            );
            try {
                downloadFile(release, partial);
                if (!verifyDownloadedApk(partial)) {
                    throw new UpdateException(
                            activity.getString(R.string.update_signature_mismatch)
                    );
                }
                if (destination.exists() && !destination.delete()) {
                    throw new UpdateException("无法替换旧安装包");
                }
                if (!partial.renameTo(destination)) {
                    throw new UpdateException("无法保存安装包");
                }
                mainHandler.post(() -> {
                    setBusy(false);
                    statusView.setText(R.string.update_download_complete);
                    requestInstall();
                });
            } catch (Exception error) {
                partial.delete();
                mainHandler.post(() -> showFailure(messageOf(error)));
            }
        });
    }

    private void downloadFile(ReleaseInfo release, File partial) throws Exception {
        HttpURLConnection connection = openConnection(new URL(release.asset.downloadUrl));
        connection.setRequestProperty("Accept", "application/octet-stream");
        int responseCode = connection.getResponseCode();
        if (responseCode != HttpURLConnection.HTTP_OK) {
            connection.disconnect();
            throw new UpdateException("APK 下载 HTTP " + responseCode);
        }

        long expectedSize = connection.getContentLengthLong();
        if (expectedSize > MAX_APK_BYTES || release.asset.size > MAX_APK_BYTES) {
            connection.disconnect();
            throw new UpdateException("安装包体积异常");
        }
        long totalSize = expectedSize > 0L ? expectedSize : release.asset.size;
        long downloaded = 0L;
        int lastPercent = -1;
        try (
                InputStream input = new BufferedInputStream(
                        connection.getInputStream()
                );
                BufferedOutputStream output = new BufferedOutputStream(
                        new FileOutputStream(partial)
                )
        ) {
            byte[] buffer = new byte[32 * 1024];
            int count;
            while ((count = input.read(buffer)) != -1) {
                downloaded += count;
                if (downloaded > MAX_APK_BYTES) {
                    throw new UpdateException("安装包体积异常");
                }
                output.write(buffer, 0, count);
                if (totalSize > 0L) {
                    int percent = (int) Math.min(
                            100L,
                            downloaded * 100L / totalSize
                    );
                    if (percent != lastPercent) {
                        lastPercent = percent;
                        int progress = percent;
                        mainHandler.post(() -> statusView.setText(getString(
                                R.string.update_downloading,
                                release.version,
                                progress
                        )));
                    }
                }
            }
        } finally {
            connection.disconnect();
        }
        if (downloaded == 0L) {
            throw new UpdateException("下载内容为空");
        }
    }

    private boolean verifyDownloadedApk(File apk) throws Exception {
        PackageManager packageManager = activity.getPackageManager();
        int flags = Build.VERSION.SDK_INT >= Build.VERSION_CODES.P
                ? PackageManager.GET_SIGNING_CERTIFICATES
                : PackageManager.GET_SIGNATURES;
        PackageInfo archive = packageManager.getPackageArchiveInfo(
                apk.getAbsolutePath(),
                flags
        );
        PackageInfo current = packageManager.getPackageInfo(
                activity.getPackageName(),
                flags
        );
        if (archive == null
                || !activity.getPackageName().equals(archive.packageName)) {
            return false;
        }
        Set<String> currentDigests = signingDigests(current);
        Set<String> archiveDigests = signingDigests(archive);
        return !currentDigests.isEmpty()
                && currentDigests.equals(archiveDigests);
    }

    @SuppressWarnings("deprecation")
    private Set<String> signingDigests(PackageInfo packageInfo) throws Exception {
        Signature[] signatures;
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
            if (packageInfo.signingInfo == null) {
                return new HashSet<>();
            }
            signatures = packageInfo.signingInfo.hasMultipleSigners()
                    ? packageInfo.signingInfo.getApkContentsSigners()
                    : packageInfo.signingInfo.getSigningCertificateHistory();
        } else {
            signatures = packageInfo.signatures;
        }
        Set<String> digests = new HashSet<>();
        if (signatures == null) {
            return digests;
        }
        MessageDigest digest = MessageDigest.getInstance("SHA-256");
        for (Signature signature : signatures) {
            byte[] hash = digest.digest(signature.toByteArray());
            digests.add(bytesToHex(hash));
        }
        return digests;
    }

    private void requestInstall() {
        if (!canInstallPackages()) {
            preferences.edit().putBoolean(KEY_PENDING_INSTALL, true).apply();
            Toast.makeText(
                    activity,
                    R.string.update_install_permission,
                    Toast.LENGTH_LONG
            ).show();
            Intent intent = new Intent(
                    Settings.ACTION_MANAGE_UNKNOWN_APP_SOURCES,
                    Uri.parse("package:" + activity.getPackageName())
            );
            try {
                activity.startActivity(intent);
            } catch (RuntimeException error) {
                preferences.edit().putBoolean(KEY_PENDING_INSTALL, false).apply();
                showFailure(activity.getString(R.string.update_install_failed));
            }
            return;
        }
        openInstaller();
    }

    private boolean canInstallPackages() {
        return activity.getPackageManager().canRequestPackageInstalls();
    }

    private void openInstaller() {
        File apk = UpdateFileProvider.updateFile(activity);
        if (!apk.isFile()) {
            showFailure(activity.getString(R.string.update_install_failed));
            return;
        }
        Intent intent = new Intent(Intent.ACTION_VIEW)
                .setDataAndType(UpdateFileProvider.updateUri(activity), APK_MIME)
                .addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION);
        try {
            activity.startActivity(intent);
        } catch (RuntimeException error) {
            showFailure(activity.getString(R.string.update_install_failed));
        }
    }

    private void showRepositoryDialog() {
        Dialog dialog = new Dialog(activity);
        dialog.requestWindowFeature(Window.FEATURE_NO_TITLE);
        dialog.setContentView(R.layout.dialog_update_repository);
        EditText dialogInput = dialog.findViewById(R.id.input_update_repository);
        dialogInput.setInputType(InputType.TYPE_CLASS_TEXT
                | InputType.TYPE_TEXT_VARIATION_URI);
        dialogInput.setText(repository());
        dialogInput.setSelection(dialogInput.length());
        dialog.findViewById(R.id.dialog_cancel)
                .setOnClickListener(view -> dialog.dismiss());
        dialog.findViewById(R.id.dialog_save)
                .setOnClickListener(view -> {
                    view.performHapticFeedback(HapticFeedbackConstants.VIRTUAL_KEY);
                    String value = normalizeRepository(
                            dialogInput.getText().toString()
                    );
                    if (!isValidRepository(value)) {
                        dialogInput.setError(activity.getString(
                                R.string.update_repo_invalid
                        ));
                        return;
                    }
                    preferences.edit().putString(KEY_REPOSITORY, value).apply();
                    renderRepositoryStatus();
                    dialog.dismiss();
                    checkForUpdates();
                });
        showDialog(dialog);
    }

    private void renderRepositoryStatus() {
        if (busy) {
            return;
        }
        String repository = repository();
        if (repository.isEmpty()) {
            statusView.setText(getString(
                    R.string.update_repo_missing,
                    BuildConfig.VERSION_NAME
            ));
        } else {
            statusView.setText(getString(
                    R.string.update_repo_ready,
                    BuildConfig.VERSION_NAME,
                    repository
            ));
        }
    }

    private void showFailure(String message) {
        setBusy(false);
        statusView.setText(getString(R.string.update_failed, message));
        Toast.makeText(activity, message, Toast.LENGTH_LONG).show();
    }

    private void setBusy(boolean value) {
        busy = value;
        checkButton.setEnabled(!value);
        checkButton.setAlpha(value ? 0.58f : 1f);
    }

    private HttpURLConnection openConnection(URL url) throws Exception {
        HttpURLConnection connection = (HttpURLConnection) url.openConnection();
        connection.setConnectTimeout(15_000);
        connection.setReadTimeout(30_000);
        connection.setInstanceFollowRedirects(true);
        connection.setRequestProperty("User-Agent", "Check-in-Android");
        return connection;
    }

    private String readResponse(
            HttpURLConnection connection,
            int responseCode
    ) throws Exception {
        InputStream stream = responseCode >= 200 && responseCode < 400
                ? connection.getInputStream()
                : connection.getErrorStream();
        if (stream == null) {
            return "";
        }
        try (InputStream input = stream;
             ByteArrayOutputStream output = new ByteArrayOutputStream()) {
            byte[] buffer = new byte[8 * 1024];
            int count;
            while ((count = input.read(buffer)) != -1) {
                output.write(buffer, 0, count);
            }
            return output.toString(StandardCharsets.UTF_8.name());
        }
    }

    private void openWebPage(String url) {
        if (url == null || url.isEmpty()) {
            return;
        }
        try {
            activity.startActivity(new Intent(Intent.ACTION_VIEW, Uri.parse(url)));
        } catch (RuntimeException error) {
            showFailure(messageOf(error));
        }
    }

    private String repository() {
        String configured = normalizeRepository(
                preferences.getString(KEY_REPOSITORY, "")
        );
        if (isValidRepository(configured)) {
            return configured;
        }
        String defaultRepository = normalizeRepository(
                BuildConfig.DEFAULT_GITHUB_REPOSITORY
        );
        return isValidRepository(defaultRepository) ? defaultRepository : "";
    }

    private String normalizeRepository(String value) {
        if (value == null) {
            return "";
        }
        String normalized = value.trim();
        if (normalized.startsWith("https://github.com/")) {
            normalized = normalized.substring("https://github.com/".length());
        } else if (normalized.startsWith("http://github.com/")) {
            normalized = normalized.substring("http://github.com/".length());
        }
        while (normalized.endsWith("/")) {
            normalized = normalized.substring(0, normalized.length() - 1);
        }
        if (normalized.endsWith(".git")) {
            normalized = normalized.substring(0, normalized.length() - 4);
        }
        return normalized;
    }

    private boolean isValidRepository(String repository) {
        return REPOSITORY_PATTERN.matcher(repository).matches();
    }

    private String normalizeVersion(String version) {
        if (version == null) {
            return "";
        }
        String normalized = version.trim();
        if (normalized.startsWith("v") || normalized.startsWith("V")) {
            normalized = normalized.substring(1);
        }
        return normalized.matches("[0-9]+(?:\\.[0-9]+){0,3}(?:[-+].*)?")
                ? normalized
                : "";
    }

    private int compareVersions(String left, String right) {
        int[] leftParts = numericVersion(left);
        int[] rightParts = numericVersion(right);
        int count = Math.max(leftParts.length, rightParts.length);
        for (int index = 0; index < count; index++) {
            int leftValue = index < leftParts.length ? leftParts[index] : 0;
            int rightValue = index < rightParts.length ? rightParts[index] : 0;
            if (leftValue != rightValue) {
                return Integer.compare(leftValue, rightValue);
            }
        }
        return 0;
    }

    private int[] numericVersion(String value) {
        String base = normalizeVersion(value).split("[-+]", 2)[0];
        if (base.isEmpty()) {
            return new int[]{0};
        }
        return Arrays.stream(base.split("\\."))
                .mapToInt(part -> {
                    try {
                        return Integer.parseInt(part);
                    } catch (NumberFormatException ignored) {
                        return 0;
                    }
                })
                .toArray();
    }

    private String formatBytes(long bytes) {
        if (bytes < 1024L * 1024L) {
            return String.format(Locale.US, "%.1f KB", bytes / 1024f);
        }
        return String.format(
                Locale.US,
                "%.1f MB",
                bytes / (1024f * 1024f)
        );
    }

    private String bytesToHex(byte[] bytes) {
        StringBuilder builder = new StringBuilder(bytes.length * 2);
        for (byte value : bytes) {
            builder.append(String.format(Locale.US, "%02x", value & 0xff));
        }
        return builder.toString();
    }

    private String messageOf(Exception error) {
        String message = error.getMessage();
        return message == null || message.trim().isEmpty()
                ? error.getClass().getSimpleName()
                : message;
    }

    private String getString(int resourceId, Object... arguments) {
        return activity.getString(resourceId, arguments);
    }

    private void showDialog(Dialog dialog) {
        Window window = dialog.getWindow();
        if (window != null) {
            window.setBackgroundDrawable(new ColorDrawable(Color.TRANSPARENT));
            window.addFlags(WindowManager.LayoutParams.FLAG_DIM_BEHIND);
            WindowManager.LayoutParams params = window.getAttributes();
            params.dimAmount = 0.52f;
            window.setAttributes(params);
        }
        dialog.show();
        if (window != null) {
            int width = (int) (
                    activity.getResources().getDisplayMetrics().widthPixels
                            * 0.91f
            );
            window.setLayout(width, WindowManager.LayoutParams.WRAP_CONTENT);
        }
    }

    private static final class UpdateException extends Exception {
        private UpdateException(String message) {
            super(message);
        }
    }

    private static final class ReleaseInfo {
        private final String version;
        private final String pageUrl;
        private final AssetInfo asset;

        private ReleaseInfo(
                String version,
                String pageUrl,
                AssetInfo asset
        ) {
            this.version = version;
            this.pageUrl = pageUrl;
            this.asset = asset;
        }
    }

    private static final class AssetInfo {
        private final String name;
        private final String downloadUrl;
        private final long size;

        private AssetInfo(String name, String downloadUrl, long size) {
            this.name = name;
            this.downloadUrl = downloadUrl;
            this.size = size;
        }
    }
}
