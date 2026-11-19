package flutter.overlay.window.flutter_overlay_window;

import android.app.Activity;
import android.app.NotificationManager;
import android.content.Context;
import android.content.Intent;
import android.net.Uri;
import android.os.Build;
import android.provider.Settings;
import android.service.notification.StatusBarNotification;
import android.util.Log;
import android.view.WindowManager;

import androidx.annotation.NonNull;
import androidx.annotation.Nullable;
import androidx.annotation.RequiresApi;
import androidx.core.app.NotificationManagerCompat;

import java.util.ArrayList;
import java.util.HashMap;
import java.util.List;
import java.util.Map;

import android.content.pm.PackageManager;
import androidx.core.app.ActivityCompat;
import androidx.core.content.ContextCompat;

import io.flutter.FlutterInjector;
import io.flutter.embedding.engine.FlutterEngine;
import io.flutter.embedding.engine.FlutterEngineCache;
import io.flutter.embedding.engine.FlutterEngineGroup;
import io.flutter.embedding.engine.dart.DartExecutor;
import io.flutter.embedding.engine.plugins.FlutterPlugin;
import io.flutter.embedding.engine.plugins.activity.ActivityAware;
import io.flutter.embedding.engine.plugins.activity.ActivityPluginBinding;
import io.flutter.plugin.common.BasicMessageChannel;
import io.flutter.plugin.common.JSONMessageCodec;
import io.flutter.plugin.common.MethodCall;
import io.flutter.plugin.common.MethodChannel;
import io.flutter.plugin.common.MethodChannel.MethodCallHandler;
import io.flutter.plugin.common.MethodChannel.Result;
import io.flutter.plugin.common.PluginRegistry;

public class FlutterOverlayWindowPlugin implements
        FlutterPlugin, ActivityAware, BasicMessageChannel.MessageHandler, MethodCallHandler,
        PluginRegistry.ActivityResultListener, PluginRegistry.RequestPermissionsResultListener {

    private MethodChannel channel;
    private Context context;
    private Activity mActivity;
    private BasicMessageChannel<Object> messenger;
    private final WindowSetup windowSetup = WindowSetup.getInstance();
    private ActivityPluginBinding activityBinding;
    private Result pendingResult;
    final int REQUEST_CODE_FOR_OVERLAY_PERMISSION = 1248;
    // [Pet Life 新增] 麥克風／相機／通知的執行期權限
    final int REQUEST_CODE_FOR_RUNTIME = 1249;
    private Result pendingRuntime;
    private List<String> pendingRuntimePerms;

    @Override
    public void onAttachedToEngine(@NonNull FlutterPluginBinding flutterPluginBinding) {
        this.context = flutterPluginBinding.getApplicationContext();
        channel = new MethodChannel(flutterPluginBinding.getBinaryMessenger(), OverlayConstants.CHANNEL_TAG);
        channel.setMethodCallHandler(this);

        messenger = new BasicMessageChannel(flutterPluginBinding.getBinaryMessenger(), OverlayConstants.MESSENGER_TAG,
                JSONMessageCodec.INSTANCE);
        messenger.setMessageHandler(this);

        windowSetup.setMessenger(messenger);
        windowSetup.getMessenger().setMessageHandler(this);
    }

    @RequiresApi(api = Build.VERSION_CODES.N)
    @Override
    public void onMethodCall(@NonNull MethodCall call, @NonNull Result result) {
        if (call.method.equals("petCheckRuntime")) {
            List<String> perms = call.argument("perms");
            result.success(runtimeStatus(perms));
            return;
        } else if (call.method.equals("petRequestRuntime")) {
            List<String> perms = call.argument("perms");
            List<String> missing = new ArrayList<>();
            for (String p : perms) {
                if (ContextCompat.checkSelfPermission(context, p) != PackageManager.PERMISSION_GRANTED) missing.add(p);
            }
            if (missing.isEmpty()) {
                result.success(runtimeStatus(perms));
                return;
            }
            if (mActivity == null) {
                result.error("NO_ACTIVITY", "petRequestRuntime requires a foreground activity", null);
                return;
            }
            if (pendingRuntime != null) pendingRuntime.success(runtimeStatus(pendingRuntimePerms));
            pendingRuntime = result;
            pendingRuntimePerms = perms;
            ActivityCompat.requestPermissions(mActivity, missing.toArray(new String[0]), REQUEST_CODE_FOR_RUNTIME);
            return;
        } else if (call.method.equals("petOpenAppSettings")) {
            Intent intent = new Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS);
            intent.setData(Uri.parse("package:" + context.getPackageName()));
            intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK);
            context.startActivity(intent);
            result.success(true);
            return;
        } else if (call.method.equals("petSdkInt")) {
            result.success(Build.VERSION.SDK_INT);
            return;
        } else if (call.method.equals("checkPermission")) {
            result.success(checkOverlayPermission());
        } else if (call.method.equals("requestPermission")) {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
                if (checkOverlayPermission()) {
                    result.success(true);
                    return;
                }
                if (mActivity == null) {
                    result.error("NO_ACTIVITY", "requestPermission requires a foreground activity", null);
                    return;
                }
                if (pendingResult != null) {
                    pendingResult.success(checkOverlayPermission());
                }
                pendingResult = result;
                Intent intent = new Intent(Settings.ACTION_MANAGE_OVERLAY_PERMISSION);
                intent.setData(Uri.parse("package:" + mActivity.getPackageName()));
                mActivity.startActivityForResult(intent, REQUEST_CODE_FOR_OVERLAY_PERMISSION);
            } else {
                result.success(true);
            }
        } else if (call.method.equals("showOverlay")) {
            if (!checkOverlayPermission()) {
                result.error("PERMISSION", "overlay permission is not enabled", null);
                return;
            }
            Integer height = call.argument("height");
            Integer width = call.argument("width");
            String alignment = call.argument("alignment");
            String flag = call.argument("flag");
            String overlayTitle = call.argument("overlayTitle");
            String overlayContent = call.argument("overlayContent");
            String notificationVisibility = call.argument("notificationVisibility");
            String notificationIcon = call.argument("notificationIcon");
            boolean enableDrag = call.argument("enableDrag");
            Map<String, Object> dismissConfig = call.argument("dismissConfig");
            String positionGravity = call.argument("positionGravity");
            Map<String, Integer> startPosition = call.argument("startPosition");
            int startX = startPosition != null ? startPosition.getOrDefault("x", OverlayConstants.DEFAULT_XY) : OverlayConstants.DEFAULT_XY;
            int startY = startPosition != null ? startPosition.getOrDefault("y", OverlayConstants.DEFAULT_XY) : OverlayConstants.DEFAULT_XY;


            windowSetup.setWidth(width != null ? width : -1);
            windowSetup.setHeight(height != null ? height : -1);
            windowSetup.setEnableDrag(enableDrag);
            windowSetup.setDismissConfig(dismissConfig != null ? DismissConfig.fromMap(dismissConfig) : null);
            windowSetup.setGravityFromAlignment(alignment != null ? alignment : "center");
            windowSetup.setFlag(flag != null ? flag : "flagNotFocusable");
            windowSetup.setOverlayTitle(overlayTitle);
            windowSetup.setOverlayContent(overlayContent == null ? "" : overlayContent);
            windowSetup.setPositionGravity(positionGravity);
            windowSetup.setNotificationVisibility(notificationVisibility);
            windowSetup.setNotificationIcon(notificationIcon);

            final Intent intent = new Intent(context, OverlayService.class);
            intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK);
            intent.addFlags(Intent.FLAG_ACTIVITY_SINGLE_TOP);
            intent.putExtra("startX", startX);
            intent.putExtra("startY", startY);
            context.startService(intent);
            result.success(null);
        } else if (call.method.equals("updateNotification")) {
            String title = call.argument("title");
            String content = call.argument("content");
            String icon = call.argument("icon");
            if (title != null) windowSetup.setOverlayTitle(title);
            if (content != null) windowSetup.setOverlayContent(content);
            if (icon != null) windowSetup.setNotificationIcon(icon);
            result.success(OverlayService.updateNotification());
        } else if (call.method.equals("isOverlayActive")) {
            result.success(OverlayService.isRunning);
            return;
        } else if (call.method.equals("moveOverlay")) {
            int x = call.argument("x");
            int y = call.argument("y");
            result.success(OverlayService.moveOverlay(x, y));
        } else if (call.method.equals("getOverlayPosition")) {
            result.success(OverlayService.getCurrentPosition());
        } else if (call.method.equals("updateOverlay")) {
            int x = call.argument("x");
            int y = call.argument("y");
            int width = call.argument("width");
            int height = call.argument("height");
            boolean enableDrag = call.argument("enableDrag");
            result.success(OverlayService.updateOverlay(x, y, width, height, enableDrag));
        } else if (call.method.equals("getScreenSize")) {
            result.success(OverlayService.getScreenSize());
        } else if (call.method.equals("closeOverlay")) {
            if (OverlayService.isRunning) {
                final Intent i = new Intent(context, OverlayService.class);
                context.stopService(i);
                result.success(true);
            } else {
                result.success(false);
            }
            return;
        } else if (call.method.equals("setOverlayVisible")) {
            Boolean visible = call.argument("visible");
            if (visible == null) {
                result.error("INVALID_ARGUMENT", "visible is required", null);
                return;
            }
            result.success(OverlayService.setOverlayVisible(visible));
        } else {
            result.notImplemented();
        }

    }

    @Override
    public void onDetachedFromEngine(@NonNull FlutterPluginBinding binding) {
        channel.setMethodCallHandler(null);
        windowSetup.getMessenger().setMessageHandler(null);
    }

    @Override
    public void onAttachedToActivity(@NonNull ActivityPluginBinding binding) {
        attachToActivity(binding);
        if (FlutterEngineCache.getInstance().get(OverlayConstants.CACHED_TAG) == null) {
            FlutterEngineGroup enn = new FlutterEngineGroup(context);
            DartExecutor.DartEntrypoint dEntry = new DartExecutor.DartEntrypoint(
                    FlutterInjector.instance().flutterLoader().findAppBundlePath(),
                    "overlayMain");
            FlutterEngine engine = enn.createAndRunEngine(context, dEntry);
            FlutterEngineCache.getInstance().put(OverlayConstants.CACHED_TAG, engine);
        }
    }

    @Override
    public void onDetachedFromActivityForConfigChanges() {
        detachFromActivity();
    }

    @Override
    public void onReattachedToActivityForConfigChanges(@NonNull ActivityPluginBinding binding) {
        attachToActivity(binding);
    }

    @Override
    public void onDetachedFromActivity() {
        detachFromActivity();
    }

    private void attachToActivity(@NonNull ActivityPluginBinding binding) {
        activityBinding = binding;
        mActivity = binding.getActivity();
        binding.addActivityResultListener(this);
        binding.addRequestPermissionsResultListener(this);
    }

    private void detachFromActivity() {
        if (activityBinding != null) {
            activityBinding.removeActivityResultListener(this);
            activityBinding.removeRequestPermissionsResultListener(this);
            activityBinding = null;
        }
        mActivity = null;
    }

    @Override
    public void onMessage(@Nullable Object message, @NonNull BasicMessageChannel.Reply reply) {
        BasicMessageChannel overlayMessageChannel = new BasicMessageChannel(
                FlutterEngineCache.getInstance().get(OverlayConstants.CACHED_TAG)
                        .getDartExecutor(),
                OverlayConstants.MESSENGER_TAG, JSONMessageCodec.INSTANCE);
        overlayMessageChannel.send(message, reply);
    }

    private boolean checkOverlayPermission() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
            return Settings.canDrawOverlays(context);
        }
        return true;
    }

    @Override
    public boolean onActivityResult(int requestCode, int resultCode, Intent data) {
        if (requestCode == REQUEST_CODE_FOR_OVERLAY_PERMISSION) {
            if (pendingResult != null) {
                pendingResult.success(checkOverlayPermission());
                pendingResult = null;
            }
            return true;
        }
        return false;
    }


    private Map<String, Boolean> runtimeStatus(List<String> perms) {
        Map<String, Boolean> out = new HashMap<>();
        if (perms == null) return out;
        for (String p : perms) {
            out.put(p, ContextCompat.checkSelfPermission(context, p) == PackageManager.PERMISSION_GRANTED);
        }
        return out;
    }

    @Override
    public boolean onRequestPermissionsResult(int requestCode, @NonNull String[] permissions, @NonNull int[] grantResults) {
        if (requestCode != REQUEST_CODE_FOR_RUNTIME) return false;
        if (pendingRuntime != null) {
            pendingRuntime.success(runtimeStatus(pendingRuntimePerms));
            pendingRuntime = null;
            pendingRuntimePerms = null;
        }
        return true;
    }
}
