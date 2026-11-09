# TVEXP: Universal + ABI Split APKs

## ما الذي تغير؟
- يبني GitHub Actions ملف APK شاملًا (Universal) لكل خدمة، ويظل هو رابط التحديث التلقائي الحالي لضمان التوافق مع UpdateService الحالية.
- يبني أيضًا APKs منفصلة حسب ABI باستخدام `--split-per-abi` لتقليل حجم التنزيل اليدوي للأجهزة المتوافقة.
- يحتفظ بملف AAB لكل خدمة.
- ينشر الملفات الأربعة/أكثر في Release الخاص بالخدمة: Universal APK، AAB، وملفات ABI split، وملف latest-mobile.json أو latest-tv.json.
- يبقى تطبيق Mobile وتطبيق TV منفصلين في package ID وقناة التحديث والتوقيع.
- أزيل ملف JKS من حزمة التسليم، وأضيف إلى `.gitignore`.

## مهم بشأن التحديث التلقائي
ملف `latest-*.json` ما زال يشير إلى Universal APK. هذا مقصود وآمن؛ لأن خدمة التحديث الحالية لا تختار ABI بنفسها ولا تتحقق من توافق كل split مع الجهاز. ملفات ABI الأصغر متاحة للتنزيل اليدوي من صفحة GitHub Release.

لا تغيّر رابط التحديث إلى APK split قبل تنفيذ اختيار ABI موثوق في Android/Kotlin والتحقق من توافقه مع `Build.SUPPORTED_ABIS`، وإلا قد يتعذر تثبيت تحديث على بعض الأجهزة.

## أسماء الملفات
- `TVEXP-Mobile-<version>-universal.apk`
- `TVEXP-Mobile-<version>-<abi>-release.apk` (قد يختلف ترتيب اسم flavor/ABI حسب Flutter، ويعاد تسميته تلقائيًا من اسم الملف الناتج)
- `TVEXP-Mobile-<version>.aab`
- النظائر الخاصة بـ TV.

## الاختبار
تم فحص صياغة YAML محليًا، والتأكد من وجود أمر split وعدم وجود علامات دمج. لم يتم تشغيل Flutter/Gradle build في هذه البيئة؛ لذلك يجب اعتماد الناتج بعد نجاح GitHub Actions، وفحص أسماء وأحجام ملفات APK الناتجة.
