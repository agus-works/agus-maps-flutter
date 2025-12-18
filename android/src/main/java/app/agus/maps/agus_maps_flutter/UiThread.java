package app.agus.maps.agus_maps_flutter;

import android.os.Handler;
import android.os.Looper;
import androidx.annotation.Keep;

/**
 * Helper class to execute tasks on the Android UI thread.
 * This is called from native code to post GUI tasks to the main thread.
 */
public class UiThread {
    private static final Handler sUiHandler = new Handler(Looper.getMainLooper());

    public static boolean isUiThread() {
        return Looper.getMainLooper().getThread() == Thread.currentThread();
    }

    /**
     * Executes something on UI thread. If called from UI thread then given task will be executed synchronously.
     *
     * @param task the code that must be executed on UI thread.
     */
    public static void run(Runnable task) {
        if (isUiThread())
            task.run();
        else
            sUiHandler.post(task);
    }

    /**
     * Executes something on UI thread after last message queued in the application's main looper.
     *
     * @param task the code that must be executed later on UI thread.
     */
    public static void runLater(Runnable task) {
        runLater(task, 0);
    }

    /**
     * Executes something on UI thread after a given delayMillis.
     *
     * @param task        the code that must be executed on UI thread after given delayMillis.
     * @param delayMillis The delayMillis until the code will be executed.
     */
    public static void runLater(Runnable task, long delayMillis) {
        sUiHandler.postDelayed(task, delayMillis);
    }

    /**
     * Cancels execution of the given task that was previously queued.
     *
     * @param task the code that must be cancelled.
     */
    public static void cancelDelayedTasks(Runnable task) {
        sUiHandler.removeCallbacks(task);
    }

    // Called from JNI to forward a task to the main thread.
    @Keep
    @SuppressWarnings("unused")
    public static void forwardToMainThread(final long taskPointer) {
        android.util.Log.d("AgusMapsFlutter", "UiThread.forwardToMainThread: taskPointer=" + taskPointer);
        runLater(() -> nativeProcessTask(taskPointer), 0);
    }

    // Native callback to execute the task
    private static native void nativeProcessTask(long taskPointer);
}
