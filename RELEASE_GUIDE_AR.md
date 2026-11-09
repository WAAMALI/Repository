# دليل إصدار TVEXP

## التطبيقات وقنوات التحديث
- الهاتف: `mobile-v*`، الحزمة `com.tvexp.iptv`، والبيان `latest-mobile.json`.
- الشاشات: `tv-v*`، الحزمة `com.tvexp.iptv.tv`، والبيان `latest-tv.json`.
- مستودع الإصدارات: `WAAMALI/tvexp-releases`.
- الإصدار الحالي المجهز: `2.3.3+14`.

## تشغيل الفيديو
TVEXP لا يضمّن مشغل فيديو داخليًا. يرسل روابط البث والملفات إلى تطبيقات التشغيل المثبتة على الجهاز باستخدام Android Intent. اختر VLC أو أي مشغل متوافق من شاشة اختيار التطبيق، ويمكنك تعيينه كتطبيق افتراضي من Android إذا رغبت.

الملفات المحلية تُفتح عبر `FileProvider`، وروابط التنزيل من Android Download Manager تُمرر كـ `content://` مع صلاحية القراءة.

## إصدار خدمة واحدة أو الخدمتين
1. افتح GitHub Actions ثم `TVEXP Mobile and TV Release`.
2. اختر Run workflow.
3. اختر `mobile` أو `tv` أو `both`.
4. شغّل وانتظر اكتمال الاختبارات والبناء والنشر.
5. عند اختيار `both` تُحدد المصفوفة لتعمل وظيفة بناء واحدة في كل مرة، لتقليل التوازي على موارد GitHub.

يمكن استخدام Tags أيضًا: `mobile-v2.3.3` أو `tv-v2.3.3`.

## GitHub Secrets المطلوبة
`ANDROID_KEYSTORE_BASE64`, `ANDROID_KEYSTORE_PASSWORD`, `ANDROID_KEY_ALIAS`, `ANDROID_KEY_PASSWORD`, `RELEASES_TOKEN`.

يحتاج `RELEASES_TOKEN` إلى صلاحية Contents: Read and write على مستودع `tvexp-releases` وMetadata: Read-only.

## التوقيع
يجب أن تكون Keystore هي نفسها التي وقّعت النسخ المثبتة حاليًا. لا تنشئ مفتاحًا جديدًا ولا ترفع ملف JKS إلى المستودع. احتفظ بنسخة احتياطية مشفرة خارج المستودع.

## قنوات التحديث
- الهاتف يقرأ `latest-mobile.json` ويقبل فقط `com.tvexp.iptv`.
- الشاشات تقرأ `latest-tv.json` وتقبل فقط `com.tvexp.iptv.tv`.
- يجب أن يكون `versionCode` المنشور أكبر من رقم الإصدار المثبت حتى يقبل التطبيق التحديث.
- يتم اشتقاق `versionCode` و`versionName` من `pubspec.yaml` لضمان تطابق التطبيق مع ملف البيان.
