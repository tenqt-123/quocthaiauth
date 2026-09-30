"""
==============================================================================
QUỐC THÁI AUTH CLIENT FOR PYTHON 3
Tương thích hoàn toàn với server https://quocthaiauth.onrender.com
Hỗ trợ cả 2 phương thức xác thực:
  1. Xác thực bằng Mã Key Bản Quyền: auth.login_key("VIET-VIP-...")
  2. Xác thực bằng Tài Khoản & Mật Khẩu: auth.login_user("username", "password")
==============================================================================
"""

import sys
import os
import time
import socket
import hashlib
import platform
import json
import urllib.request
import urllib.error

class QuocThaiAuthClient:
    def __init__(self, app_id: str, base_url: str = "https://quocthaiauth.onrender.com"):
        self.app_id = app_id
        self.base_url = base_url.rstrip("/")
        self.token = ""
        self.hwid = self.get_machine_hwid()
        self.online_users = "1"
        self.user_data = {}

    def get_machine_hwid(self) -> str:
        """Sinh mã phần cứng duy nhất của máy tính"""
        try:
            raw = f"{platform.node()}_{platform.processor()}_{os.getlogin()}"
            return "HWID-" + hashlib.sha256(raw.encode()).hexdigest()[:16].upper()
        except Exception:
            return "HWID-PYTHON-CLIENT"

    def _post(self, path: str, payload: dict) -> dict:
        url = f"{self.base_url}/api/v1/client{path}"
        data = json.dumps(payload).encode("utf-8")
        req = urllib.request.Request(
            url,
            data=data,
            headers={
                "Content-Type": "application/json",
                "x-app-id": self.app_id,
                "x-hwid": self.hwid,
                "User-Agent": "QuocThaiAuth-Python/1.0"
            }
        )
        if self.token:
            req.add_header("Authorization", f"Bearer {self.token}")

        try:
            with urllib.request.urlopen(req, timeout=12) as res:
                body = res.read().decode("utf-8")
                return json.loads(body)
        except urllib.error.HTTPError as e:
            try:
                err_body = e.read().decode("utf-8")
                return json.loads(err_body)
            except Exception:
                return {"success": False, "error": f"Lỗi HTTP {e.code}"}
        except Exception as e:
            return {"success": False, "error": f"Không thể kết nối máy chủ: {e}"}

    def init(self) -> bool:
        """1. Khởi tạo kết nối với máy chủ QuocThaiAuth"""
        res = self._post("/init", {"appId": self.app_id, "hwid": self.hwid})
        if res.get("success"):
            self.token = res.get("token", "")
            self.online_users = str(res.get("numOnlineUsers", "1"))
            return True
        return False

    def login_key(self, key: str) -> dict:
        """2. Xác thực bằng Mã Key Bản Quyền"""
        res = self._post("/login", {"key": key.strip(), "hwid": self.hwid, "appId": self.app_id})
        if res.get("success"):
            self.token = res.get("token", "")
            self.online_users = str(res.get("numOnlineUsers", "1"))
            self.user_data = res
        return res

    def login_user(self, username: str, password: str) -> dict:
        """3. Xác thực bằng Tài Khoản & Mật Khẩu (User Account)"""
        res = self._post("/login-user", {
            "username": username.strip(),
            "password": password.strip(),
            "hwid": self.hwid,
            "appId": self.app_id
        })
        if res.get("success"):
            self.token = res.get("token", "")
            self.online_users = str(res.get("numOnlineUsers", "1"))
            self.user_data = res
        return res

    def check(self) -> bool:
        """4. Gửi heartbeat duy trì trạng thái Online"""
        res = self._post("/check", {"hwid": self.hwid, "appId": self.app_id})
        if res.get("success"):
            self.online_users = str(res.get("numOnlineUsers", self.online_users))
            return True
        return False


# VÍ DỤ CHẠY THỬ NGHIỆM:
if __name__ == "__main__":
    APP_ID = "app_pk_viet_9a8b7c6d5e4f"
    BASE_URL = "https://quocthaiauth.onrender.com"

    auth = QuocThaiAuthClient(APP_ID, BASE_URL)
    print("=" * 50)
    print("      QUỐC THÁI AUTH - DEMO XÁC THỰC PYTHON")
    print("=" * 50)
    print(f"[*] HWID máy: {auth.hwid}")
    print("[*] Đang kết nối máy chủ...")

    if not auth.init():
        print("[-] Không thể kết nối tới máy chủ QuocThaiAuth!")
        sys.exit(1)

    print(f"[+] Kết nối thành công! Số máy đang Online: {auth.online_users}")
    print("\nChọn hình thức đăng nhập:")
    print("1. Đăng nhập bằng Mã Key Bản Quyền")
    print("2. Đăng nhập bằng Tài Khoản & Mật Khẩu")

    choice = input("Lựa chọn (1 hoặc 2): ").strip()
    if choice == "1":
        key = input("Nhập mã key bản quyền: ").strip()
        result = auth.login_key(key)
        if result.get("success"):
            print(f"[+] XÁC THỰC KEY THÀNH CÔNG! Gói: {result.get('subscription')}")
            print(f"[+] Thời hạn hết hạn: {result.get('expiresAt')}")
        else:
            print(f"[-] Thất bại: {result.get('error', 'Lỗi không xác định')}")
    else:
        user = input("Tên tài khoản: ").strip()
        pwd = input("Mật khẩu: ").strip()
        result = auth.login_user(user, pwd)
        if result.get("success"):
            print(f"[+] ĐĂNG NHẬP THÀNH CÔNG! Xin chào {user}")
            print(f"[+] Gói: {result.get('subscription')}, Hạn: {result.get('expiresAt')}")
        else:
            print(f"[-] Thất bại: {result.get('error', 'Lỗi không xác định')}")
