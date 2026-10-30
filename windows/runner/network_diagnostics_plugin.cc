#include <winsock2.h>
#include <ws2tcpip.h>
#include <iphlpapi.h>
#include <icmpapi.h>
#include <windows.h>
#include "network_diagnostics_plugin.h"
#include <flutter/method_channel.h>
#include <flutter/standard_method_codec.h>
#include <stdlib.h>
#include <stdio.h>
#include <any>
#include <cctype>
#include <string>
#include <sstream>
#include <vector>
#include <regex>
#include <thread>
#include <memory>

#include "utils.h"

#pragma comment(lib, "Ws2_32.lib")
#pragma comment(lib, "iphlpapi.lib")

namespace {

using flutter::EncodableMap;
using flutter::EncodableValue;
using MethodResultPtr = std::unique_ptr<flutter::MethodResult<EncodableValue>>;
using MethodChannelPtr =
    std::unique_ptr<flutter::MethodChannel<EncodableValue>>;

// ------------------------------------------------------------------
//  flushDns
// ------------------------------------------------------------------
typedef BOOL(WINAPI* DnsFlushResolverCacheFunc)();

static void HandleFlushDns(MethodResultPtr result) {
  HMODULE dnsapi = LoadLibraryW(L"dnsapi.dll");
  bool success = false;
  
  if (dnsapi) {
    auto pDnsFlushResolverCache = (DnsFlushResolverCacheFunc)GetProcAddress(dnsapi, "DnsFlushResolverCache");
    if (pDnsFlushResolverCache) {
      success = pDnsFlushResolverCache();
    }
    FreeLibrary(dnsapi);
  }

  // Fallback if undocumented API fails or is unavailable
  if (!success) {
    auto cmdRes = RunCmdSync(L"ipconfig /flushdns");
    if (cmdRes.exit_code == 0) {
      success = true;
    }
  }
  
  if (success) {
    result->Success(EncodableValue("Caché DNS limpiada exitosamente."));
  } else {
    result->Error("flushdns_error", "Error al limpiar caché DNS. Intenta ejecutar la app como Administrador.");
  }
}

// ------------------------------------------------------------------
//  clearNetworkCaches
// ------------------------------------------------------------------
static void HandleClearCaches(MethodResultPtr result) {
  if (!IsElevated()) {
    result->Error("permiso_denegado", "Se requieren privilegios de Administrador para limpiar tablas ARP.");
    return;
  }

  ULONG outBufLen = 0;
  GetIfTable(nullptr, &outBufLen, FALSE);
  PMIB_IFTABLE pIfTable = (PMIB_IFTABLE)malloc(outBufLen);
  int success_count = 0;
  int fail_count = 0;

  if (pIfTable != nullptr && GetIfTable(pIfTable, &outBufLen, FALSE) == NO_ERROR) {
    for (DWORD i = 0; i < pIfTable->dwNumEntries; i++) {
      if (FlushIpNetTable(pIfTable->table[i].dwIndex) == NO_ERROR) {
        success_count++;
      } else {
        fail_count++;
      }
    }
    free(pIfTable);
  } else {
    if (pIfTable) free(pIfTable);
    result->Error("arp_error", "No se pudieron enumerar las interfaces.");
    return;
  }

  std::stringstream output;
  output << "ARP cache: " << success_count << " limpiados, " << fail_count << " con error.";
  result->Success(EncodableValue(output.str()));
}

// ------------------------------------------------------------------
//  ping
// ------------------------------------------------------------------
static void HandlePing(const std::string& host, MethodResultPtr result) {
  if (host.empty()) {
    result->Error("argumento_invalido", "Host no especificado");
    return;
  }

  // Async thread to prevent UI freezing
  std::thread([host, res = std::move(result)]() mutable {
    WSADATA wsa_data;
    if (WSAStartup(MAKEWORD(2, 2), &wsa_data) != 0) {
      res->Error("socket_error", "No se pudo inicializar Winsock");
      return;
    }

    addrinfo hints{};
    hints.ai_family = AF_INET;
    hints.ai_socktype = SOCK_STREAM;
    hints.ai_protocol = IPPROTO_TCP;

    addrinfo* addresses = nullptr;
    if (getaddrinfo(host.c_str(), nullptr, &hints, &addresses) != 0 || addresses == nullptr) {
      WSACleanup();
      res->Error("inaccesible", "No se pudo resolver el host (solo IPv4 soportado para ping)");
      return;
    }

    struct sockaddr_in* sockaddr_ipv4 = (struct sockaddr_in*)addresses->ai_addr;
    IPAddr ip = sockaddr_ipv4->sin_addr.S_un.S_addr;
    freeaddrinfo(addresses);
    WSACleanup();

    HANDLE hIcmpFile = IcmpCreateFile();
    if (hIcmpFile == INVALID_HANDLE_VALUE) {
      res->Error("ping_error", "No se pudo crear el handle ICMP");
      return;
    }

    char SendData[32] = "Data Buffer";
    DWORD ReplySize = sizeof(ICMP_ECHO_REPLY) + sizeof(SendData) + 8;
    LPVOID ReplyBuffer = malloc(ReplySize);
    
    if (ReplyBuffer == nullptr) {
      IcmpCloseHandle(hIcmpFile);
      res->Error("ping_error", "Memoria insuficiente");
      return;
    }

    DWORD dwRetVal = IcmpSendEcho(hIcmpFile, ip, SendData, sizeof(SendData),
                                  nullptr, ReplyBuffer, ReplySize, 1200);

    if (dwRetVal != 0) {
      PICMP_ECHO_REPLY pEchoReply = (PICMP_ECHO_REPLY)ReplyBuffer;
      int avg = pEchoReply->RoundTripTime;
      free(ReplyBuffer);
      IcmpCloseHandle(hIcmpFile);
      res->Success(EncodableValue(avg));
    } else {
      free(ReplyBuffer);
      IcmpCloseHandle(hIcmpFile);
      res->Error("inaccesible", "Host inaccesible");
    }
  }).detach();
}

// ------------------------------------------------------------------
//  checkTcpPort
// ------------------------------------------------------------------
static void HandleCheckTcpPort(
    const std::string& host,
    int port,
    MethodResultPtr result) {
  if (host.empty()) {
    result->Error("argumento_invalido", "Host no especificado");
    return;
  }
  if (port <= 0 || port > 65535) {
    result->Error("argumento_invalido", "Puerto inválido");
    return;
  }

  // Async thread to prevent UI freezing
  std::thread([host, port, res = std::move(result)]() mutable {
    WSADATA wsa_data{};
    if (WSAStartup(MAKEWORD(2, 2), &wsa_data) != 0) {
      res->Error("socket_error", "No se pudo inicializar Winsock");
      return;
    }

    addrinfo hints{};
    hints.ai_family = AF_UNSPEC;
    hints.ai_socktype = SOCK_STREAM;
    hints.ai_protocol = IPPROTO_TCP;

    addrinfo* addresses = nullptr;
    const auto service = std::to_string(port);
    const int addr_res =
        getaddrinfo(host.c_str(), service.c_str(), &hints, &addresses);
    if (addr_res != 0 || addresses == nullptr) {
      WSACleanup();
      res->Error("inaccesible", "No se pudo resolver el host o abrir el puerto");
      return;
    }

    int best_time_ms = -1;
    for (addrinfo* current = addresses; current != nullptr;
         current = current->ai_next) {
      SOCKET sock =
          socket(current->ai_family, current->ai_socktype, current->ai_protocol);
      if (sock == INVALID_SOCKET) {
        continue;
      }

      u_long non_blocking = 1;
      ioctlsocket(sock, FIONBIO, &non_blocking);

      const ULONGLONG start_tick = GetTickCount64();
      int connect_res =
          connect(sock, current->ai_addr, static_cast<int>(current->ai_addrlen));
      if (connect_res == SOCKET_ERROR) {
        const int connect_err = WSAGetLastError();
        if (connect_err == WSAEWOULDBLOCK || connect_err == WSAEINPROGRESS ||
            connect_err == WSAEINVAL) {
          fd_set write_set;
          FD_ZERO(&write_set);
          FD_SET(sock, &write_set);

          timeval timeout{};
          timeout.tv_sec = 1;
          timeout.tv_usec = 500000;

          const int select_res =
              select(0, nullptr, &write_set, nullptr, &timeout);
          if (select_res > 0 && FD_ISSET(sock, &write_set)) {
            int socket_error = 0;
            int socket_error_size = sizeof(socket_error);
            if (getsockopt(sock, SOL_SOCKET, SO_ERROR,
                           reinterpret_cast<char*>(&socket_error),
                           &socket_error_size) == 0 &&
                socket_error == 0) {
              const int elapsed_ms =
                  static_cast<int>(GetTickCount64() - start_tick);
              if (best_time_ms == -1 || elapsed_ms < best_time_ms) {
                best_time_ms = elapsed_ms;
              }
            }
          }
        }
      } else {
        const int elapsed_ms = static_cast<int>(GetTickCount64() - start_tick);
        if (best_time_ms == -1 || elapsed_ms < best_time_ms) {
          best_time_ms = elapsed_ms;
        }
      }

      closesocket(sock);
      if (best_time_ms >= 0) {
        break;
      }
    }

    freeaddrinfo(addresses);
    WSACleanup();

    if (best_time_ms < 0) {
      res->Error("inaccesible", "No se pudo establecer conexión TCP con el puerto");
    } else {
      res->Success(EncodableValue(best_time_ms));
    }
  }).detach();
}

// ------------------------------------------------------------------
//  Method call dispatcher
// ------------------------------------------------------------------
static void HandleMethodCall(
    const flutter::MethodCall<EncodableValue>& method_call,
    std::unique_ptr<flutter::MethodResult<EncodableValue>> result) {
  const auto& method = method_call.method_name();

  if (method == "flushDns") {
    HandleFlushDns(std::move(result));
    return;
  }

  if (method == "clearNetworkCaches") {
    HandleClearCaches(std::move(result));
    return;
  }

  if (method == "ping") {
    std::string host;
    auto args = method_call.arguments();
    if (auto* map = std::get_if<EncodableMap>(args)) {
      auto it = map->find(EncodableValue("host"));
      if (it != map->end()) {
        if (auto* s = std::get_if<std::string>(&it->second)) host = *s;
      }
    }
    HandlePing(host, std::move(result));
    return;
  }

  if (method == "checkTcpPort") {
    std::string host;
    int port = 0;
    auto args = method_call.arguments();
    if (auto* map = std::get_if<EncodableMap>(args)) {
      auto host_it = map->find(EncodableValue("host"));
      if (host_it != map->end()) {
        if (auto* s = std::get_if<std::string>(&host_it->second)) host = *s;
      }
      auto port_it = map->find(EncodableValue("port"));
      if (port_it != map->end()) {
        if (auto* i = std::get_if<int>(&port_it->second)) port = *i;
      }
    }
    HandleCheckTcpPort(host, port, std::move(result));
    return;
  }

  result->NotImplemented();
}

}  // namespace

void NetworkDiagnosticsPluginRegisterWithRegistrar(
    flutter::FlutterEngine* engine) {
  auto channel = std::make_unique<flutter::MethodChannel<EncodableValue>>(
      engine->messenger(), "com.medlinkconnect/network_diagnostics",
      &flutter::StandardMethodCodec::GetInstance());
  channel->SetMethodCallHandler(HandleMethodCall);
  static std::vector<MethodChannelPtr> s_channels;
  s_channels.push_back(std::move(channel));
}
