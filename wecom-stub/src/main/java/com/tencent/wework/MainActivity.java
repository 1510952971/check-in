package com.tencent.wework;

import android.app.Activity;
import android.graphics.Color;
import android.os.Bundle;
import android.view.Gravity;
import android.widget.LinearLayout;
import android.widget.TextView;

import java.time.LocalDateTime;
import java.time.format.DateTimeFormatter;
import java.util.Locale;

public class MainActivity extends Activity {
    @Override
    protected void onCreate(Bundle savedInstanceState) {
        super.onCreate(savedInstanceState);

        LinearLayout root = new LinearLayout(this);
        root.setOrientation(LinearLayout.VERTICAL);
        root.setGravity(Gravity.CENTER);
        root.setPadding(48, 48, 48, 48);
        root.setBackgroundColor(Color.rgb(238, 250, 246));

        TextView title = new TextView(this);
        title.setText("企业微信测试替身");
        title.setTextColor(Color.rgb(20, 55, 51));
        title.setTextSize(28);
        title.setGravity(Gravity.CENTER);

        TextView message = new TextView(this);
        message.setText("打卡准点已成功打开目标应用");
        message.setTextColor(Color.rgb(55, 90, 85));
        message.setTextSize(17);
        message.setGravity(Gravity.CENTER);
        message.setPadding(0, 28, 0, 0);

        TextView time = new TextView(this);
        String now = DateTimeFormatter.ofPattern(
                "yyyy-MM-dd HH:mm:ss",
                Locale.US
        ).format(LocalDateTime.now());
        time.setText(now);
        time.setTextColor(Color.rgb(8, 126, 120));
        time.setTextSize(16);
        time.setGravity(Gravity.CENTER);
        time.setPadding(0, 16, 0, 0);

        root.addView(title);
        root.addView(message);
        root.addView(time);
        setContentView(root);
    }
}
