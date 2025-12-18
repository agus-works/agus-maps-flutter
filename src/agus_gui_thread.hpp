#pragma once

#include "base/task_loop.hpp"
#include <jni.h>

namespace agus {

/**
 * GUI thread implementation that posts tasks to Android's main (UI) thread.
 * This ensures that tasks scheduled via Platform::RunTask(Thread::Gui, ...)
 * are executed on the Android main thread, maintaining thread affinity
 * for components like BookmarkManager.
 */
class AgusGuiThread : public base::TaskLoop
{
public:
    AgusGuiThread();
    ~AgusGuiThread() override;

    // Called from Java to execute a task
    static void ProcessTask(jlong taskPointer);

    // TaskLoop overrides:
    PushResult Push(Task && task) override;
    PushResult Push(Task const & task) override;

private:
    jclass m_class = nullptr;
    jmethodID m_method = nullptr;
};

}  // namespace agus
