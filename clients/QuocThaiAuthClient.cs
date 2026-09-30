// ==============================================================================
// QUỐC THÁI AUTH CLIENT FOR C# (.NET WinForms / WPF / Console App)
// Hỗ trợ xác thực cả Mã Key Bản Quyền và Tài Khoản Mật Khẩu (User Accounts)
// Server mặc định: https://quocthaiauth.onrender.com
// ==============================================================================

using System;
using System.IO;
using System.Net.Http;
using System.Security.Cryptography;
using System.Text;
using System.Text.Json;
using System.Threading.Tasks;

namespace QuocThaiAuth
{
    public class QuocThaiAuthClient
    {
        private readonly string _baseUrl;
        private readonly string _appId;
        private static readonly HttpClient httpClient = new HttpClient();

        public QuocThaiAuthClient(string appId, string baseUrl = "https://quocthaiauth.onrender.com")
        {
            _appId = appId;
            _baseUrl = baseUrl.TrimEnd('/');
        }

        public class AuthResult
        {
            public bool Success { get; set; }
            public string Message { get; set; }
            public string Token { get; set; }
            public string Subscription { get; set; }
            public string ExpiresAt { get; set; }
            public string Hwid { get; set; }
            public string NumOnlineUsers { get; set; }
        }

        /// <summary>
        /// 1. Khởi tạo kết nối & lấy số máy Online
        /// </summary>
        public async Task<AuthResult> InitAsync()
        {
            try
            {
                var payload = new { appId = _appId, hwid = GetMachineHwid() };
                string json = JsonSerializer.Serialize(payload);
                var content = new StringContent(json, Encoding.UTF8, "application/json");

                HttpResponseMessage response = await httpClient.PostAsync($"{_baseUrl}/api/v1/client/init", content);
                string responseBody = await response.Content.ReadAsStringAsync();

                using var doc = JsonDocument.Parse(responseBody);
                var root = doc.RootElement;
                bool success = root.TryGetProperty("success", out var s) && s.GetBoolean();

                return new AuthResult
                {
                    Success = success,
                    Message = root.TryGetProperty("message", out var m) ? m.GetString() : (root.TryGetProperty("error", out var e) ? e.GetString() : ""),
                    Token = root.TryGetProperty("token", out var t) ? t.GetString() : "",
                    NumOnlineUsers = root.TryGetProperty("numOnlineUsers", out var o) ? o.GetString() : "1"
                };
            }
            catch (Exception ex)
            {
                return new AuthResult { Success = false, Message = "Lỗi kết nối: " + ex.Message };
            }
        }

        /// <summary>
        /// 2. Xác thực bằng Mã Key Bản Quyền
        /// </summary>
        public async Task<AuthResult> LoginKeyAsync(string licenseKey)
        {
            try
            {
                var payload = new { key = licenseKey.Trim(), hwid = GetMachineHwid(), appId = _appId };
                string json = JsonSerializer.Serialize(payload);
                var content = new StringContent(json, Encoding.UTF8, "application/json");

                HttpResponseMessage response = await httpClient.PostAsync($"{_baseUrl}/api/v1/client/login", content);
                string responseBody = await response.Content.ReadAsStringAsync();

                using var doc = JsonDocument.Parse(responseBody);
                var root = doc.RootElement;
                bool success = root.TryGetProperty("success", out var s) && s.GetBoolean();

                return new AuthResult
                {
                    Success = success,
                    Message = success ? "Xác thực Key thành công!" : (root.TryGetProperty("error", out var e) ? e.GetString() : "Xác thực thất bại"),
                    Token = root.TryGetProperty("token", out var t) ? t.GetString() : "",
                    Subscription = root.TryGetProperty("subscription", out var sub) ? sub.GetString() : "VIP",
                    ExpiresAt = root.TryGetProperty("expiresAt", out var exp) ? exp.GetString() : "",
                    Hwid = root.TryGetProperty("hwid", out var h) ? h.GetString() : "",
                    NumOnlineUsers = root.TryGetProperty("numOnlineUsers", out var o) ? o.GetString() : "1"
                };
            }
            catch (Exception ex)
            {
                return new AuthResult { Success = false, Message = "Lỗi xác thực: " + ex.Message };
            }
        }

        /// <summary>
        /// 3. Xác thực bằng Tài Khoản & Mật Khẩu (User Account)
        /// </summary>
        public async Task<AuthResult> LoginUserAsync(string username, string password)
        {
            try
            {
                var payload = new { username = username.Trim(), password = password.Trim(), hwid = GetMachineHwid(), appId = _appId };
                string json = JsonSerializer.Serialize(payload);
                var content = new StringContent(json, Encoding.UTF8, "application/json");

                HttpResponseMessage response = await httpClient.PostAsync($"{_baseUrl}/api/v1/client/login-user", content);
                string responseBody = await response.Content.ReadAsStringAsync();

                using var doc = JsonDocument.Parse(responseBody);
                var root = doc.RootElement;
                bool success = root.TryGetProperty("success", out var s) && s.GetBoolean();

                return new AuthResult
                {
                    Success = success,
                    Message = success ? "Đăng nhập tài khoản thành công!" : (root.TryGetProperty("error", out var e) ? e.GetString() : "Đăng nhập thất bại"),
                    Token = root.TryGetProperty("token", out var t) ? t.GetString() : "",
                    Subscription = root.TryGetProperty("subscription", out var sub) ? sub.GetString() : "VIP",
                    ExpiresAt = root.TryGetProperty("expiresAt", out var exp) ? exp.GetString() : "",
                    Hwid = root.TryGetProperty("hwid", out var h) ? h.GetString() : "",
                    NumOnlineUsers = root.TryGetProperty("numOnlineUsers", out var o) ? o.GetString() : "1"
                };
            }
            catch (Exception ex)
            {
                return new AuthResult { Success = false, Message = "Lỗi đăng nhập: " + ex.Message };
            }
        }

        /// <summary>
        /// 4. Heartbeat duy trì trạng thái Online & cập nhật số máy
        /// </summary>
        public async Task<AuthResult> CheckSessionAsync()
        {
            try
            {
                var payload = new { appId = _appId, hwid = GetMachineHwid() };
                string json = JsonSerializer.Serialize(payload);
                var content = new StringContent(json, Encoding.UTF8, "application/json");

                HttpResponseMessage response = await httpClient.PostAsync($"{_baseUrl}/api/v1/client/check", content);
                string responseBody = await response.Content.ReadAsStringAsync();

                using var doc = JsonDocument.Parse(responseBody);
                var root = doc.RootElement;
                bool success = root.TryGetProperty("success", out var s) && s.GetBoolean();

                return new AuthResult
                {
                    Success = success,
                    Message = "Phiên hoạt động tốt",
                    NumOnlineUsers = root.TryGetProperty("numOnlineUsers", out var o) ? o.GetString() : "1"
                };
            }
            catch (Exception ex)
            {
                return new AuthResult { Success = false, Message = ex.Message };
            }
        }

        /// <summary>
        /// Sinh mã HWID duy nhất dựa trên tên máy và vi xử lý của Windows
        /// </summary>
        public static string GetMachineHwid()
        {
            try
            {
                string raw = Environment.MachineName + "_" + Environment.UserName + "_" + Environment.ProcessorCount;
                using var sha256 = SHA256.Create();
                byte[] bytes = sha256.ComputeHash(Encoding.UTF8.GetBytes(raw));
                var sb = new StringBuilder("HWID-");
                for (int i = 0; i < 8; i++)
                {
                    sb.Append(bytes[i].ToString("X2"));
                }
                return sb.ToString();
            }
            catch
            {
                return "HWID-WINDOWS-CLIENT";
            }
        }
    }
}
