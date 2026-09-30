// ==============================================================================
// VÍ DỤ TÍCH HỢP QUOCTHAIAUTH VÀO TOOL C++ (TƯƠNG THÍCH KEYAUTH / LONGAUTH)
// Biên dịch:
//   MinGW / GCC:  g++ main.cpp -lcurl -lcrypto -o tool_vip.exe
//   Visual Studio: Thêm libcurl và OpenSSL vào project, sau đó Build
// ==============================================================================

#include <iostream>
#include <string>
#include "quocthaiauth.hpp"

// THAY ĐỔI CÁC THÔNG SỐ TƯƠNG ỨNG VỚI ỨNG DỤNG BẠN TẠO TRÊN WEB:
const std::string APP_NAME      = "Tool VIP QuocThai";
const std::string APP_OWNERID   = "app_pk_viet_9a8b7c6d5e4f";                 // App ID từ web QuocThaiAuth
const std::string APP_VERSION   = "1.0.0";
const std::string APP_URL       = "https://quocthaiauth.onrender.com";       // Domain máy chủ chính thức
const std::string APP_SECRET    = "sk_live_viet_849203847291039482";         // App Secret Key từ web

// Khởi tạo đối tượng QuocThaiAuth (hoặc KeyAuth)
QuocThaiAuth::api QuocThaiApp(APP_NAME, APP_OWNERID, APP_VERSION, APP_URL, APP_SECRET);
#define KeyAuthApp QuocThaiApp

int main() {
    // Đổi font tiếng Việt console trên Windows nếu cần
    #ifdef _WIN32
    SetConsoleOutputCP(65001);
    #endif

    std::cout << "====================================================\n";
    std::cout << "          " << APP_NAME << " - BẢN QUYỀN API        \n";
    std::cout << "====================================================\n\n";

    // 1. Khởi tạo kết nối hệ thống
    std::cout << "[*] Dang ket noi toi he thong xac thuc..." << std::endl;
    KeyAuthApp.init();

    if (!KeyAuthApp.response.success) {
        std::cout << "[-] Loi khoi tao: " << KeyAuthApp.response.message << std::endl;
        std::cout << "[-] Vui long kiem tra internet hoac lien he Admin.\n";
        system("pause");
        return 1;
    }

    std::cout << "[+] Ket noi may chu thanh cong!" << std::endl;
    std::cout << "[+] So may dang truy cap he thong: " << KeyAuthApp.app_data.numOnlineUsers << " may" << std::endl;
    std::cout << "[+] Tong so key hoat dong:         " << KeyAuthApp.app_data.numKeys << " key" << std::endl;
    std::cout << "----------------------------------------------------\n";

    // 2. Menu đăng nhập
    std::cout << "[1] Kich hoat / Dang nhap bang Key Ban Quyen\n";
    std::cout << "[2] Dang nhap bang Tai Khoan & Mat Khau\n";
    std::cout << "[3] Dang ky tai khoan moi bang Key\n";
    std::cout << "[?] Lua chon cua ban (1-3): ";
    
    int choice = 1;
    std::cin >> choice;

    if (choice == 1) {
        std::string key;
        std::cout << "\n[?] Nhap ma key ban quyen: ";
        std::cin >> key;

        std::cout << "[*] Dang xac thuc key va kiem tra HWID..." << std::endl;
        KeyAuthApp.license(key);

        if (!KeyAuthApp.response.success) {
            std::cout << "\n[-] XAC THUC THAT BAI: " << KeyAuthApp.response.message << std::endl;
            system("pause");
            return 1;
        }

        std::cout << "\n[+] XAC THUC THANH CONG!" << std::endl;
        std::cout << "[+] Goi ban quyen:   " << KeyAuthApp.user_data.subscriptions[0].name << std::endl;
        std::cout << "[+] Thoi han con lai: " << KeyAuthApp.expiryLabel() << std::endl;
        std::cout << "[+] HWID may tinh:    " << KeyAuthApp.user_data.hwid << std::endl;
    } 
    else if (choice == 2) {
        std::string username, password;
        std::cout << "\n[?] Username: ";
        std::cin >> username;
        std::cout << "[?] Password: ";
        std::cin >> password;

        KeyAuthApp.login(username, password);
        if (!KeyAuthApp.response.success) {
            std::cout << "\n[-] Dang nhap that bai: " << KeyAuthApp.response.message << std::endl;
            system("pause");
            return 1;
        }
        std::cout << "\n[+] Dang nhap thanh cong! Xin chao " << KeyAuthApp.user_data.username << std::endl;
    }
    else if (choice == 3) {
        std::string username, password, key;
        std::cout << "\n[?] Nhap key ban quyen de kich hoat: ";
        std::cin >> key;
        std::cout << "[?] Tao username moi: ";
        std::cin >> username;
        std::cout << "[?] Tao password moi: ";
        std::cin >> password;

        KeyAuthApp.regstr(username, password, key);
        if (!KeyAuthApp.response.success) {
            std::cout << "\n[-] Dang ky that bai: " << KeyAuthApp.response.message << std::endl;
            system("pause");
            return 1;
        }
        std::cout << "\n[+] Dang ky va dang nhap thanh cong!" << std::endl;
    }

    // 3. Lấy biến từ xa (VD: Link update phần mềm)
    std::string updateUrl = KeyAuthApp.getvar("UPDATE_URL");
    if (!updateUrl.empty()) {
        std::cout << "[+] Bien may chu (UPDATE_URL): " << updateUrl << std::endl;
    }

    // 4. Bắt đầu chương trình chính
    std::cout << "\n====================================================\n";
    std::cout << " [SUCCESS] Chuc mung! Tool da duoc kich hoat thanh cong!\n";
    std::cout << " [STATUS]  Chay tinh nang chinh cua tool tai day...\n";
    std::cout << "====================================================\n\n";

    system("pause");
    return 0;
}
