# Iran Navigator

مخزن یکپارچه پروژه **Iran Navigator**؛ شامل اپلیکیشن اندروید، نسخه وب، قراردادهای مشترک API و زیرساخت Backend.

## ساختار مخزن

```text
android/                  اپلیکیشن Native اندروید (Kotlin)
web/                      پیش‌نمایش وب (MapLibre GL JS)
backend/                  API و پایگاه داده مشترک (FastAPI + PostGIS)
shared/
  api-contracts/          قرارداد رسمی API بین پلتفرم‌ها
  models/                 قواعد مدل‌های مشترک
docs/                     معماری و راهنمای توسعه
.github/workflows/        CI/CD مستقل برای هر بخش
```

## پلتفرم‌ها

### Android
پروژه اندروید در پوشه `android/` قرار دارد.

```bash
cd android
gradle --no-daemon :app:assembleDebug
```

خروجی: `android/app/build/outputs/apk/debug/app-debug.apk`

### Web
پیش‌نمایش وب از پوشه `web/` منتشر می‌شود:

https://tarokhd.github.io/Map/

برای انتشار خودکار، در GitHub از مسیر **Settings → Pages** گزینه **GitHub Actions** را به‌عنوان Source انتخاب کنید. Workflow وب نیز تلاش می‌کند Pages را در صورت امکان فعال کند.

### Backend و پایگاه داده
زیرساخت محلی API و PostgreSQL/PostGIS در پوشه `backend/` آماده شده است:

```bash
docker compose -f backend/compose.yml up --build
```

- API محلی: http://localhost:8000/healthz
- وضعیت اتصال دیتابیس: http://localhost:8000/readyz
- مستندات API: http://localhost:8000/docs

تنظیمات Compose برای توسعه محلی است و پورت‌ها فقط روی localhost منتشر می‌شوند.

## وضعیت یکپارچگی داده‌ها

این Monorepo و قرارداد OpenAPI و اسکیمای PostGIS را آماده می‌کند؛ اما **همگام‌سازی واقعی حساب‌ها، مکان‌های ذخیره‌شده و تاریخچه مسیر بین Android و Web هنوز فعال نشده است**. در حال حاضر Backend فقط health/readiness را پیاده‌سازی می‌کند. برای همگام‌سازی باید احراز هویت، endpointهای CRUD قراردادشده و استقرار Backend روی سرور انجام شود. اتصال مستقیم اپلیکیشن‌ها به دیتابیس مجاز نیست؛ هر دو باید از API مشترک استفاده کنند.

## گردش‌کارهای مستقل

- تغییرات `android/` یا قراردادهای مشترک: Build اندروید
- تغییرات `web/`: انتشار GitHub Pages
- تغییرات `backend/` یا قراردادهای مشترک: بررسی Backend

جزئیات بیشتر در `docs/ARCHITECTURE.md` آمده است.

## نقشه و داده‌ها

پیش‌نمایش از MapLibre، OpenFreeMap، OpenStreetMap، Photon و Valhalla استفاده می‌کند. سرویس‌های عمومی صرفاً برای نمونه اولیه هستند و SLA یا پوشش کامل ایران را تضمین نمی‌کنند. برای انتشار واقعی باید سرویس‌های پایدار و سیاست‌های استفاده و انتساب داده رعایت شوند.
