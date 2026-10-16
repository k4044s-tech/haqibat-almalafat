# إعداد مشروع Firebase الخاص بالحقيبة

1. https://console.firebase.google.com ← Create a new Firebase project ← الاسم: haqibat-almalafat (Google Analytics غير مطلوب).
2. Build ← Authentication ← Get started ← Sign-in method ← فعّل Email/Password.
3. Authentication ← Settings ← Authorized domains ← Add domain ← k4044s-tech.github.io
4. Build ← Firestore Database ← Create database ← Production mode ← اختر أقرب موقع متاح.
5. Firestore ← Rules ← الصق محتوى firestore.rules كاملًا ← Publish.
6. ⚙️ Project settings ← Your apps ← أيقونة الويب </> ← سجّل التطبيق ← انسخ firebaseConfig.
7. ضع firebaseConfig في index.html مكان: const FIREBASE_CONFIG=null;
8. ارفع index.html و .nojekyll إلى GitHub وفعّل Pages.
9. من الموقع: «إنشاء حساب».
10. Firestore ← haqiba_users ← مستندك: role = admin ، status = active ← أعد تحميل الموقع.

## باركود الشواهد
- عند اختيار «باركود» في «عرض الشواهد» تُضغط صورة الشاهد وتُحفظ في مجموعة `haqiba_ev` في Firestore، ويُطبع رمز QR يفتح صفحة عرض الشاهد.
- لا يحتاج Firebase Storage ولا خطة مدفوعة؛ يكفي Firestore (حجم الصورة بعد الضغط أقل من 1MB).
- القواعد في firestore.rules تسمح لأي شخص يملك الرابط بفتح الشاهد، ولا تسمح باستعراض قائمة الشواهد إلا للمشرف.
- لا تضع في الشواهد صورًا تحتوي بيانات شخصية حساسة للطلاب.

## منصة البطاقات
- عند الضغط على «نشر رابط للبطاقة» يُحفظ التصميم في مجموعة `haqiba_cards` في Firestore، ويُنشأ رابط بالشكل `#/c/<المعرّف>` مع باركود.
- يفتح أي شخص الرابط دون تسجيل دخول، ويكتب اسمه، ويحمّل البطاقة صورة PNG تُرسم في متصفحه.
- النشر متاح للحسابات المفعّلة فقط، ولا يعدّل البطاقة أو يحذفها إلا صاحبها (والمشرف للحذف). صورة التصميم المرفوعة تُضغط تلقائيًا لتبقى أقل من 1 ميجابايت.
- القواعد اللازمة موجودة في `firestore.rules` (قسم `haqiba_cards`)، فانشر الملف كاملًا بعد التحديث.

