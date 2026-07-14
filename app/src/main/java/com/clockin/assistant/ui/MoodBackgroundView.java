package com.clockin.assistant.ui;

import android.content.Context;
import android.graphics.Canvas;
import android.graphics.Color;
import android.graphics.LinearGradient;
import android.graphics.Matrix;
import android.graphics.Paint;
import android.graphics.RadialGradient;
import android.graphics.Shader;
import android.util.AttributeSet;
import android.view.View;

public class MoodBackgroundView extends View {
    private static final long FRAME_DELAY_MILLIS = 48L;
    private static final int FIELD_COUNT = 3;

    private final Paint paint = new Paint(Paint.ANTI_ALIAS_FLAG);
    private final RadialGradient[] dayFields = new RadialGradient[FIELD_COUNT];
    private final RadialGradient[] nightFields = new RadialGradient[FIELD_COUNT];
    private final float[] fieldRadii = new float[FIELD_COUNT];
    private final Matrix[] fieldMatrices = {
            new Matrix(),
            new Matrix(),
            new Matrix()
    };
    private final Runnable frame = new Runnable() {
        @Override
        public void run() {
            phase += 0.0065f;
            if (phase > 1f) {
                phase -= 1f;
            }
            modeMix += (targetModeMix - modeMix) * 0.085f;
            invalidate();
            postDelayed(this, FRAME_DELAY_MILLIS);
        }
    };

    private LinearGradient dayBase;
    private LinearGradient nightBase;
    private float phase;
    private float modeMix;
    private float targetModeMix;
    private int moodIndex;
    private boolean modeInitialized;
    private boolean running;

    public MoodBackgroundView(Context context) {
        super(context);
        initialize();
    }

    public MoodBackgroundView(Context context, AttributeSet attrs) {
        super(context, attrs);
        initialize();
    }

    public MoodBackgroundView(Context context, AttributeSet attrs, int defStyleAttr) {
        super(context, attrs, defStyleAttr);
        initialize();
    }

    private void initialize() {
        setLayerType(LAYER_TYPE_HARDWARE, null);
    }

    public void setNightMode(boolean night) {
        targetModeMix = night ? 1f : 0f;
        if (!modeInitialized) {
            modeInitialized = true;
            modeMix = targetModeMix;
        }
        invalidate();
    }

    public void setMoodIndex(int moodIndex) {
        int nextMood = Math.max(0, Math.min(3, moodIndex));
        if (this.moodIndex == nextMood) {
            return;
        }
        this.moodIndex = nextMood;
        if (fieldRadii[0] > 0f) {
            rebuildFieldShaders();
        }
        invalidate();
    }

    @Override
    protected void onSizeChanged(int width, int height, int oldWidth, int oldHeight) {
        super.onSizeChanged(width, height, oldWidth, oldHeight);
        dayBase = new LinearGradient(
                0f,
                0f,
                width,
                height,
                Color.rgb(255, 243, 176),
                Color.rgb(202, 236, 255),
                Shader.TileMode.CLAMP
        );
        nightBase = new LinearGradient(
                0f,
                0f,
                width,
                height,
                Color.rgb(8, 13, 22),
                Color.rgb(18, 25, 38),
                Shader.TileMode.CLAMP
        );
        float radius = Math.max(width, height) * 0.74f;
        fieldRadii[0] = radius;
        fieldRadii[1] = radius * 0.92f;
        fieldRadii[2] = radius;
        rebuildFieldShaders();
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
    protected void onWindowVisibilityChanged(int visibility) {
        super.onWindowVisibilityChanged(visibility);
        if (visibility == VISIBLE) {
            startAnimation();
        } else {
            stopAnimation();
        }
    }

    @Override
    protected void onDraw(Canvas canvas) {
        super.onDraw(canvas);
        float width = getWidth();
        float height = getHeight();
        if (width <= 0f || height <= 0f || dayBase == null || nightBase == null) {
            return;
        }

        int dayAlpha = Math.round(255f * (1f - modeMix));
        int nightAlpha = Math.round(255f * modeMix);
        drawBase(canvas, dayBase, dayAlpha, width, height);
        drawBase(canvas, nightBase, nightAlpha, width, height);

        float wave = (float) (phase * Math.PI * 2.0);
        float radius = Math.max(width, height) * 0.74f;
        drawFieldPair(
                canvas,
                0,
                width * (0.18f + 0.09f * (float) Math.sin(wave)),
                height * (0.12f + 0.05f * (float) Math.cos(wave * 0.8f)),
                radius,
                dayAlpha,
                nightAlpha
        );
        drawFieldPair(
                canvas,
                1,
                width * (0.82f + 0.08f * (float) Math.cos(wave * 0.7f)),
                height * (0.33f + 0.07f * (float) Math.sin(wave * 0.9f)),
                radius * 0.92f,
                dayAlpha,
                nightAlpha
        );
        drawFieldPair(
                canvas,
                2,
                width * (0.35f + 0.12f * (float) Math.cos(wave * 0.55f)),
                height * (0.77f + 0.06f * (float) Math.sin(wave * 0.65f)),
                radius,
                dayAlpha,
                nightAlpha
        );

        paint.setShader(null);
        paint.setAlpha(255);
        paint.setColor(Color.argb(Math.round(modeMix * 16f), 0, 0, 0));
        canvas.drawRect(0f, 0f, width, height, paint);
    }

    private void drawBase(
            Canvas canvas,
            LinearGradient shader,
            int alpha,
            float width,
            float height
    ) {
        if (alpha <= 0) {
            return;
        }
        paint.setShader(shader);
        paint.setAlpha(alpha);
        canvas.drawRect(0f, 0f, width, height, paint);
    }

    private void drawFieldPair(
            Canvas canvas,
            int index,
            float centerX,
            float centerY,
            float radius,
            int dayAlpha,
            int nightAlpha
    ) {
        Matrix matrix = fieldMatrices[index];
        matrix.setTranslate(centerX, centerY);
        if (dayAlpha > 0) {
            dayFields[index].setLocalMatrix(matrix);
            paint.setShader(dayFields[index]);
            paint.setAlpha(dayAlpha);
            canvas.drawCircle(centerX, centerY, radius, paint);
        }
        if (nightAlpha > 0) {
            nightFields[index].setLocalMatrix(matrix);
            paint.setShader(nightFields[index]);
            paint.setAlpha(nightAlpha);
            canvas.drawCircle(centerX, centerY, radius, paint);
        }
    }

    private void rebuildFieldShaders() {
        int dayMood = moodIndex == 1
                ? Color.rgb(255, 190, 92)
                : Color.rgb(202, 236, 255);
        int[] nightMoodColors = {
                Color.rgb(0, 214, 180),
                Color.rgb(66, 228, 164),
                Color.rgb(0, 245, 212),
                Color.rgb(104, 255, 202)
        };
        int nightMood = nightMoodColors[moodIndex];
        dayFields[0] = radial(Color.rgb(255, 159, 28), 178, fieldRadii[0]);
        dayFields[1] = radial(Color.rgb(101, 214, 166), 166, fieldRadii[1]);
        dayFields[2] = radial(dayMood, 150, fieldRadii[2]);
        nightFields[0] = radial(Color.rgb(42, 91, 224), 205, fieldRadii[0]);
        nightFields[1] = radial(Color.rgb(138, 43, 226), 218, fieldRadii[1]);
        nightFields[2] = radial(nightMood, 205, fieldRadii[2]);
    }

    private RadialGradient radial(int color, int alpha, float radius) {
        int center = Color.argb(
                alpha,
                Color.red(color),
                Color.green(color),
                Color.blue(color)
        );
        int edge = Color.argb(
                0,
                Color.red(color),
                Color.green(color),
                Color.blue(color)
        );
        return new RadialGradient(
                0f,
                0f,
                radius,
                center,
                edge,
                Shader.TileMode.CLAMP
        );
    }

    private void startAnimation() {
        if (running) {
            return;
        }
        running = true;
        removeCallbacks(frame);
        post(frame);
    }

    private void stopAnimation() {
        running = false;
        removeCallbacks(frame);
    }
}
