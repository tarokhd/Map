# Iran Navigator

مخزن یکپارچه پروژه **Iran Navigator**؛ شامل اپلیکیشن‌های Android و iOS، نسخه وب، قراردادهای مشترک API و زیرساخت Backend.

## ساختار مخزن

~~~text
android/                  پوسته اندروید (Kotlin) با World مشترک
ios/                      پوسته آیفون و آیپد (SwiftUI) با World مشترک
web/                      پیش‌نمایش وب (MapLibre GL JS)
backend/                  API و پایگاه داده مشترک (FastAPI + PostGIS)
shared/
  api-contracts/          قرارداد رسمی API بین پلتفرم‌ها
  models/                 قرارداد ناوبری و adapterهای ارائه‌دهنده مسیر
docs/                     معماری و راهنمای توسعه
scripts/                  بررسی همسانی و تست سرویس‌های نقشه
.github/workflows/        CI/CD مستقل برای هر بخش
~~~

## سند محصول و نقشه راه

مشخصات جامع قابلیت‌های هدف، وضعیت واقعی نمونه اولیه، وابستگی‌های داده و مراحل توسعه در [سند Product Feature Parity](docs/PRODUCT_FEATURE_PARITY_FA.md) ثبت شده است. قابلیت‌های هدف تا زمان تست و تأیید نباید به‌عنوان امکانات تکمیل‌شده معرفی شوند.

## پلتفرم‌ها

### Android
پروژه اندروید در پوشه android قرار دارد. رابط و موتور نمایش مشترک داخل APK بسته‌بندی می‌شوند؛ مجوزها و GPS بومی‌اند. [راهنمای اندروید](android/README_FA.md).

~~~bash
cd android
gradle --no-daemon :app:testDebugUnitTest :app:assembleDebug
~~~

خروجی: android/app/build/outputs/apk/debug/app-debug.apk

### iOS
پروژه آیفون در پوشه ios با SwiftUI، CoreLocation و WKWebView همان World مشترک را اجرا می‌کند. پیش از xcodegen، `python3 scripts/package_world_assets.py --platform ios --output ios/build/World` را اجرا کنید. [راهنمای iOS](ios/README.md).

روی Mac با Xcode و Homebrew:

~~~bash
brew install xcodegen
cd ios
xcodegen generate
~~~

سپس ios/IranNavigator.xcodeproj را در Xcode باز کنید و یک iPhone Simulator را اجرا کنید. GitHub Actions تست‌های واحد و رابط کاربری را در شبیه‌ساز اجرا می‌کند و نسخه Simulator بدون امضای کد می‌سازد. این Artifact فایل IPA قابل نصب روی آیفون واقعی نیست؛ نصب روی دستگاه و TestFlight به امضای اپل نیاز دارد.

### Web
نسخه جدید وب از پوشه web منتشر می‌شود: صفحه شروع خلوت، انتخاب مقصد پیش از گزینه‌های سفر، ناوبری نزدیک به اول‌شخص و نور و بافت تطبیقی محیط. جزئیات در [راهنمای وب](web/README.md) ثبت شده است. نسخه مرورگر از MapLibre GL JS 5.24.0 با UMD استفاده می‌کند تا سازگاری با بارگذاری script قدیمی حفظ شود؛ تغییر نسخه باید همراه با تست مرورگر و Worker انجام شود:

https://tarokhd.github.io/Map/

### Backend و پایگاه داده
زیرساخت محلی API و PostgreSQL/PostGIS در پوشه backend آماده شده است:

~~~bash
docker compose -f backend/compose.yml up --build
~~~

- API محلی: http://localhost:8000/healthz
- وضعیت اتصال دیتابیس: http://localhost:8000/readyz
- مستندات API: http://localhost:8000/docs

Backend اکنون health/readiness و endpoint مسیریابی مشترک را پیاده‌سازی می‌کند. اتصال واقعی Neshan به NESHAN_API_KEY نیاز دارد؛ ذخیره مکان، تاریخچه مسیر و همگام‌سازی کاربران هنوز فعال نشده‌اند.

جزئیات هماهنگی وب، اندروید، iOS و نسخه‌های آینده در [معماری World مشترک](docs/SHARED_WORLD.md) ثبت شده است. تغییرات رابط و ناوبری در یک محل اعمال می‌شوند و CI هر نسخه از همان کد ساخته می‌شود.

## کنترل کیفیت و همسانی

- Android: تست‌های JUnit و ساخت APK
- iOS: تست‌های Swift و UI روی شبیه‌ساز، همراه با موقعیت شبیه‌سازی‌شده تهران
- Web: انتشار مستقل GitHub Pages
- Platform parity: بررسی خودکار حالت‌های سفر، دستورهای گردش، داده ساختمان سه‌بعدی و قالب polyline6 در هر سه کلاینت
- Browser smoke: اجرای Chromium واقعی، بررسی نقشه سه‌بعدی، جریان مقصد و مسیر، نور محیط، GPS و کش دارایی‌های ظاهری
- Navigation smoke: بررسی زنده سرویس‌های OpenFreeMap، Photon و Valhalla

برای اجرای دستی تست سرویس‌های عمومی:

~~~bash
python scripts/navigation_service_smoke.py
~~~

برای انتشار واقعی باید محدودیت‌ها و شرایط استفاده سرویس‌های عمومی بررسی و سرویس پایدار انتخاب شود.
