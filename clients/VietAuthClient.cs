// ==============================================================================
// VIET AUTH CLIENT FOR C# (.NET WinForms / WPF / Console App)
// Dành cho lập trình viên Việt Nam tích hợp xác thực bản quyền & HWID vào phần mềm
// ==============================================================================

using System;
using System.IO;
using System.Net.Http;
using System.Security.Cryptography;
using System.Text;
using System.Text.Json;
using System.Threading.Tasks;

namespace VietAuth
{
    public class VietAuthClient
    {
        private readonly string _apiUrl;
        private readonly string _appId;
        private static readonly HttpClient httpClient = new HttpClient();

        public VietAuthClient(string appId, string baseUrl = "http://localhost:8080")
        {
            _appId = appId;
            _apiUrl = baseUrl.TrimEnd('/') + "/api/1.2";
        }

        public class LicenseResult
        {
            public bool Success { get; set; }
            public string Message { get; set; }
            public string Key { get; set; }
            public string SubscriptionLevel { get; set; }
            public bool IsLifetime { get; set; }
            public string ExpiresAt { get; set; }
            public int DaysRemaining { get; set; }
            public string Hwid { get; set; }
        }

        /// <summary>
        /// Xác thực mã key bản quyền với máy chủ VietAuth
        /// </summary>
        public async Task<LicenseResult> VerifyLicenseAsync(string licenseKey)
        {
            try
            {
                string hwid = GetMachineHwid();
                var payload = new
                {
                    license = licenseKey.Trim(),
                    hwid = hwid,
                    appId = _appId
                };

                string jsonPayload = JsonSerializer.Serialize(payload);
                var content = new StringContent(jsonPayload, Encoding.UTF8, "application/json");

                HttpResponseMessage response = await httpClient.PostAsync($"{_apiUrl}/license/verify", content);
                string responseBody = await response.Content.ReadAsStringAsync();

                using JsonDocument doc = JsonDocument.Parse(responseBody);
                JsonElement root = doc.RootElement;

                bool isSuccess = root.GetProperty("success").GetBoolean();
                string message = root.TryGetProperty("message", out var msgProp) ? msgProp.GetString() : "";

                var result = new LicenseResult
                {
                    Success = isSuccess,
                    Message = message
                };

                if (isSuccess && root.TryGetProperty("data", out var dataProp))
                {
                    if (dataProp.TryGetProperty("key", out var k)) result.Key = k.GetString();
                    if (dataProp.TryGetProperty("subscriptionLevel", out var lvl)) result.SubscriptionLevel = lvl.GetString();
                    if (dataProp.TryGetProperty("isLifetime", out var lt)) result.IsLifetime = lt.GetBoolean();
                    if (dataProp.TryGetProperty("expiresAt", out var exp)) result.ExpiresAt = exp.GetString();
                    if (dataProp.TryGetProperty("daysRemaining", out var days)) result.DaysRemaining = days.GetInt32();
                    if (dataProp.TryGetProperty("hwid", out var h)) result.Hwid = h.GetString();
                }

                return result;
            }
            catch (Exception ex)
            {
                return new LicenseResult
                {
                    Success = false,
                    Message = "Không thể kết nối đến máy chủ xác thực: " + ex.Message
                };
            }
        }

        /// <summary>
        /// Tạo mã HWID định danh duy nhất của phần cứng máy tính
        /// </summary>
        public static string GetMachineHwid()
        {
            string rawId = Environment.MachineName + "_" + Environment.UserName + "_" + Environment.ProcessorCount;
            using SHA256 sha = SHA256.Create();
            byte[] bytes = sha.ComputeHash(Encoding.UTF8.GetBytes(rawId));
            return "HWID-" + BitConverter.ToString(bytes).Replace("-", "").Substring(0, 16);
        }
    }

    // =========================================================================
    // CODE MẪU CHẠY THỬ NGHIỆM (DEMO USAGE)
    // =========================================================================
    class Program
    {
        static async Task Main(string[] args)
        {
            Console.OutputEncoding = Encoding.UTF8;
            Console.WriteLine("=================================================");
            Console.WriteLine("        VIET AUTH - TEST XÁC THỰC C# CLIENT      ");
            Console.WriteLine("=================================================\n");

            string appId = "app_pk_viet_9a8b7c6d5e4f"; // Lấy từ Dashboard VietAuth
            var auth = new VietAuthClient(appId);

            Console.Write("Nhập mã key bản quyền của bạn: ");
            string key = Console.ReadLine();

            Console.WriteLine("\n[*] Đang kiểm tra bản quyền với máy chủ...");
            var result = await auth.VerifyLicenseAsync(key);

            if (result.Success)
            {
                Console.ForegroundColor = ConsoleColor.Green;
                Console.WriteLine("\n[+] XÁC THỰC THÀNH CÔNG!");
                Console.WriteLine($"    Thông báo: {result.Message}");
                Console.WriteLine($"    Gói dịch vụ: {result.SubscriptionLevel}");
                Console.WriteLine($"    Thời hạn: {(result.IsLifetime ? "Vĩnh viễn (Lifetime)" : result.DaysRemaining + " ngày còn lại")}");
                Console.ResetColor();

                Console.WriteLine("\n--> Khởi chạy các chức năng của phần mềm...");
            }
            else
            {
                Console.ForegroundColor = ConsoleColor.Red;
                Console.WriteLine("\n[-] XÁC THỰC THẤT BẠI!");
                Console.WriteLine($"    Lý do: {result.Message}");
                Console.ResetColor();
            }

            Console.WriteLine("\nNhấn phím bất kỳ để thoát...");
            Console.ReadKey();
        }
    }
}
