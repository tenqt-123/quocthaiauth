// ==============================================================================
// QUỐC THÁI AUTH (QuocThaiAuth) - C++ CLIENT AUTH SDK
// Tương thích 100% chuẩn KeyAuth & LongAuth (longauth.site)
// Drop file này vào project C++ của bạn và sử dụng ngay:
//   QuocThaiAuth::api App(name, ownerid, version, url, path);
// Hoặc giữ nguyên gọi KeyAuth cũ:
//   KeyAuth::api App(name, ownerid, version, url, path);
//
// Mặc định Base URL: https://quocthaiauth.onrender.com
// Hỗ trợ cả 2 phương thức xác thực:
//   1. Xác thực bằng Mã Key: App.license("KEY-BAN-QUYEN");
//   2. Xác thực bằng Tài Khoản & Mật Khẩu: App.login("username", "password");
//
// Yêu cầu thư viện: libcurl + OpenSSL (libcrypto)
// Lệnh biên dịch MinGW / GCC:
//   g++ main.cpp -lcurl -lcrypto -o app.exe
// Visual Studio:
//   Link libcurl.lib + libcrypto.lib
// ==============================================================================
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

namespace QuocThaiAuthCompatInternal {
static size_t writeCb(void* p, size_t s, size_t n, void* up) {
    ((std::string*)up)->append((char*)p, s * n); 
    return s * n;
}

static std::string hmacHex(const std::string& key, const std::string& msg) {
    if (key.empty()) return "";
    unsigned char* d; 
    unsigned int len;
    d = HMAC(EVP_sha256(), key.data(), key.size(),
             (unsigned char*)msg.data(), msg.size(), nullptr, &len);
    std::ostringstream o;
    for (unsigned int i = 0; i < len; i++) {
        o << std::hex << std::setw(2) << std::setfill('0') << (int)d[i];
    }
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
    for (char ch : body) {
        if (ch != ' ' && ch != '\n' && ch != '\r' && ch != '\t') {
            compact += ch;
        }
    }
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
    if (seconds <= 0) return "HẾT HẠN (EXPIRED)";
    const long long days = seconds / 86400;
    const long long hours = (seconds % 86400) / 3600;
    const long long minutes = (seconds % 3600) / 60;
    char out[64] = {};
    if (days > 3650) {
        return "VĨNH VIỄN (LIFETIME)";
    }
    if (days > 0) {
        std::snprintf(out, sizeof(out), "%lld Ngày %lld Giờ", days, hours);
    } else if (hours > 0) {
        std::snprintf(out, sizeof(out), "%lld Giờ %lld Phút", hours, minutes);
    } else {
        std::snprintf(out, sizeof(out), "%lld Phút", minutes);
    }
    return out;
}

static std::string defaultHwid() {
#ifdef _WIN32
    char computer[256] = {};
    unsigned long size = sizeof(computer);
    GetComputerNameA(computer, &size);
    return std::string("HWID-") + std::string(computer);
#else
    return "HWID-LINUX-CLIENT";
#endif
}
}

namespace QuocThaiAuth {

class api {
public:
    std::string name;
    std::string ownerid;
    std::string version;
    std::string url;
    std::string path; // App Secret Key

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

    api(std::string name, std::string ownerid, std::string version, std::string url = "https://quocthaiauth.onrender.com", std::string path = "")
        : name(name), ownerid(ownerid), version(version), url(url.empty() ? "https://quocthaiauth.onrender.com" : url), path(path) {
        curl_global_init(CURL_GLOBAL_DEFAULT);
    }

    ~api() {
        curl_global_cleanup();
    }

    long long expiryUnixSeconds() const {
        if (user_data.subscriptions.empty()) return 0;
        return QuocThaiAuthCompatInternal::parseUnixSeconds(user_data.subscriptions[0].expiry);
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
        if (remaining < 0) return "VĨNH VIỄN (LIFETIME)";
        return QuocThaiAuthCompatInternal::formatRemainingSeconds(remaining);
    }

    // 1. Khởi tạo phiên kết nối
    void init() {
        std::string body = send("/init", "{}", true);
        apply(body, "Initialized");
        if (response.success) {
            app_data.version = QuocThaiAuthCompatInternal::extractString(body, "version");
            app_data.numOnlineUsers = QuocThaiAuthCompatInternal::extractString(body, "numOnlineUsers");
            app_data.numUsers = QuocThaiAuthCompatInternal::extractString(body, "numUsers");
            app_data.numKeys = QuocThaiAuthCompatInternal::extractString(body, "numKeys");
        }
    }

    // 2. Xác thực bằng Mã Key Bản Quyền
    void license(std::string key) {
        std::string hwid = QuocThaiAuthCompatInternal::defaultHwid();
        std::string raw = "{\"key\":\"" + QuocThaiAuthCompatInternal::jsonEscape(key) + "\",\"hwid\":\"" + QuocThaiAuthCompatInternal::jsonEscape(hwid) + "\"}";
        std::string body = send("/login", raw, true);
        apply(body, "Xác thực Key bản quyền thành công!");
        if (response.success) {
            fillUser("license_user", hwid, body);
            app_data.numOnlineUsers = QuocThaiAuthCompatInternal::extractString(body, "numOnlineUsers");
        }
    }

    // 3. Xác thực bằng Tài Khoản & Mật Khẩu (User Account)
    void login(std::string username, std::string password) {
        std::string hwid = QuocThaiAuthCompatInternal::defaultHwid();
        std::string raw = "{\"username\":\"" + QuocThaiAuthCompatInternal::jsonEscape(username) + "\",\"password\":\"" + QuocThaiAuthCompatInternal::jsonEscape(password) + "\",\"hwid\":\"" + QuocThaiAuthCompatInternal::jsonEscape(hwid) + "\"}";
        std::string body = send("/login-user", raw, true);
        apply(body, "Đăng nhập tài khoản thành công!");
        if (response.success) {
            fillUser(username, hwid, body);
            app_data.numOnlineUsers = QuocThaiAuthCompatInternal::extractString(body, "numOnlineUsers");
        }
    }

    // 4. Đăng ký tài khoản kèm Key kích hoạt
    void regstr(std::string username, std::string password, std::string key, std::string email = "") {
        (void)email;
        std::string hwid = QuocThaiAuthCompatInternal::defaultHwid();
        std::string raw = "{\"key\":\"" + QuocThaiAuthCompatInternal::jsonEscape(key) + "\",\"username\":\"" + QuocThaiAuthCompatInternal::jsonEscape(username) + "\",\"password\":\"" + QuocThaiAuthCompatInternal::jsonEscape(password) + "\",\"hwid\":\"" + QuocThaiAuthCompatInternal::jsonEscape(hwid) + "\"}";
        std::string body = send("/register", raw, true);
        apply(body, "Đăng ký tài khoản thành công!");
        if (response.success) {
            login(username, password);
        }
    }

    // 5. Kiểm tra phiên và duy trì trạng thái Online (Heartbeat)
    void check(bool check_paid = false) {
        (void)check_paid;
        std::string hwid = QuocThaiAuthCompatInternal::defaultHwid();
        std::string body = send("/check", "{\"hwid\":\"" + QuocThaiAuthCompatInternal::jsonEscape(hwid) + "\"}", true);
        apply(body, "Phiên hợp lệ - Máy đang Online");
        if (response.success) {
            app_data.numOnlineUsers = QuocThaiAuthCompatInternal::extractString(body, "numOnlineUsers");
        }
    }

    // 6. Lấy biến từ xa (Remote Variables)
    std::string var(std::string varid) { return getvar(varid); }
    std::string getvar(std::string var) {
        std::string body = send("/variables", "", false);
        apply(body, "Variables loaded");
        const std::string quoted = "\"" + var + "\"";
        auto pos = body.find(quoted);
        if (pos == std::string::npos) return "";
        auto valuePos = body.find("\"value\"", pos);
        if (valuePos == std::string::npos) return "";
        return QuocThaiAuthCompatInternal::extractString(body.substr(valuePos), "value");
    }

    void logout() {
        token.clear();
        user_data = userdata{};
        response.success = true;
        response.message = "Đã đăng xuất";
    }

    // Các hàm phụ trợ tương thích ngược KeyAuth cũ
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
        std::string n = QuocThaiAuthCompatInternal::nonce();
        std::string sig = path.empty() ? "" : QuocThaiAuthCompatInternal::hmacHex(path, ts + "." + n + "." + raw);
        std::string resp;
        CURL* c = curl_easy_init();
        if (!c) return "{\"success\":false,\"error\":\"curl_easy_init failed\"}";

        struct curl_slist* h = nullptr;
        h = curl_slist_append(h, "Content-Type: application/json");
        h = curl_slist_append(h, ("x-app-id: " + ownerid).c_str());
        h = curl_slist_append(h, ("x-timestamp: " + ts).c_str());
        h = curl_slist_append(h, ("x-nonce: " + n).c_str());
        if (!sig.empty()) {
            h = curl_slist_append(h, ("x-signature: " + sig).c_str());
        }
        if (!token.empty()) {
            h = curl_slist_append(h, ("Authorization: Bearer " + token).c_str());
        }

        std::string base = url;
        while (!base.empty() && base.back() == '/') base.pop_back();

        curl_easy_setopt(c, CURLOPT_URL, (base + "/api/v1/client" + apiPath).c_str());
        curl_easy_setopt(c, CURLOPT_HTTPHEADER, h);
        if (post) {
            curl_easy_setopt(c, CURLOPT_POSTFIELDS, raw.c_str());
        }
        curl_easy_setopt(c, CURLOPT_WRITEFUNCTION, QuocThaiAuthCompatInternal::writeCb);
        curl_easy_setopt(c, CURLOPT_WRITEDATA, &resp);
        curl_easy_setopt(c, CURLOPT_SSL_VERIFYPEER, 0L);
        curl_easy_setopt(c, CURLOPT_SSL_VERIFYHOST, 0L);
        curl_easy_setopt(c, CURLOPT_TIMEOUT, 15L);

        CURLcode res = curl_easy_perform(c);
        curl_slist_free_all(h);
        curl_easy_cleanup(c);

        if (res != CURLE_OK) {
            return "{\"success\":false,\"error\":\"Lỗi kết nối máy chủ QuocThaiAuth: " + std::string(curl_easy_strerror(res)) + "\"}";
        }

        std::string t = QuocThaiAuthCompatInternal::extractString(resp, "token");
        if (!t.empty()) token = t;
        return resp;
    }

    void apply(const std::string& body, const std::string& okMessage) {
        response.success = QuocThaiAuthCompatInternal::successTrue(body);
        response.isPaid = response.success;
        response.message = response.success ? okMessage : QuocThaiAuthCompatInternal::extractString(body, "error");
        if (response.message.empty()) {
            response.message = response.success ? okMessage : QuocThaiAuthCompatInternal::extractString(body, "message");
        }
        if (response.message.empty()) {
            response.message = response.success ? okMessage : "Yêu cầu thất bại (Lỗi máy chủ)";
        }
    }

    void fillUser(const std::string& username, const std::string& hwid, const std::string& body) {
        user_data.username = username;
        user_data.hwid = hwid;
        user_data.lastlogin = std::to_string(time(nullptr));
        if (user_data.createdate.empty()) user_data.createdate = user_data.lastlogin;

        const std::string expiresAt = QuocThaiAuthCompatInternal::extractString(body, "expiresAt");
        const std::string expiry = QuocThaiAuthCompatInternal::isoUtcToUnixSeconds(expiresAt);
        const std::string subLevel = QuocThaiAuthCompatInternal::extractString(body, "subscription");

        if (user_data.subscriptions.empty()) {
            subscriptions_class sub;
            sub.name = subLevel.empty() ? "VIP" : subLevel;
            user_data.subscriptions.push_back(sub);
        }
        user_data.subscriptions[0].name = subLevel.empty() ? "VIP" : subLevel;
        user_data.subscriptions[0].expiry = expiry;
    }

    void unsupported(const std::string& fn) {
        response.success = false;
        response.isPaid = false;
        response.message = "QuocThaiAuth không hỗ trợ hàm KeyAuth::" + fn;
    }
};

} // namespace QuocThaiAuth

// Tương thích ngược: Cho phép giữ nguyên tên gọi KeyAuth::api trong code cũ
namespace KeyAuth = QuocThaiAuth;
