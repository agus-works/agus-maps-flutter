#include "agus_gui_thread.hpp"
#include "base/logging.hpp"
#include <android/log.h>
#include <memory>
#include <mutex>

// Store JavaVM globally for getting JNIEnv from any thread
// This is shared with agus_maps_flutter.cpp
JavaVM* g_javaVM = nullptr;
static jclass g_uiThreadClass = nullptr;
static jmethodID g_forwardMethod = nullptr;
static std::mutex g_jniMutex;

extern "C" JNIEXPORT jint JNICALL JNI_OnLoad(JavaVM* vm, void* reserved) {
    g_javaVM = vm;
    __android_log_print(ANDROID_LOG_DEBUG, "AgusGuiThread", "JNI_OnLoad: JavaVM stored");
    
    // Initialize class and method references on load
    JNIEnv* env = nullptr;
    if (vm->GetEnv(reinterpret_cast<void**>(&env), JNI_VERSION_1_6) != JNI_OK) {
        __android_log_print(ANDROID_LOG_ERROR, "AgusGuiThread", "JNI_OnLoad: Failed to get JNIEnv");
        return JNI_VERSION_1_6;
    }
    
    jclass localClass = env->FindClass("app/agus/maps/agus_maps_flutter/UiThread");
    if (localClass == nullptr) {
        __android_log_print(ANDROID_LOG_ERROR, "AgusGuiThread", "JNI_OnLoad: Failed to find UiThread class");
        env->ExceptionClear();
        return JNI_VERSION_1_6;
    }
    
    g_uiThreadClass = static_cast<jclass>(env->NewGlobalRef(localClass));
    env->DeleteLocalRef(localClass);
    
    g_forwardMethod = env->GetStaticMethodID(g_uiThreadClass, "forwardToMainThread", "(J)V");
    if (g_forwardMethod == nullptr) {
        __android_log_print(ANDROID_LOG_ERROR, "AgusGuiThread", "JNI_OnLoad: Failed to find forwardToMainThread method");
        env->ExceptionClear();
    } else {
        __android_log_print(ANDROID_LOG_DEBUG, "AgusGuiThread", "JNI_OnLoad: UiThread class and method initialized");
    }
    
    return JNI_VERSION_1_6;
}

static JNIEnv* getJNIEnv() {
    JNIEnv* env = nullptr;
    if (g_javaVM == nullptr) {
        __android_log_print(ANDROID_LOG_ERROR, "AgusGuiThread", "JavaVM is null!");
        return nullptr;
    }
    
    jint result = g_javaVM->GetEnv(reinterpret_cast<void**>(&env), JNI_VERSION_1_6);
    if (result == JNI_EDETACHED) {
        // Thread not attached, attach it
        if (g_javaVM->AttachCurrentThread(&env, nullptr) != 0) {
            __android_log_print(ANDROID_LOG_ERROR, "AgusGuiThread", "Failed to attach thread to JVM");
            return nullptr;
        }
    } else if (result != JNI_OK) {
        __android_log_print(ANDROID_LOG_ERROR, "AgusGuiThread", "Failed to get JNI env: %d", result);
        return nullptr;
    }
    return env;
}

namespace agus {

AgusGuiThread::AgusGuiThread()
{
    __android_log_print(ANDROID_LOG_DEBUG, "AgusGuiThread", "AgusGuiThread constructor");
    
    // Use globally cached references
    m_class = g_uiThreadClass;
    m_method = g_forwardMethod;
    
    if (m_class == nullptr || m_method == nullptr) {
        __android_log_print(ANDROID_LOG_ERROR, "AgusGuiThread", "UiThread class/method not initialized - JNI_OnLoad may have failed");
    } else {
        __android_log_print(ANDROID_LOG_DEBUG, "AgusGuiThread", "AgusGuiThread using cached JNI references");
    }
}

AgusGuiThread::~AgusGuiThread()
{
    // Don't delete global refs - they're owned by JNI_OnLoad
    m_class = nullptr;
    m_method = nullptr;
}

// static
void AgusGuiThread::ProcessTask(jlong taskPointer)
{
    __android_log_print(ANDROID_LOG_DEBUG, "AgusGuiThread", "ProcessTask: taskPointer=%ld", taskPointer);
    std::unique_ptr<Task> task(reinterpret_cast<Task*>(taskPointer));
    (*task)();
}

base::TaskLoop::PushResult AgusGuiThread::Push(Task && task)
{
    __android_log_print(ANDROID_LOG_DEBUG, "AgusGuiThread", "Push(&&) called");
    
    std::lock_guard<std::mutex> lock(g_jniMutex);
    
    JNIEnv* env = getJNIEnv();
    if (env == nullptr || g_uiThreadClass == nullptr || g_forwardMethod == nullptr) {
        __android_log_print(ANDROID_LOG_ERROR, "AgusGuiThread", "Push failed - JNI not initialized, executing synchronously");
        // Execute synchronously as fallback
        task();
        return {true, kNoId};
    }

    // Allocate task on heap - will be deleted in ProcessTask
    auto* taskPtr = new Task(std::move(task));
    env->CallStaticVoidMethod(g_uiThreadClass, g_forwardMethod, reinterpret_cast<jlong>(taskPtr));
    
    // Check for exceptions
    if (env->ExceptionCheck()) {
        __android_log_print(ANDROID_LOG_ERROR, "AgusGuiThread", "JNI exception during Push");
        env->ExceptionClear();
        delete taskPtr;
        return {false, kNoId};
    }
    
    return {true, kNoId};
}

base::TaskLoop::PushResult AgusGuiThread::Push(Task const & task)
{
    __android_log_print(ANDROID_LOG_DEBUG, "AgusGuiThread", "Push(&) called");
    
    std::lock_guard<std::mutex> lock(g_jniMutex);
    
    JNIEnv* env = getJNIEnv();
    if (env == nullptr || g_uiThreadClass == nullptr || g_forwardMethod == nullptr) {
        __android_log_print(ANDROID_LOG_ERROR, "AgusGuiThread", "Push failed - JNI not initialized, executing synchronously");
        // Execute synchronously as fallback
        task();
        return {true, kNoId};
    }

    // Allocate task on heap - will be deleted in ProcessTask
    auto* taskPtr = new Task(task);
    env->CallStaticVoidMethod(g_uiThreadClass, g_forwardMethod, reinterpret_cast<jlong>(taskPtr));
    
    // Check for exceptions
    if (env->ExceptionCheck()) {
        __android_log_print(ANDROID_LOG_ERROR, "AgusGuiThread", "JNI exception during Push");
        env->ExceptionClear();
        delete taskPtr;
        return {false, kNoId};
    }
    
    return {true, kNoId};
}

}  // namespace agus

// JNI callback from Java to execute the task
extern "C" JNIEXPORT void JNICALL
Java_app_agus_maps_agus_1maps_1flutter_UiThread_nativeProcessTask(JNIEnv* env, jclass clazz, jlong taskPointer) {
    __android_log_print(ANDROID_LOG_DEBUG, "AgusGuiThread", "nativeProcessTask called: %ld", taskPointer);
    agus::AgusGuiThread::ProcessTask(taskPointer);
}
