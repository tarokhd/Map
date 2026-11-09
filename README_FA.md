# Iran Navigator 2.0

نسخه آزمایشی اندروید با Kotlin و MapLibre Native.

## امکانات نسخه 2.0
- نقشه برداری تهران با تم روشن و تاریک
- زاویه دید مایل و ساختمان‌های سه‌بعدی در صورت وجود داده ارتفاع
- دریافت به‌روزرسانی موقعیت از GPS و Network Location با بررسی دقت
- انتخاب مبدأ و مقصد روی نقشه
- محاسبه مسیر خیابانی با Valhalla برای خودرو، موتورسیکلت و پیاده‌روی
- نمایش هندسه مسیر و مراحل گردش
- راهنمای متنی فارسی و Text-to-Speech در صورت پشتیبانی موتور صوتی دستگاه
- جست‌وجوی مکان با Photon و اولویت‌دهی بر اساس موقعیت یا مرکز نقشه

## ساخت
JDK 17، Android SDK Platform 35 و Gradle 8.9.

```bash
gradle --no-daemon :app:assembleDebug
```

خروجی: `app/build/outputs/apk/debug/app-debug.apk`

## محدودیت‌های نمونه اولیه
- سرویس عمومی Valhalla و Photon برای آزمایش استفاده می‌شوند؛ SLA یا تضمین پایداری ندارند. برای عرضه عمومی در ایران باید سرویس‌های اختصاصی و داده‌های به‌روز ایران میزبانی شوند.
- پوشش و صحت خیابان‌ها وابسته به داده OpenStreetMap است.
- راهنمای صوتی فارسی به نصب بودن صدای فارسی در موتور TTS دستگاه وابسته است.
- این نسخه هنوز تست میدانی روی گوشی واقعی و اعتبارسنجی مسیر در شهرهای مختلف ایران را پشت سر نگذاشته است.
- پیگیری مسیر در این نسخه پایه است؛ باز‌مسیریابی خودکار کامل، ترافیک زنده، نقشه آفلاین و هشدارهای پیشرفته در نسخه‌های بعدی هستند.

## منابع و انتساب
- MapLibre Native: https://github.com/maplibre/maplibre-native
- OpenFreeMap: https://openfreemap.org/
- OpenStreetMap contributors: https://www.openstreetmap.org/copyright
- Valhalla: https://github.com/valhalla/valhalla
- Photon: https://github.com/komoot/photon
