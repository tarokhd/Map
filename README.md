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
  models/                 قواعد مدل‌های مشترک
docs/                     معماری و راهنمای توسعه
.github/workflows/        CI/CD مستقل برای هر بخش
~~~

## پلتفرم‌ها

### Android
پروژه اندروید در پوشه android قرار دارد.

~~~bash
cd android
gradle --no-daemon :app:assembleDebug
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

سپس ios/IranNavigator.xcodeproj را در Xcode باز کنید و یک iPhone Simulator را اجرا کنید. GitHub Actions نیز یک نسخه Simulator بدون امضای کد می‌سازد. این Artifact فایل IPA قابل نصب روی آیفون واقعی نیست؛ نصب روی دستگاه و TestFlight به امضای اپل نیاز دارد.

### Web
پیش‌نمایش وب از پوشه web منتشر می‌شود:

https://tarokhd.github.io/Map/

برای انتشار خودکار، در GitHub از مسیر Settings → Pages گزینه GitHub Actions را به‌عنوان Source انتخاب کنید.

### Backend و پایگاه داده
زیرساخت محلی API و PostgreSQL/PostGIS در پوشه backend آماده شده است:

~~~bash
docker compose -f backend/compose.yml up --build
~~~

- API محلی: http://localhost:8000/healthz
- وضعیت اتصال دیتابیس: http://localhost:8000/readyz
- مستندات API: http://localhost:8000/docs

تنظیمات Compose برای توسعه محلی است و پورت‌ها فقط روی localhost منتشر می‌شوند.

## وضعیت یکپارچگی داده‌ها

این Monorepo و قرارداد OpenAPI و اسکیمای PostGIS را آماده می‌کند؛ اما همگام‌سازی واقعی حساب‌ها، مکان‌های ذخیره‌شده و تاریخچه مسیر بین کلاینت‌ها هنوز فعال نشده است. Backend فعلاً فقط health/readiness را پیاده‌سازی می‌کند. اتصال مستقیم کلاینت‌ها به دیتابیس مجاز نیست؛ هر دو باید از API مشترک استفاده کنند.

## گردش‌کارهای مستقل

- تغییرات android/: Build اندروید
- تغییرات ios/: Build شبیه‌ساز iOS روی macOS
- تغییرات web/: انتشار GitHub Pages
- تغییرات backend/ یا shared/: بررسی Backend و قراردادها

جزئیات بیشتر در docs/ARCHITECTURE.md آمده است.

## نقشه و داده‌ها

کلاینت‌ها از MapLibre و سرویس‌های نمونه OpenFreeMap، OpenStreetMap، Photon و Valhalla استفاده می‌کنند. سرویس‌های عمومی برای نمونه اولیه هستند و SLA یا پوشش کامل ایران را تضمین نمی‌کنند. برای انتشار واقعی باید سرویس‌های پایدار و سیاست‌های استفاده و انتساب داده رعایت شوند.
