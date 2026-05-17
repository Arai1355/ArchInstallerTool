# أداة ArchInstallerTool

English documentation: [README.md](README.md)

`ArchInstallerTool` هي أداة تثبيت تفاعلية مكتوبة بـ Bash لتثبيت Arch Linux من بيئة Arch Live الرسمية. تساعدك الأداة في إعداد الشبكة، اختيار المرايا، اختيار نوع التثبيت، اختيار سطح المكتب، تقسيم القرص، تثبيت الحزم، إعداد محمل الإقلاع، وإنشاء سكربت ما بعد التثبيت.

> **تحذير مهم:** هذه الأداة تستطيع مسح القرص بالكامل. اقرأ التحذيرات جيدًا، وتأكد من القرص الهدف قبل المتابعة.

## المميزات

- أنماط تثبيت تفاعلية: minimal, desktop, server, developer, gaming, custom.
- مساعد اتصال Wi-Fi باستخدام `nmcli` أو `iwctl`.
- تحديث مرايا pacman بشكل اختياري مع أخذ نسخة احتياطية واسترجاعها عند الفشل.
- اختيار kernel: `linux`, `linux-lts`, `linux-zen`, `linux-hardened`.
- تثبيت حزمة `linux-headers` المناسبة للـ kernel المختار.
- اختيار سطح المكتب: KDE, GNOME, XFCE, i3, Sway, Hyprland أو بدون سطح مكتب.
- اختيار نظام الملفات: `ext4`, `btrfs`, `xfs`.
- دعم Btrfs subvolumes: `@`, `@home`, `@snapshots`.
- تقسيم تلقائي بسيط وتقسيم LVM.
- كشف GPU واختيار تعريفات Intel, AMD, NVIDIA Open DKMS, Virtual Machine.
- دعم locale إنجليزي وعربي، ومنها `ar_IQ.UTF-8`.
- التحقق من صحة اسم المستخدم واسم الجهاز.
- فحص الحزم قبل تهيئة القرص.
- رسائل فشل أوضح: المرحلة، الأمر الفاشل، رقم السطر، وآخر أسطر من ملف السجل.
- إنشاء `post_install.sh` لحزم AUR والإعدادات الإضافية.

## المتطلبات

شغّل السكربت من بيئة Arch Linux Live الرسمية.

يفضل توفر:

- جهاز يدعم UEFI إذا كنت تريد تثبيت UEFI.
- اتصال إنترنت يعمل.
- صلاحيات root داخل Arch ISO.
- نسخة احتياطية من ملفاتك المهمة.
- معرفة أساسية بالأقراص والأقسام في Linux.

يعتمد السكربت على أدوات موجودة عادة في Arch ISO مثل:

```bash
pacstrap arch-chroot genfstab pacman parted lsblk systemctl
```

وبعض الخيارات تحتاج أدوات إضافية مثل:

```bash
mkfs.btrfs mkfs.xfs lvm2 reflector nmcli iwctl
```

## التشغيل السريع

داخل Arch Live:

```bash
chmod +x ArchInstallerTool.sh
./ArchInstallerTool.sh
```

إذا فشل السكربت، اقرأ رسالة الخطأ وراجع ملف السجل الذي يطبعه السكربت.

## الطريقة الأولى: تحميل السكربت من حاسوب آخر عبر HTTP

على الحاسوب الذي يحتوي السكربت:

```bash
cd /path/to/script-folder
python3 -m http.server 8000 --bind 0.0.0.0
```

لمعرفة IP هذا الحاسوب:

```bash
ip -4 addr
```

على جهاز Arch Live الهدف:

```bash
curl -fL http://IP_ADDRESS:8000/ArchInstallerTool.sh -o ArchInstallerTool.sh
chmod +x ArchInstallerTool.sh
./ArchInstallerTool.sh
```

مثال:

```bash
curl -fL http://192.168.1.207:8000/ArchInstallerTool.sh -o ArchInstallerTool.sh
chmod +x ArchInstallerTool.sh
./ArchInstallerTool.sh
```

إذا فشل التحميل، اختبر الاتصال:

```bash
ping -c 3 IP_ADDRESS
curl -I http://IP_ADDRESS:8000/
```

## الطريقة الثانية: النسخ من فلاش USB

انسخ السكربت إلى فلاش USB من جهاز آخر، ثم داخل Arch Live:

```bash
lsblk
mkdir -p /mnt/usb
mount /dev/sdX1 /mnt/usb
cp /mnt/usb/ArchInstallerTool.sh .
chmod +x ArchInstallerTool.sh
./ArchInstallerTool.sh
```

استبدل `/dev/sdX1` باسم قسم الفلاش الحقيقي كما يظهر في `lsblk`.

## الطريقة الثالثة: النقل باستخدام SCP عبر SSH

على جهاز Arch Live الهدف، ضع كلمة مرور مؤقتة للـ root وشغّل SSH:

```bash
passwd
systemctl start sshd
ip -4 addr
```

من حاسوبك الأساسي:

```bash
scp ArchInstallerTool.sh root@TARGET_IP:/root/ArchInstallerTool.sh
```

ثم على جهاز Arch Live:

```bash
chmod +x /root/ArchInstallerTool.sh
/root/ArchInstallerTool.sh
```

## الطريقة الرابعة: التحميل من GitHub

بعد نشر المستودع على GitHub يمكنك تحميل الملف الخام:

```bash
curl -fL https://raw.githubusercontent.com/Arai1355/ArchInstallerTool/main/ArchInstallerTool.sh -o ArchInstallerTool.sh
chmod +x ArchInstallerTool.sh
./ArchInstallerTool.sh
```

صفحة المستودع: <https://github.com/Arai1355/ArchInstallerTool>

## الطريقة الخامسة: تحميل المستودع باستخدام Git

هذه الطريقة مناسبة إذا كنت تريد تحميل المستودع كاملًا، بما في ذلك ملفات README وأي ملفات أخرى مستقبلًا.

أولًا، اتصل بالشبكة من بيئة Arch Live.

إذا كنت تستخدم كابل Ethernet، غالبًا سيعمل الاتصال تلقائيًا. اختبره:

```bash
ping -c 3 archlinux.org
```

إذا كنت تستخدم Wi-Fi، استخدم `iwctl`:

```bash
iwctl
```

داخل واجهة `iwctl`:

```text
device list
station wlan0 scan
station wlan0 get-networks
station wlan0 connect WIFI_NAME
exit
```

استبدل `wlan0` باسم كرت الواي فاي الحقيقي، واستبدل `WIFI_NAME` باسم شبكتك. إذا كانت الشبكة تحتاج كلمة مرور، سيطلبها `iwctl`.

اختبر الاتصال:

```bash
ping -c 3 archlinux.org
```

إذا لم يكن `git` مثبتًا داخل Arch Live، ثبّته:

```bash
pacman -Sy git
```

حمّل المستودع:

```bash
git clone https://github.com/Arai1355/ArchInstallerTool.git
cd ArchInstallerTool
chmod +x ArchInstallerTool.sh
./ArchInstallerTool.sh
```

ويمكنك تحميل فرع معين:

```bash
git clone -b BRANCH_NAME https://github.com/Arai1355/ArchInstallerTool.git
```

## تحقق من السكربت قبل تشغيله

لا تشغل أي سكربت بصلاحيات root قبل مراجعته:

```bash
less ArchInstallerTool.sh
```

افحص صياغة Bash:

```bash
bash -n ArchInstallerTool.sh
```

إذا كان هناك checksum موثوق منشور، قارنه:

```bash
sha256sum ArchInstallerTool.sh
```

لا تشغل السكربت إذا كان checksum لا يطابق القيمة الموثوقة.

## تحذيرات مهمة

- السكربت يستطيع حذف كل البيانات من القرص المختار.
- لا تختر فلاش التثبيت كقرص هدف.
- افحص الأقراص دائمًا قبل المتابعة:

```bash
lsblk -f
fdisk -l
```

- التقسيم التلقائي يقوم بتهيئة القرص المحدد.
- التقسيم اليدوي يحتاج انتباهًا؛ كتابة قسم خاطئ قد يمسح بياناتك.
- LVM وBtrfs ومحمل الإقلاع وتعريفات GPU قد تؤثر على إقلاع النظام.
- إذا كنت تستخدم لابتوب، وصّل الشاحن قبل التثبيت.
- لا تقاطع عمليات `pacstrap` أو التهيئة أو تثبيت GRUB أو `mkinitcpio`.

## تحذير أمني

لا تشغل سكربتات تثبيت من مصادر مجهولة بدون مراجعة.

نسخة معدلة أو خبيثة من هذا السكربت يمكن أن:

- تمسح أقراصًا غير متوقعة.
- تحمّل حزمًا خبيثة.
- تضيف مفاتيح SSH غير مصرح بها.
- تغير كلمات المرور أو المستخدمين.
- تثبت أدوات وصول خلفي أو تحكم عن بعد.
- تسرّب بيانات خاصة إذا كان هناك اتصال بالشبكة.

قبل التشغيل:

```bash
less ArchInstallerTool.sh
bash -n ArchInstallerTool.sh
sha256sum ArchInstallerTool.sh
```

يفضل التحميل من مستودعك الرسمي، أو من release موثوق، أو من رابط له checksum معروف.

## إخلاء المسؤولية القانوني

هذا المشروع مقدم كما هو، بدون أي ضمان.

المؤلف غير مسؤول عن:

- فقدان البيانات.
- فشل التثبيت.
- مشاكل الإقلاع.
- أخطاء إعداد العتاد أو firmware.
- الحوادث الأمنية الناتجة عن نسخ معدلة أو خبيثة.
- أي ضرر يحدث بسبب تشغيل السكربت بدون فهم ما يفعله.

أنت المسؤول عن مراجعة الكود، أخذ نسخة احتياطية، اختيار القرص الصحيح، والتحقق من مصدر أي سكربت تشغله بصلاحيات root.

## نصائح الاستعادة عند الفشل

إذا حدث فشل، افحص mount والأقراص:

```bash
findmnt /mnt
lsblk -f
```

لفك التركيب قبل إعادة المحاولة:

```bash
umount -R /mnt 2>/dev/null
swapoff -a
```

راجع ملف السجل الذي يطبعه السكربت، وغالبًا يكون داخل:

```bash
/tmp/arch_installer_*/install.log
```

## سير عمل مقترح

1. أقلع من Arch Linux ISO الرسمي.
2. اتصل بالإنترنت.
3. انقل أو حمّل `ArchInstallerTool.sh`.
4. راجع السكربت وتحقق منه.
5. نفّذ `bash -n ArchInstallerTool.sh`.
6. شغّل أداة التثبيت.
7. اختر القرص الهدف بحذر.
8. راجع ملخص التثبيت قبل كتابة `yes`.
9. أعد التشغيل فقط بعد اكتمال التثبيت بنجاح.

## ملاحظات

- Secure Boot وتشفير القرص الكامل ميزات متقدمة ويجب تنفيذها بحذر.
- للأنظمة المهمة أو الإنتاجية، راجع إعدادات النظام ومحمل الإقلاع قبل الاعتماد على التثبيت.
- احتفظ دائمًا بفلاش إنقاذ أو Arch ISO جاهز.
