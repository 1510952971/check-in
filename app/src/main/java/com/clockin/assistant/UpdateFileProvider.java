package com.clockin.assistant;

import android.content.ContentProvider;
import android.content.ContentValues;
import android.database.Cursor;
import android.database.MatrixCursor;
import android.net.Uri;
import android.os.ParcelFileDescriptor;
import android.provider.OpenableColumns;

import java.io.File;
import java.io.FileNotFoundException;

/**
 * Read-only content provider that grants the Android package installer access
 * to the one APK downloaded by {@link GitHubUpdateManager}.
 */
public class UpdateFileProvider extends ContentProvider {
    private static final String UPDATE_PATH = "clockin-update.apk";
    private static final String APK_MIME =
            "application/vnd.android.package-archive";

    public static File updateFile(android.content.Context context) {
        File directory = context.getExternalFilesDir(
                android.os.Environment.DIRECTORY_DOWNLOADS
        );
        if (directory == null) {
            directory = new File(context.getFilesDir(), "updates");
        }
        if (!directory.exists()) {
            directory.mkdirs();
        }
        return new File(directory, UPDATE_PATH);
    }

    public static Uri updateUri(android.content.Context context) {
        return new Uri.Builder()
                .scheme("content")
                .authority(context.getPackageName() + ".updates")
                .appendPath(UPDATE_PATH)
                .build();
    }

    @Override
    public boolean onCreate() {
        return true;
    }

    @Override
    public String getType(Uri uri) {
        return APK_MIME;
    }

    @Override
    public Cursor query(
            Uri uri,
            String[] projection,
            String selection,
            String[] selectionArgs,
            String sortOrder
    ) {
        File file = verifiedFile(uri);
        String[] columns = projection == null
                ? new String[]{OpenableColumns.DISPLAY_NAME, OpenableColumns.SIZE}
                : projection;
        MatrixCursor cursor = new MatrixCursor(columns, 1);
        MatrixCursor.RowBuilder row = cursor.newRow();
        for (String column : columns) {
            if (OpenableColumns.DISPLAY_NAME.equals(column)) {
                row.add("check-in-update.apk");
            } else if (OpenableColumns.SIZE.equals(column)) {
                row.add(file.length());
            } else {
                row.add(null);
            }
        }
        return cursor;
    }

    @Override
    public ParcelFileDescriptor openFile(Uri uri, String mode)
            throws FileNotFoundException {
        if (!"r".equals(mode)) {
            throw new FileNotFoundException("Read-only update provider");
        }
        return ParcelFileDescriptor.open(
                verifiedFile(uri),
                ParcelFileDescriptor.MODE_READ_ONLY
        );
    }

    @Override
    public Uri insert(Uri uri, ContentValues values) {
        throw new UnsupportedOperationException("Read-only update provider");
    }

    @Override
    public int delete(Uri uri, String selection, String[] selectionArgs) {
        return 0;
    }

    @Override
    public int update(
            Uri uri,
            ContentValues values,
            String selection,
            String[] selectionArgs
    ) {
        return 0;
    }

    private File verifiedFile(Uri uri) {
        if (getContext() == null
                || uri == null
                || !UPDATE_PATH.equals(uri.getLastPathSegment())) {
            throw new IllegalArgumentException("Unknown update URI");
        }
        File file = updateFile(getContext());
        if (!file.isFile()) {
            throw new IllegalArgumentException("Update APK is missing");
        }
        return file;
    }
}
