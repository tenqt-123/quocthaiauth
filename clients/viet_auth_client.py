# -*- coding: utf-8 -*-
"""
==============================================================================
VIET AUTH CLIENT FOR PYTHON 3
Tích hợp xác thực mã bản quyền Key & Khóa HWID cho Tool/Bot viết bằng Python
==============================================================================
"""

import sys
import uuid
import platform
import hashlib
import requests

class VietAuthClient:
    def __init__(self, app_id: str, base_url: str = "http://localhost:8080"):
        self.app_id = app_id
        self.api_url = base_url.rstrip("/") + "/api/1.2"
        self.session = requests.Session()

    @staticmethod
    def get_machine_hwid() -> str:
        """Tạo mã định danh phần cứng (Hardware ID) độc nhất của máy"""
        raw_info = f"{platform.node()}_{platform.machine()}_{uuid.getnode()}"
        sha = hashlib.sha256(raw_info.encode("utf-8")).hexdigest()
        return f"HWID-{sha[:16].upper()}"

    def verify_license(self, license_key: str) -> dict:
        """
        Gửi yêu cầu xác thực key bản quyền lên máy chủ VietAuth
        """
        hwid = self.get_machine_hwid()
        payload = {
            "license": license_key.strip(),
            "hwid": hwid,
            "appId": self.app_id
        }

        try:
            res = self.session.post(
                f"{self.api_url}/license/verify",
                json=payload,
                timeout=10,
                headers={"Content-Type": "application/json"}
            )
            return res.json()
        except requests.exceptions.RequestException as e:
            return {
                "success": False,
                "message": f"Không thể kết nối đến máy chủ VietAuth: {e}"
            }

    def get_variable(self, var_name: str) -> str:
        """Lấy biến cấu hình an toàn từ server (ví dụ: phiên bản, link tải update)"""
        try:
            res = self.session.get(f"{self.api_url}/variable?name={var_name}", timeout=5)
            data = res.json()
            if data.get("success"):
                return data.get("value")
            return None
        except Exception:
            return None


# ==============================================================================
# CHẠY TEST THỬ NGHIỆM CLIENT
# ==============================================================================
if __name__ == "__main__":
    print("=" * 60)
    print("         VIET AUTH - TEST XÁC THỰC BẢN QUYỀN PYTHON           ")
    print("=" * 60)

    # Thay bằng App ID của bạn tạo trong web
    APP_ID = "app_pk_viet_9a8b7c6d5e4f"
    client = VietAuthClient(app_id=APP_ID)

    print(f"[*] HWID máy tính của bạn: {client.get_machine_hwid()}")
    key = input("Nhập mã key bản quyền (VD: VIET-VIP-8888-9999-AAAA): ").strip()

    if not key:
        print("[-] Vui lòng không để trống mã key!")
        sys.exit(1)

    print("\n[*] Đang gửi yêu cầu xác thực tới máy chủ...")
    result = client.verify_license(key)

    if result.get("success"):
        print("\n[+] XÁC THỰC THÀNH CÔNG! BẢN QUYỀN HỢP LỆ.")
        print(f"    - Thông báo: {result.get('message')}")
        data = result.get("data", {})
        print(f"    - Gói bản quyền: {data.get('subscriptionLevel')}")
        print(f"    - Trạng thái: {data.get('status')}")
        print(f"    - Thời hạn: {'Vĩnh viễn' if data.get('isLifetime') else str(data.get('daysRemaining')) + ' ngày còn lại'}")
        print(f"    - Ngày hết hạn: {data.get('expiresAt') or 'Không giới hạn'}")
        
        # Test lấy biến từ xa
        ver = client.get_variable("APP_VERSION")
        if ver:
            print(f"    - Phiên bản mới nhất từ server: {ver}")

        print("\n--> Khởi chạy chương trình chính của bạn tại đây!\n")
    else:
        print("\n[-] XÁC THỰC THẤT BẠI!")
        print(f"    - Lý do: {result.get('message')}\n")
