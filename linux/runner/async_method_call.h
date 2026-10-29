#ifndef ASYNC_METHOD_CALL_H_
#define ASYNC_METHOD_CALL_H_

#include <flutter_linux/flutter_linux.h>

#include <functional>

/**
 * Executes a method handler on a worker thread and delivers its response on
 * the platform (GTK) thread. The handler must not touch Flutter objects other
 * than creating the response value.
 */
void respond_async(FlMethodCall* method_call,
                   std::function<FlMethodResponse*()> handler);

#endif  // ASYNC_METHOD_CALL_H_
