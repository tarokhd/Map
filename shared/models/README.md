# Shared Data Models

قرارداد داده مشترک برای کلاینت Android، کلاینت Web و Backend باید از `../api-contracts/openapi.yaml` پیروی کند.

## قواعد مهم
- مختصات در مدل API به شکل فیلدهای نام‌دار `latitude` و `longitude` هستند.
- در GeoJSON ترتیب مختصات همیشه `[longitude, latitude]` است.
- شناسه رکوردها UUID هستند.
- زمان‌ها در API با ISO-8601 و timezone مشخص ارسال می‌شوند.
- مقادیر `travel_mode`: `car`، `motorcycle` و `walking`.
- داده متعلق به کاربر فقط از طریق Backend و پس از احراز هویت/مجوزدهی قابل خواندن یا تغییر است.

مدل‌های Kotlin و TypeScript باید با این قرارداد سازگار بمانند. کلاینت‌ها نباید مستقیماً به PostgreSQL متصل شوند.
