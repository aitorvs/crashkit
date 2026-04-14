// process_name.cpp
#include "process.h"
#include <atomic>
#include <fstream>
#include <mutex>
#include <string>
#include <vector>

namespace {

    std::string read_cmdline() {
        std::ifstream f("/proc/self/cmdline", std::ios::in | std::ios::binary);
        if (!f.is_open()) return {};
        std::vector<char> buf(256);
        f.read(buf.data(), static_cast<std::streamsize>(buf.size()));
        std::streamsize n = f.gcount();
        if (n <= 0) return {};

        // /proc/self/cmdline is '\0'-terminated (and may contain extra garbage after the first '\0')
        size_t len = 0;
        while (len < static_cast<size_t>(n) && buf[len] != '\0') ++len;
        return std::string(buf.data(), len);
    }

    inline std::string process_role_from_name(std::string_view full_process_name) {
        // If there's no ':', it's the main process.
        const size_t colon = full_process_name.find(':');
        if (colon == std::string_view::npos) return "main";

        // Take the substring after ':' and trim whitespace.
        std::string_view suffix = full_process_name.substr(colon + 1);
        auto l = suffix.find_first_not_of(" \t\r\n");
        auto r = suffix.find_last_not_of(" \t\r\n");
        if (l == std::string_view::npos) return "main"; // was only whitespace

        suffix = suffix.substr(l, r - l + 1);
        if (suffix.empty()) return "main";

        // sanitize to a friendly charset for pixels/logs
        std::string clean;
        clean.reserve(suffix.size());
        for (char c : suffix) {
            if ((c >= 'a' && c <= 'z') ||
                (c >= 'A' && c <= 'Z') ||
                (c >= '0' && c <= '9') ||
                c == '_' || c == '-' || c == '.')
                clean.push_back(c);
            else
                clean.push_back('_');
        }
        return clean.empty() ? "main" : clean;
    }


    std::once_flag g_once;
    std::string g_cached;

} // namespace

std::string get_process_name() {
    std::call_once(g_once, [&]() {
        std::string name = read_cmdline();
        g_cached = name;
    });
    return process_role_from_name(g_cached);
}
