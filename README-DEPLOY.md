# BONAFIDE Portal + JS PACS (veb-versiya)

Bu papka — Cloudflare Pages'ga joylash uchun tayyor statik sayt:

```
JS_PACS_web/
├── index.html        ← Portal (hub): ikkita karta — 재고 관리 va JS PACS
└── jspacs/           ← JS PACS ko'ruvchi (brauzerda mustaqil ishlaydi)
```

## Cloudflare Pages'ga joylash (eng oson yo'l — drag & drop)

1. [dash.cloudflare.com](https://dash.cloudflare.com) ga kiring (inventar ilovangiz turgan akkaunt).
2. **Workers & Pages → Create → Pages → Upload assets** ni tanlang.
3. Loyiha nomi kiriting, masalan: `bonafidekcs-portal`.
4. Shu papkaning **ichidagi hamma narsani** (index.html + jspacs papkasi) sudrab tashlang.
5. **Deploy** bosing → `https://bonafidekcs-portal.pages.dev` tayyor.

CLI orqali xohlasangiz:
```
npx wrangler pages deploy "C:\Users\user\Desktop\JS_PACS_web" --project-name=bonafidekcs-portal
```

## Ishlash tartibi

- Portal ochiladi → xodim **재고 관리** yoki **JS PACS** ni tanlaydi.
- JS PACS sarlavhasida **🏠 포털** (portalga qaytish) va **📦 재고 관리** (inventar ilovasi) tugmalari bor.
- JS PACS brauzerda (Chrome/Edge) **⚙ Setting** orqali DICOM papkani tanlab ishlaydi —
  klinika kompyuterida tarmoq papkasini (`\\Desktop-uebgim1\sts`) tanlash mumkin.

## Muhim cheklovlar (veb-versiyada)

| Imkoniyat | Desktop (WPF) | Veb (brauzer) |
|---|---|---|
| Worklist, preview, qidiruv | ✅ | ✅ |
| Umurtqa annotatsiya, Cobb, o'lchovlar | ✅ | ✅ |
| JS VIEWER (yonma-yon solishtirish) | ✅ | ✅ |
| Annotatsiya saqlash (.jsha.json) | ✅ | ✅ (papkaga yozish ruxsati bilan) |
| EMR (SQL Server) ma'lumotlari | ✅ | ❌ |
| Claude AI hisobot (판독) | ✅ | ❌ |
| Yangi surat kelganda avtomatik yangilanish | ✅ | ❌ (↻ tugmasi bilan qo'lda) |

Desktop dastur (`JS_PACS_배포\HospitalReport.App.exe`) o'zgarmagan — ikkalasi parallel ishlayveradi.

## Keyingi qadam (ixtiyoriy): yagona login

JS PACS aslida inventar ilovasi bilan **bitta Firebase akkaunt tizimiga** (uiwon-inventory)
ulangan bo'lgan — hozirgi nusxada login o'chirilgan (`js/02-auth-stub.js`).
Xodimlar ikkala tizimga bitta parol bilan kirsin desangiz, `02-auth-stub.js` o'rniga
Firebase login kodini qaytarish kerak — buning uchun Firebase loyiha sozlamalari
(apiKey, authDomain va h.k.) kerak bo'ladi.
