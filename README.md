# NotifyReward

Tweak jailbreak iOS để bắt notification từ app ngân hàng forward về server xử lý tự động.

Mình làm cái này vì lười cộng tiền thủ công cho khách mà lại không có API của con VIB để tích hợp nên để nó tự forward qua server rồi server làm gì thì làm =))

## Yêu cầu

- iOS 14.0 - 16.x
- Jailbreak

## Build

```bash
export THEOS=/path/to/theos
make package
```

## Sửa code cho app của bạn

Vào [Tweak.xm](Tweak.xm) sửa 4 dòng `#define` đầu file:

```objc
#define NR_SERVER   @"http://ip-server:port/path"
#define NR_SECRET   @"secret-key"
#define NR_BUNDLE   @"com.banking.abcxyz"
#define NR_TITLE    @"Title"
```

Rồi `make package` lại.

## Server nhận gì

POST JSON:

```json
{
  "appName": "com.vib.myvib2prod",
  "title":   "Thông báo giao dịch",
  "text":    "GD 100k...",
  "time":    1717000000
}
```

Header: `x-bank-secret` để auth.

## Cơ chế

Hook `BBServer` → lọc theo bundle + title → gửi HTTP qua raw socket bind thẳng `en0` (không đi qua VPN).

Dùng raw socket để tránh bị VPN chặn. Dedup bằng `bulletinID` để không gửi trùng.
