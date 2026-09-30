// QuocThaiAuth & LongAuth C++ KeyAuth-compatible auth.hpp.
// Drop this file in place of the old KeyAuth auth.hpp, then keep your old calls:
//   KeyAuth::api KeyAuthApp(name, ownerid, version, url, path);
// Mapping:
//   name    = display name, e.g. "YOUR_APP"
//   ownerid = QuocThaiAuth App ID (e.g. "app_pk_viet_...")
//   version = your app version (e.g. "1.0.0")
//   url     = Base URL: "https://quocthaiauth.onrender.com" (hoặc "http://localhost:8080")
//   path    = QuocThaiAuth App Secret Key (e.g. "sk_live_viet_...")
//
// Requires libcurl + OpenSSL.
// Visual Studio: Link libcurl.lib + libssl.lib + libcrypto.lib
// MinGW / GCC:   g++ main.cpp -lcurl -lcrypto -o app
#pragma once

#include <string>
#include <ctime>
#include <cstdio>
#include <random>
#include <sstream>
#include <iomanip>
#include <vector>
#include <cstdlib>
#ifdef _WIN32
#include <windows.h>
#endif
#include <curl/curl.h>
#include <openssl/hmac.h>

struct channel_struct {
    std::string author;
    std::string message;
    std::string timestamp;
};

namespace LongAuthCompatInternal {
static size_t writeCb(void* p, size_t s, size_t n, void* up) {
    ((std::string*)up)->append((char*)p, s * n); return s * n;
}

static std::string hmacHex(const std::string& key, const std::string& msg) {
    unsigned char* d; unsigned int len;
    d = HMAC(EVP_sha256(), key.data(), key.size(),
             (unsigned char*)msg.data(), msg.size(), nullptr, &len);
    std::ostringstream o;
    for (unsigned int i = 0; i < len; i++) o << std::hex << std::setw(2) << std::setfill('0') << (int)d[i];
    return o.str();
}

static std::string nonce() {
    return std::to_string((unsigned long long)time(nullptr)) + std::to_string((unsigned long long)rand());
}

static std::string jsonEscape(const std::string& s) {
    std::string out;
    for (char ch : s) {
        if (ch == '\\') out += "\\\\";
        else if (ch == '"') out += "\\\"";
        else if (ch == '\n') out += "\\n";
        else if (ch == '\r') out += "\\r";
        else if (ch == '\t') out += "\\t";
        else out += ch;
    }
    return out;
}

static bool successTrue(const std::string& body) {
    std::string compact;
    for (char ch : body) if (ch != ' ' && ch != '\n' && ch != '\r' && ch != '\t') compact += ch;
    return compact.find("\"success\":true") != std::string::npos;
}

static std::string extractString(const std::string& body, const std::string& key) {
    const std::string needle = "\"" + key + "\"";
    auto pos = body.find(needle);
    if (pos == std::string::npos) return "";
    pos = body.find(':', pos + needle.size());
    if (pos == std::string::npos) return "";
    pos = body.find('"', pos + 1);
    if (pos == std::string::npos) return "";
    std::string out;
    bool esc = false;
    for (++pos; pos < body.size(); ++pos) {
        char ch = body[pos];
        if (esc) { out += ch; esc = false; }
        else if (ch == '\\') esc = true;
        else if (ch == '"') break;
        else out += ch;
    }
    return out;
}

static std::string isoUtcToUnixSeconds(const std::string& iso) {
    if (iso.empty()) return "";
    int year = 0, month = 0, day = 0, hour = 0, minute = 0, second = 0;
    if (std::sscanf(iso.c_str(), "%d-%d-%dT%d:%d:%d", &year, &month, &day, &hour, &minute, &second) != 6) {
        return "";
    }
    std::tm utc{};
    utc.tm_year = year - 1900;
    utc.tm_mon = month - 1;
    utc.tm_mday = day;
    utc.tm_hour = hour;
    utc.tm_min = minute;
    utc.tm_sec = second;
    utc.tm_isdst = 0;
#ifdef _WIN32
    std::time_t unixSeconds = _mkgmtime(&utc);
#else
    std::time_t unixSeconds = timegm(&utc);
#endif
    if (unixSeconds == (std::time_t)-1) return "";
    return std::to_string((long long)unixSeconds);
}

static long long parseUnixSeconds(const std::string& value) {
    if (value.empty()) return 0;
    char* end = nullptr;
    const long long parsed = std::strtoll(value.c_str(), &end, 10);
    if (!end || *end != '\0' || parsed <= 0) return 0;
    return parsed;
}

static std::string formatRemainingSeconds(long long seconds) {
    if (seconds <= 0) return "EXPIRED";
    const long long days = seconds / 86400;
    const long long hours = (seconds % 86400) / 3600;
    const long long minutes = (seconds % 3600) / 60;
    char out[32] = {};
    if (days > 0) {
        std::snprintf(out, sizeof(out), "%lldD %lldH", days, hours);
    } else if (hours > 0) {
        std::snprintf(out, sizeof(out), "%lldH %lldM", hours, minutes);
    } else {
        std::snprintf(out, sizeof(out), "%lldM", minutes);
    }
    return out;
}

static std::string defaultHwid() {
#ifdef _WIN32
    char computer[256] = {};
    unsigned long size = sizeof(computer);
    GetComputerNameA(computer, &size);
    return std::string(computer);
#else
    return "desktop-client";
#endif
}
}

namespace KeyAuth {

class api {
public:
    std::string name, ownerid, version, url, path;

    class subscriptions_class {
    public:
        std::string name;
        std::string expiry;
    };

    class userdata {
    public:
        std::string username;
        std::string ip;
        std::string hwid;
        std::string createdate;
        std::string lastlogin;
        std::vector<subscriptions_class> subscriptions;
    };

    class appdata {
    public:
        std::string numUsers;
        std::string numOnlineUsers;
        std::string numKeys;
        std::string version;
        std::string customerPanelLink;
    };

    class responsedata {
    public:
        std::vector<channel_struct> channeldata;
        bool success{};
        std::string message;
        bool isPaid{};
    };

    userdata user_data;
    appdata app_data;
    responsedata response;

    api(std::string name, std::string ownerid, std::string version, std::string url, std::string path)
        : name(name), ownerid(ownerid), version(version), url(url), path(path) {
        curl_global_init(CURL_GLOBAL_DEFAULT);
    }

    ~api() {
        curl_global_cleanup();
    }

    long long expiryUnixSeconds() const {
        if (user_data.subscriptions.empty()) return 0;
        return LongAuthCompatInternal::parseUnixSeconds(user_data.subscriptions[0].expiry);
    }

    long long expiryRemainingSeconds() const {
        const long long expiry = expiryUnixSeconds();
        if (expiry <= 0) return -1;
        const long long remaining = expiry - (long long)std::time(nullptr);
        return remaining > 0 ? remaining : 0;
    }

    bool isExpired() const {
        return expiryUnixSeconds() > 0 && expiryRemainingSeconds() == 0;
    }

    std::string expiryLabel() const {
        const long long remaining = expiryRemainingSeconds();
        if (remaining < 0) return "N/A";
        return LongAuthCompatInternal::formatRemainingSeconds(remaining);
    }

    void init() {
        std::string body = send("/init", "{}", true);
        apply(body, "Initialized");
        if (response.success) {
            app_data.version = LongAuthCompatInternal::extractString(body, "version");
            app_data.numOnlineUsers = LongAuthCompatInternal::extractString(body, "numOnlineUsers");
            app_data.numUsers = LongAuthCompatInternal::extractString(body, "numUsers");
            app_data.numKeys = LongAuthCompatInternal::extractString(body, "numKeys");
        }
    }

    void license(std::string key) {
        std::string hwid = LongAuthCompatInternal::defaultHwid();
        std::string raw = "{\"key\":\"" + LongAuthCompatInternal::jsonEscape(key) + "\",\"hwid\":\"" + LongAuthCompatInternal::jsonEscape(hwid) + "\"}";
        std::string body = send("/login", raw, true);
        apply(body, "License login successful");
        if (response.success) fillUser("license", hwid, body);
    }

    void login(std::string username, std::string password) {
        std::string hwid = LongAuthCompatInternal::defaultHwid();
        std::string raw = "{\"username\":\"" + LongAuthCompatInternal::jsonEscape(username) + "\",\"password\":\"" + LongAuthCompatInternal::jsonEscape(password) + "\",\"hwid\":\"" + LongAuthCompatInternal::jsonEscape(hwid) + "\"}";
        std::string body = send("/login-user", raw, true);
        apply(body, "Login successful");
        if (response.success) fillUser(username, hwid, body);
    }

    void regstr(std::string username, std::string password, std::string key, std::string email = "") {
        (void)email;
        std::string hwid = LongAuthCompatInternal::defaultHwid();
        std::string raw = "{\"key\":\"" + LongAuthCompatInternal::jsonEscape(key) + "\",\"username\":\"" + LongAuthCompatInternal::jsonEscape(username) + "\",\"password\":\"" + LongAuthCompatInternal::jsonEscape(password) + "\",\"hwid\":\"" + LongAuthCompatInternal::jsonEscape(hwid) + "\"}";
        std::string body = send("/register", raw, true);
        apply(body, "Registered");
        if (response.success) login(username, password);
    }

    void check(bool check_paid = false) {
        (void)check_paid;
        std::string body = send("/check", "{}", true);
        apply(body, "Session valid");
    }

    std::string var(std::string varid) { return getvar(varid); }
    std::string getvar(std::string var) {
        std::string body = send("/variables", "", false);
        apply(body, "Variables loaded");
        const std::string quoted = "\"" + var + "\"";
        auto pos = body.find(quoted);
        if (pos == std::string::npos) return "";
        auto valuePos = body.find("\"value\"", pos);
        if (valuePos == std::string::npos) return "";
        return LongAuthCompatInternal::extractString(body.substr(valuePos), "value");
    }

    void logout() { token.clear(); user_data = userdata{}; response.success = true; response.message = "Logged out"; }

    // Giữ tương thích tối đa với các dự án KeyAuth cũ
    void ban(std::string reason = "") { (void)reason; unsupported("ban"); }
    void log(std::string msg) { (void)msg; response.success = true; response.message = "Log ignored"; }
    std::string webhook(std::string id, std::string params, std::string body = "", std::string contenttype = "") { (void)id; (void)params; (void)body; (void)contenttype; unsupported("webhook"); return ""; }
    void setvar(std::string var, std::string vardata) { (void)var; (void)vardata; unsupported("setvar"); }
    bool checkblack() { response.success = true; response.message = "Not blacklisted"; return false; }
    void web_login() { unsupported("web_login"); }
    void button(std::string value) { (void)value; unsupported("button"); }
    void upgrade(std::string username, std::string key) { (void)username; (void)key; unsupported("upgrade"); }
    std::vector<unsigned char> download(std::string fileid) { (void)fileid; unsupported("download"); return {}; }
    void chatget(std::string channel) { (void)channel; unsupported("chatget"); }
    bool chatsend(std::string message, std::string channel) { (void)message; (void)channel; unsupported("chatsend"); return false; }
    void changeUsername(std::string newusername) { (void)newusername; unsupported("changeUsername"); }
    std::string fetchonline() { return app_data.numOnlineUsers; }
    void fetchstats() {}
    void forgot(std::string username, std::string email) { (void)username; (void)email; unsupported("forgot"); }

private:
    std::string token;

    std::string send(const std::string& apiPath, const std::string& raw, bool post) {
        std::string ts = std::to_string(time(nullptr));
        std::string n = LongAuthCompatInternal::nonce();
        std::string sig = LongAuthCompatInternal::hmacHex(path, ts + "." + n + "." + raw);
        std::string resp;
        CURL* c = curl_easy_init();
        struct curl_slist* h = nullptr;
        h = curl_slist_append(h, "Content-Type: application/json");
        h = curl_slist_append(h, ("x-app-id: " + ownerid).c_str());
        h = curl_slist_append(h, ("x-timestamp: " + ts).c_str());
        h = curl_slist_append(h, ("x-nonce: " + n).c_str());
        h = curl_slist_append(h, ("x-signature: " + sig).c_str());
        if (!token.empty()) h = curl_slist_append(h, ("Authorization: Bearer " + token).c_str());
        std::string base = url;
        while (!base.empty() && base.back() == '/') base.pop_back();
        curl_easy_setopt(c, CURLOPT_URL, (base + "/api/v1/client" + apiPath).c_str());
        curl_easy_setopt(c, CURLOPT_HTTPHEADER, h);
        if (post) curl_easy_setopt(c, CURLOPT_POSTFIELDS, raw.c_str());
        curl_easy_setopt(c, CURLOPT_WRITEFUNCTION, LongAuthCompatInternal::writeCb);
        curl_easy_setopt(c, CURLOPT_WRITEDATA, &resp);
        curl_easy_setopt(c, CURLOPT_TIMEOUT, 10L);
        curl_easy_setopt(c, CURLOPT_SSL_VERIFYPEER, 0L); // Cho phép chạy cả HTTPS và HTTP local
        curl_easy_perform(c);
        curl_slist_free_all(h); curl_easy_cleanup(c);
        std::string t = LongAuthCompatInternal::extractString(resp, "token");
        if (!t.empty()) token = t;
        return resp;
    }

    void apply(const std::string& body, const std::string& okMessage) {
        response.success = LongAuthCompatInternal::successTrue(body);
        response.isPaid = response.success;
        response.message = response.success ? okMessage : LongAuthCompatInternal::extractString(body, "error");
        if (response.message.empty()) response.message = LongAuthCompatInternal::extractString(body, "message");
        if (response.message.empty()) response.message = response.success ? okMessage : "Request failed";
    }

    void fillUser(const std::string& username, const std::string& hwid, const std::string& body) {
        user_data.username = username;
        user_data.hwid = hwid;
        user_data.lastlogin = std::to_string(time(nullptr));
        if (user_data.createdate.empty()) user_data.createdate = user_data.lastlogin;
        const std::string expiresAt = LongAuthCompatInternal::extractString(body, "expiresAt");
        const std::string expiry = LongAuthCompatInternal::isoUtcToUnixSeconds(expiresAt);
        if (user_data.subscriptions.empty()) {
            subscriptions_class sub;
            sub.name = "default";
            user_data.subscriptions.push_back(sub);
        }
        user_data.subscriptions[0].name = "default";
        user_data.subscriptions[0].expiry = expiry;
    }

    void unsupported(const std::string& fn) {
        response.success = false;
        response.isPaid = false;
        response.message = "VietAuth compatibility layer does not support KeyAuth::" + fn;
    }
};

} // namespace KeyAuth
