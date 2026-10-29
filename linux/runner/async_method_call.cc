#include "async_method_call.h"

#include <glib.h>

#include <utility>

namespace {

struct AsyncJob {
  FlMethodCall* method_call;
  std::function<FlMethodResponse*()> handler;
};

struct AsyncResponse {
  FlMethodCall* method_call;
  FlMethodResponse* response;
};

gboolean deliver_response(gpointer data) {
  auto* response = static_cast<AsyncResponse*>(data);
  fl_method_call_respond(response->method_call, response->response, nullptr);
  g_object_unref(response->response);
  g_object_unref(response->method_call);
  delete response;
  return G_SOURCE_REMOVE;
}

gpointer run_job(gpointer data) {
  auto* job = static_cast<AsyncJob*>(data);
  FlMethodResponse* response = nullptr;
  try {
    response = job->handler();
  } catch (...) {
    response = FL_METHOD_RESPONSE(fl_method_error_response_new(
        "error_interno", "Error interno al ejecutar la operación.", nullptr));
  }
  if (response == nullptr) {
    response = FL_METHOD_RESPONSE(fl_method_error_response_new(
        "error_interno", "La operación no devolvió una respuesta.", nullptr));
  }

  auto* async_response =
      new AsyncResponse{job->method_call, response};
  g_main_context_invoke(nullptr, deliver_response, async_response);
  delete job;
  return nullptr;
}

}  // namespace

void respond_async(FlMethodCall* method_call,
                   std::function<FlMethodResponse*()> handler) {
  g_object_ref(method_call);
  auto* job = new AsyncJob{method_call, std::move(handler)};
  GThread* thread = g_thread_new("medlink-method-call", run_job, job);
  g_thread_unref(thread);
}
