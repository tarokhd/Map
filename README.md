# Iran Navigator

مخزن یکپارچه پروژه **Iran Navigator**؛ شامل اپلیکیشن‌های Android و iOS، نسخه وب، قراردادهای مشترک API و زیرساخت Backend.

## ساختار مخزن

~~~text
android/                  اپلیکیشن Native اندروید (Kotlin)
ios/                      اپلیکیشن Native آیفون و آیپد (SwiftUI)
web/                      پیش‌نمایش وب (MapLibre GL JS)
backend/                  API و پایگاه داده مشترک (FastAPI + PostGIS)
shared/
  api-contracts/          قرارداد رسمی API بین پلتفرم‌ها
  models/                 مدل‌ها و قرارداد ناوبری مشترک
docs/                     معماری و راهنمای توسعه
scripts/                  بررسی همسانی و تست سرویس‌های نقشه
.github/workflows/        CI/CD مستقل برای هر بخش
~~~

## پلتفرم‌ها

### Android
پروژه اندروید در پوشه android قرار دارد.

~~~bash
cd android
gradle --no-daemon :app:testDebugUnitTest :app:assembleDebug
~~~

خروجی: android/app/build/outputs/apk/debug/app-debug.apk

### iOS
پروژه Native آیفون در پوشه ios قرار دارد و با SwiftUI، CoreLocation و MapLibre Native ساخته می‌شود.

روی Mac با Xcode و Homebrew:

~~~bash
brew install xcodegen
cd ios
xcodegen generate
~~~

سپس ios/IranNavigator.xcodeproj را در Xcode باز کنید و یک iPhone Simulator را اجرا کنید. GitHub Actions تست‌های واحد و رابط کاربری را در شبیه‌ساز اجرا می‌کند و نسخه Simulator بدون امضای کد می‌سازد. این Artifact فایل IPA قابل نصب روی آیفون واقعی نیست؛ نصب روی دستگاه و TestFlight به امضای اپل نیاز دارد.

### Web
پیش‌نمایش وب از پوشه web منتشر می‌شود:

https://tarokhd.github.io/Map/

### Backend و پایگاه داده
زیرساخت محلی API و PostgreSQL/PostGIS در پوشه backend آماده شده است:

~~~bash
docker compose -f backend/compose.yml up --build
~~~

- API محلی: http://localhost:8000/healthz
- وضعیت اتصال دیتابیس: http://localhost:8000/readyz
- مستندات API: http://localhost:8000/docs

همگام‌سازی واقعی کاربران و داده‌ها هنوز فعال نشده است؛ Backend فعلاً فقط health/readiness را پیاده‌سازی می‌کند.

## کنترل کیفیت و همسانی

- Android: تست‌های JUnit و ساخت APK
- iOS: تست‌های Swift و UI روی شبیه‌ساز، همراه با موقعیت شبیه‌سازی‌شده تهران
- Web: انتشار مستقل GitHub Pages
- Platform parity: بررسی خودکار حالت‌های سفر، دستورهای گردش، داده ساختمان سه‌بعدی و قالب polyline6 در هر سه کلاینت
- Navigation smoke: بررسی زنده سرویس‌های OpenFreeMap، Photon و Valhalla

برای اجرای دستی تست سرویس‌های عمومی:

~~~bash
python scripts/navigation_service_smoke.py
~~~

برای انتشار واقعی باید محدودیت‌ها و شرایط استفاده سرویس‌های عمومی بررسی و سرویس پایدار انتخاب شود.
