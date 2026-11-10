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

Compose برای توسعه محلی است. پورت‌های API و دیتابیس فقط روی localhost bind شده‌اند و رمز پیش‌فرض صرفاً رمز توسعه است.

## وضعیت پیاده‌سازی

در این مرحله فقط سرویس health/readiness اجرا می‌شود و اتصال به دیتابیس در readiness بررسی می‌شود. جداول کاربران، مکان‌های ذخیره‌شده، تاریخچه مسیر و بازخورد نقشه در اسکیمای PostGIS تعریف شده‌اند.

Endpointهای مدیریت اطلاعات کاربر در OpenAPI به‌عنوان قرارداد هدف ثبت شده‌اند، اما هنوز در FastAPI پیاده‌سازی نشده‌اند. تا زمان اضافه شدن احراز هویت و CRUD، Android و Web داده مشترک را همگام نمی‌کنند. هیچ کلید یا رمز دیتابیس نباید داخل اپلیکیشن‌های کلاینت قرار بگیرد.

## پیش از استقرار
1. رمزهای توسعه را با secretهای قوی جایگزین کنید.
2. احراز هویت (JWT/OIDC)، مجوزدهی مالکیت داده و محدودسازی نرخ را پیاده‌سازی کنید.
3. Migrationهای نسخه‌بندی‌شده برای دیتابیس اضافه کنید.
4. Backup، TLS، مانیتورینگ و سیاست نگهداری داده را تنظیم کنید.
5. API را روی VPS یا سرویس مدیریت‌شده مستقر کنید و کلاینت‌ها را به Base URL نهایی وصل کنید.
