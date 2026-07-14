package com.clockin.assistant.ui;

import android.content.Context;
import android.graphics.Canvas;
import android.graphics.Color;
import android.graphics.LinearGradient;
import android.graphics.Matrix;
import android.graphics.Paint;
import android.graphics.RectF;
import android.graphics.Shader;
import android.util.AttributeSet;
import android.view.View;

public class ShiftProgressView extends View {
    private static final long FRAME_DELAY_MILLIS = 42L;

    private final Paint paint = new Paint(Paint.ANTI_ALIAS_FLAG);
    private final RectF rect = new RectF();
    private final Matrix progressMatrix = new Matrix();
    private final Matrix shimmerMatrix = new Matrix();
    private final LinearGradient progressShader = new LinearGradient(
            0f,
            0f,
            1f,
            0f,
            new int[]{
                    Color.rgb(0, 245, 212),
                    Color.rgb(102, 227, 255),
                    Color.rgb(171, 106, 255)
            },
            null,
            Shader.TileMode.CLAMP
    );
    private final LinearGradient shimmerShader = new LinearGradient(
            0f,
            0f,
            1f,
            0f,
            Color.argb(0, 255, 255, 255),
            Color.argb(205, 255, 255, 255),
            Shader.TileMode.MIRROR
    );
    private final Runnable frame = new Runnable() {
        @Override
        public void run() {
            shimmer += 0.018f;
            if (shimmer > 1f) {
                shimmer -= 1f;
            }
            invalidate();
            postDelayed(this, FRAME_DELAY_MILLIS);
        }
    };

    private float progress;
    private float shimmer;
    private boolean running;

    public ShiftProgressView(Context context) {
        super(context);
    }

    public ShiftProgressView(Context context, AttributeSet attrs) {
        super(context, attrs);
    }

    public ShiftProgressView(Context context, AttributeSet attrs, int defStyleAttr) {
        super(context, attrs, defStyleAttr);
    }

    public void setProgress(float progress) {
        this.progress = Math.max(0.04f, Math.min(1f, progress));
        invalidate();
    }

    @Override
    protected void onAttachedToWindow() {
        super.onAttachedToWindow();
        startAnimation();
    }

    @Override
    protected void onDetachedFromWindow() {
        stopAnimation();
        super.onDetachedFromWindow();
    }

    @Override
    protected void onDraw(Canvas canvas) {
        super.onDraw(canvas);
        float width = getWidth();
        float height = getHeight();
        float radius = height / 2f;
        rect.set(0f, 0f, width, height);

        paint.setShader(null);
        paint.setColor(Color.argb(55, 255, 255, 255));
        canvas.drawRoundRect(rect, radius, radius, paint);

        float progressWidth = Math.max(height, width * progress);
        rect.set(0f, 0f, progressWidth, height);
        progressMatrix.setScale(progressWidth, 1f);
        progressShader.setLocalMatrix(progressMatrix);
        paint.setShader(progressShader);
        canvas.drawRoundRect(rect, radius, radius, paint);

        float lightWidth = Math.max(dp(32f), progressWidth * 0.32f);
        float lightCenter = -lightWidth + (progressWidth + lightWidth * 2f) * shimmer;
        float left = Math.max(0f, lightCenter - lightWidth);
        float right = Math.min(progressWidth, lightCenter + lightWidth);
        if (right > left) {
            rect.set(left, 0f, right, height);
            shimmerMatrix.setScale(right - left, 1f);
            shimmerMatrix.postTranslate(left, 0f);
            shimmerShader.setLocalMatrix(shimmerMatrix);
            paint.setShader(shimmerShader);
            canvas.drawRoundRect(rect, radius, radius, paint);
        }
        paint.setShader(null);
    }

    private void startAnimation() {
        if (running) {
            return;
        }
        running = true;
        post(frame);
    }

    private void stopAnimation() {
        running = false;
        removeCallbacks(frame);
    }

    private float dp(float value) {
        return value * getResources().getDisplayMetrics().density;
    }
}
