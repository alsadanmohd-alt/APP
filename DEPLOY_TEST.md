# نشر نسخة «قريب» المتصلة للاختبار

هذه الحزمة جاهزة للنشر على Vercel والاتصال بـ Supabase.

## 1) Supabase جديد
1. أنشئ مشروع Supabase جديدًا.
2. نفّذ `supabase/schema.sql` في SQL Editor.
3. من Authentication فعّل **Anonymous Sign-ins** للاختبار السريع.
4. لاحقًا، لاختبار رقم الجوال فعّل Phone واضبط مزود SMS.
5. انسخ Project URL وPublishable/Anon key.

إذا كانت لديك قاعدة «قريب» موجودة مسبقًا، لا تعِد تشغيل `schema.sql`. طبّق الترحيلات حسب ترتيبها، ومنها `supabase/migrations/003_party_category.sql`.

## 2) Vercel
ارفع هذا المجلد كمشروع Next.js وأضف متغيرات البيئة:

```env
NEXT_PUBLIC_SUPABASE_URL=https://YOUR_PROJECT.supabase.co
NEXT_PUBLIC_SUPABASE_ANON_KEY=YOUR_PUBLIC_KEY
NEXT_PUBLIC_ENABLE_TEST_LOGIN=true
```

ثم Deploy. بعد اكتمال الاختبار، اجعل `NEXT_PUBLIC_ENABLE_TEST_LOGIN=false` وأعد النشر.

## 3) اختبار فعلي بين مستخدمين
- افتح الرابط في متصفح عادي واضغط دخول > دخول تجريبي سريع. هذا حساب المالك.
- أضف غرضًا وصورة وسعرًا وموقعًا.
- افتح الرابط في نافذة خاصة/Incognito واضغط دخول تجريبي سريع. هذا حساب المستأجر.
- اطلب حجز الغرض.
- ارجع لحساب المالك واقبل الطلب.
- جرّب المحادثة من الطرفين.
- بعد اكتمال مدة الحجز يستطيع المالك تعليم الحجز مكتملًا، ثم يستطيع المستأجر كتابة تقييم.

## مهم قبل الإطلاق العام
- عطّل Anonymous Sign-ins وأوقف `NEXT_PUBLIC_ENABLE_TEST_LOGIN`.
- فعّل Phone + SMS إذا أردت الدخول بالجوال.
- لا تضع أي `service_role` أو secret داخل متغير يبدأ بـ `NEXT_PUBLIC_`.
