# NFC Student Scanner – Android APK Builder

Bộ này tạo app Android biến điện thoại thành máy quét NTAG215:

NTAG215 → Android đọc UID → HTTP POST → Node.js trên laptop → dashboard điểm danh.

## Yêu cầu trên Windows

1. Flutter Stable hiện hành.
2. Android Studio + Android SDK.
3. Chạy `flutter doctor` và đảm bảo mục Android toolchain không còn lỗi.
4. Internet khi build lần đầu để tải package.

App dùng:
- `nfc_manager 4.2.1`
- `http 1.6.0`

## Build APK tự động

Giải nén thư mục này rồi double-click:

`build_apk.bat`

Script sẽ:
1. kiểm tra Flutter;
2. tạo project Android bằng chính phiên bản Flutter trên máy;
3. chép code scanner;
4. tải dependency;
5. chạy `flutter build apk --release`;
6. tạo file:

`NFCStudentScanner.apk`

## Cài APK

Cách 1: copy `NFCStudentScanner.apk` sang Android và mở file để cài.

Cách 2, nếu đã có ADB:

`adb install -r NFCStudentScanner.apk`

## Dùng app

Laptop phải chạy backend đã tạo trước đó:

`node server.js`

Laptop và Android phải cùng Wi‑Fi/hotspot.

Trong app nhập địa chỉ laptop, ví dụ:

`http://192.168.137.1:3000`

Sau đó:
1. Bấm `Kiểm tra kết nối laptop`.
2. Bấm `Bắt đầu quét`.
3. Đưa NTAG215 sát mặt lưng điện thoại.
4. App đọc UID thật, ví dụ `04:A2:7F:1B:5E:80:00`.
5. App POST JSON tới `/api/nfc-scan`.
6. Laptop cập nhật điểm danh.

## Payload gửi về laptop

```json
{
  "uid": "04:A2:7F:1B:5E:80:00",
  "date": "2026-10-04T09:30:00.000Z",
  "content": ""
}
```

## Android permissions đã cấu hình

- NFC
- INTERNET
- `usesCleartextTraffic=true` để demo qua HTTP nội bộ.

## Nếu không kết nối được laptop

- Android và laptop phải cùng mạng.
- Windows Firewall phải cho phép Node.js ở Private network.
- Server Node.js phải listen `0.0.0.0:3000`.
- Không nhập `localhost` trên Android. `localhost` trên điện thoại là chính điện thoại.
- Dùng `ipconfig` trên Windows để lấy IPv4 của Wi‑Fi/hotspot.

## Ghi chú

App yêu cầu thiết bị Android có NFC (`android.hardware.nfc required=true`).
NTAG215 là NFC Type 2 / ISO 14443-A nên scanner dùng polling ISO 14443.
