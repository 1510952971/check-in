package com.clockin.assistant.ui;

import android.animation.ValueAnimator;
import android.content.Context;
import android.graphics.Canvas;
import android.graphics.Color;
import android.graphics.LinearGradient;
import android.graphics.Paint;
import android.graphics.RectF;
import android.graphics.Shader;
import android.util.AttributeSet;
import android.view.HapticFeedbackConstants;
import android.view.View;
import android.view.animation.DecelerateInterpolator;

public class GlowToggleView extends View {
    public interface OnCheckedChangeListener {
        void onCheckedChanged(boolean checked);
    }

    private final Paint paint = new Paint(Paint.ANTI_ALIAS_FLAG);
    private final RectF track = new RectF();
    private LinearGradient onGradient;
    private float thumbPosition;
    private boolean checked;
    private OnCheckedChangeListener listener;
    private ValueAnimator animator;

    public GlowToggleView(Context context) {
        super(context);
        initialize();
    }

    public GlowToggleView(Context context, AttributeSet attrs) {
        super(context, attrs);
        initialize();
    }

    public GlowToggleView(Context context, AttributeSet attrs, int defStyleAttr) {
        super(context, attrs, defStyleAttr);
        initialize();
    }

    private void initialize() {
        setClickable(true);
        setFocusable(true);
        setLayerType(LAYER_TYPE_SOFTWARE, null);
        setOnClickListener(view -> {
            performHapticFeedback(HapticFeedbackConstants.VIRTUAL_KEY);
            setChecked(!checked, true);
            if (listener != null) {
                listener.onCheckedChanged(checked);
            }
        });
    }

    public void setOnCheckedChangeListener(OnCheckedChangeListener listener) {
        this.listener = listener;
    }

    public void setChecked(boolean checked) {
        setChecked(checked, false);
    }

    public void setChecked(boolean checked, boolean animate) {
        if (this.checked == checked && !animate) {
            thumbPosition = checked ? 1f : 0f;
            invalidate();
            return;
        }
        this.checked = checked;
        setSelected(checked);
        setContentDescription(checked ? "自动打卡运行中" : "自动打卡已暂停");
        float target = checked ? 1f : 0f;
        if (!animate) {
            thumbPosition = target;
            invalidate();
            return;
        }
        if (animator != null) {
            animator.cancel();
        }
        animator = ValueAnimator.ofFloat(thumbPosition, target);
        animator.setDuration(260L);
        animator.setInterpolator(new DecelerateInterpolator());
        animator.addUpdateListener(valueAnimator -> {
            thumbPosition = (float) valueAnimator.getAnimatedValue();
            invalidate();
        });
        animator.start();
    }

    public boolean isChecked() {
        return checked;
    }

    @Override
    protected void onSizeChanged(int width, int height, int oldWidth, int oldHeight) {
        super.onSizeChanged(width, height, oldWidth, oldHeight);
        float inset = dp(5f);
        onGradient = new LinearGradient(
                inset,
                inset,
                width - inset,
                height - inset,
                Color.rgb(0, 116, 111),
                Color.rgb(0, 245, 212),
                Shader.TileMode.CLAMP
        );
    }

    @Override
    protected void onDraw(Canvas canvas) {
        super.onDraw(canvas);
        float width = getWidth();
        float height = getHeight();
        float inset = dp(5f);
        float radius = (height - inset * 2f) / 2f;
        track.set(inset, inset, width - inset, height - inset);

        int offColor = Color.argb(145, 255, 255, 255);
        if (checked || thumbPosition > 0.05f) {
            paint.setShader(onGradient);
            paint.setShadowLayer(dp(12f) * thumbPosition, 0f, 0f, Color.argb(155, 0, 245, 212));
        } else {
            paint.setShader(null);
            paint.setColor(offColor);
            paint.clearShadowLayer();
        }
        canvas.drawRoundRect(track, radius, radius, paint);

        paint.clearShadowLayer();
        paint.setShader(null);
        paint.setStyle(Paint.Style.STROKE);
        paint.setStrokeWidth(dp(1f));
        paint.setColor(Color.argb(175, 255, 255, 255));
        canvas.drawRoundRect(track, radius, radius, paint);
        paint.setStyle(Paint.Style.FILL);

        float minX = track.left + radius;
        float maxX = track.right - radius;
        float centerX = minX + (maxX - minX) * thumbPosition;
        float centerY = track.centerY();
        paint.setColor(Color.WHITE);
        paint.setShadowLayer(dp(7f), 0f, dp(3f), Color.argb(95, 0, 0, 0));
        canvas.drawCircle(centerX, centerY, radius - dp(2f), paint);
        paint.clearShadowLayer();

        paint.setColor(Color.argb(85, 255, 255, 255));
        canvas.drawCircle(
                centerX - radius * 0.25f,
                centerY - radius * 0.28f,
                radius * 0.24f,
                paint
        );
    }

    private float dp(float value) {
        return value * getResources().getDisplayMetrics().density;
    }
}
