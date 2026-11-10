# Shared Backend (Prototype Scaffold)

زیرساخت اولیه Backend مشترک برای Android و Web.

## فناوری‌ها
- FastAPI برای REST API
- PostgreSQL 16 + PostGIS برای داده‌های مکانی
- قرارداد مشترک در `shared/api-contracts/openapi.yaml`
- اسکیمای اولیه در `backend/database/init.sql`

## اجرای محلی

از ریشه مخزن:

```bash
docker compose -f backend/compose.yml up --build
```

سپس:
- Health: http://localhost:8000/healthz
- Database readiness: http://localhost:8000/readyz
- Swagger UI: http://localhost:8000/docs
- Route API (contract and implementation): POST http://localhost:8000/api/v1/routes

بدون NESHAN_API_KEY، درخواست traffic_preference=live برای خودرو/موتور پاسخ 503 می‌گیرد؛ می‌توانید موقتاً allow_non_traffic_fallback=true را بفرستید تا مسیر Valhalla با برچسب fallback_used=true و traffic_aware=false برگردد. فایل .env در Git نادیده گرفته می‌شود؛ کلید واقعی را commit نکنید.

Compose برای توسعه محلی است. پورت‌های API و دیتابیس فقط روی localhost bind شده‌اند و رمز پیش‌فرض صرفاً رمز توسعه است.

## راهبرد مسیریابی

- Valhalla سرویس پایه مسیریابی بدون ترافیک در نمونه اولیه است.
- Neshan Direction API گزینه ترافیک‌محور خودرو و موتورسیکلت است؛ قرارداد provider در shared/models/routing-provider-contract.json و endpoint هدف در shared/api-contracts/openapi.yaml ثبت شده‌اند.
- پیاده‌سازی proxy مسیریابی هنوز انجام نشده است. کلید Neshan باید فقط در secret محیط Backend نگهداری شود و هرگز در اپ‌های کلاینت یا Repository قرار نگیرد.
- در صورت نبود سرویس ترافیکی، مسیر Valhalla باید صریحاً به‌عنوان مسیر بدون ترافیک مشخص شود.

## وضعیت پیاده‌سازی

در این مرحله سرویس‌های health/readiness و POST /api/v1/routes پیاده‌سازی شده‌اند. مسیر ترافیک‌محور Neshan فقط پس از تنظیم NESHAN_API_KEY فعال می‌شود؛ در غیر این صورت API پاسخ 503 می‌دهد یا با اجازه صریح کاربر مسیر بدون ترافیک Valhalla را برمی‌گرداند. اتصال به دیتابیس در readiness بررسی می‌شود. جداول کاربران، مکان‌های ذخیره‌شده، تاریخچه مسیر و بازخورد نقشه در اسکیمای PostGIS تعریف شده‌اند.

Endpointهای مدیریت اطلاعات کاربر در OpenAPI به‌عنوان قرارداد هدف ثبت شده‌اند، اما هنوز در FastAPI پیاده‌سازی نشده‌اند. تا زمان اضافه شدن احراز هویت و CRUD، Android و Web داده مشترک را همگام نمی‌کنند. هیچ کلید یا رمز دیتابیس نباید داخل اپلیکیشن‌های کلاینت قرار بگیرد.

## پیش از استقرار
1. رمزهای توسعه را با secretهای قوی جایگزین کنید.
2. احراز هویت (JWT/OIDC)، مجوزدهی مالکیت داده و محدودسازی نرخ را پیاده‌سازی کنید.
3. Migrationهای نسخه‌بندی‌شده برای دیتابیس اضافه کنید.
4. Backup، TLS، مانیتورینگ و سیاست نگهداری داده را تنظیم کنید.
5. API را روی VPS یا سرویس مدیریت‌شده مستقر کنید و کلاینت‌ها را به Base URL نهایی وصل کنید.
