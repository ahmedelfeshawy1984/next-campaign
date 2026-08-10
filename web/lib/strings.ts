// كل نصوص الموقع في مكان واحد.
//
// No next-intl in v1, mirroring the sibling project's "عربي بس، من غير ARB"
// decision. The DATA is bilingual from day one (name_ar / name_en on every
// table) because retrofitting that means re-entering the catalogue; the CHROME
// is not, because retrofitting that is a sibling file plus a [locale] segment.
//
// Digits stay Latin inside Arabic — see toLatinDigits in lib/arabic.js and the
// reasoning there.

export const S = {
  brand: 'نكست كامباين',
  tagline: 'مطبوعات وهدايا دعائية تحمل اسمك',

  nav: {
    home: 'الرئيسية',
    corporate: 'هدايا الشركات',
    gifts: 'هدايا الأفراد',
    printing: 'طرق الطباعة',
    about: 'من إحنا',
    contact: 'اتصل بنا',
    search: 'دوّر على منتج',
  },

  home: {
    heroTitle: 'اسمك على حاجة بتتستخدم كل يوم',
    heroBody:
      'مطبوعات وهدايا دعائية للشركات، وهدايا شخصية باسم صاحبها. اختار المنتج، حدد الطباعة، وشوف التكلفة قبل ما تكلّم حد.',
    corporateCta: 'ابدأ بهدايا الشركات',
    giftsCta: 'هدية لشخص واحد',
    categoriesTitle: 'اتصفّح بالفئة',
    occasionsTitle: 'بالمناسبة',
    featuredTitle: 'الأكثر طلباً',
    howTitle: 'بتشتغل إزاي',
    steps: [
      { t: 'اختار المنتج', b: 'اتصفّح الكتالوج وشوف الخامة والمقاس وسعر القطعة عند كل كمية.' },
      { t: 'خصّص طباعتك', b: 'ارفع اللوجو أو اكتب الكلمة، حدد مكان الطباعة وعدد الألوان.' },
      { t: 'شوف التكلفة', b: 'الإجمالي بيتحرك قدامك مع الكمية — من غير ما تستنى عرض سعر.' },
      { t: 'ابعت الطلب', b: 'بنراجع الملف ونبعتلك معاينة نهائية قبل التنفيذ.' },
    ],
  },

  corporate: {
    title: 'هدايا الشركات',
    body:
      'كل حاجة هنا بتتطبع بلوجو شركتك. الأسعار للقطعة وبتنزل مع الكمية، ورسوم الكليشيه بتتحسب مرة واحدة.',
  },

  gifts: {
    title: 'هدايا الأفراد',
    body: 'قطعة واحدة، باسمها أو بكلمة انت اللي تكتبها. بنسلّمها في علبة هدية.',
  },

  product: {
    from: 'من',
    perPiece: 'للقطعة',
    atMoq: 'عند الحد الأدنى',
    dropsTo: 'وبينزل لـ',
    moq: 'الحد الأدنى للطلب',
    piece: 'قطعة',
    leadTime: 'مدة التنفيذ',
    days: 'يوم عمل',
    specs: 'المواصفات',
    allSpecs: 'كل المواصفات',
    printMethods: 'طرق الطباعة المتاحة',
    printPositions: 'أماكن الطباعة',
    options: 'الخيارات',
    priceLadder: 'السعر حسب الكمية',
    quantity: 'الكمية',
    unitPrice: 'سعر القطعة',
    save: 'توفير',
    unavailable: 'غير متاح حالياً',
    outOfStock: 'خلص',
    relatedTitle: 'منتجات قريبة',
    setupFee: 'رسوم الكليشيه',
    setupFeeOnce: 'مرة واحدة',
    freeOver: 'مجاني فوق',
    needsVector: 'محتاج ملف vector',
    askForQuote: 'اطلب عرض سعر',
  },

  catalog: {
    products: 'منتج',
    noResults: 'مفيش نتايج',
    noResultsBody: 'جرّب تشيل بعض الفلاتر أو تدوّر بكلمة تانية.',
    clearFilters: 'شيل الفلاتر',
    sort: 'الترتيب',
    sortFeatured: 'المختار',
    sortCheap: 'الأرخص',
    sortExpensive: 'الأغلى',
    sortNewest: 'الأحدث',
    sortName: 'الاسم',
    filterAudience: 'لمين',
    audienceCorporate: 'شركات',
    audienceIndividual: 'أفراد',
    filterMethod: 'طريقة الطباعة',
    filterOccasion: 'المناسبة',
    filterCategory: 'الفئة',
    all: 'الكل',
    searchPlaceholder: 'اسم المنتج أو الكود',
  },

  common: {
    currency: 'ج.م',
    vatNote: 'الأسعار غير شاملة ضريبة القيمة المضافة',
    vatNoteIncluded: 'الأسعار شاملة ضريبة القيمة المضافة',
    whatsapp: 'كلمنا واتساب',
    backHome: 'ارجع للرئيسية',
    notFound: 'الصفحة مش موجودة',
    notFoundBody: 'الرابط اتغير أو المنتج اتشال. جرّب تدوّر من الكتالوج.',
  },

  setup: {
    title: 'الموقع محتاج إعداد',
    body:
      'مفيش مفاتيح Supabase. انسخ web/.env.local.example لـ web/.env.local وحط فيه رابط المشروع والمفتاح العام (anon).',
    step1: '١. افتح لوحة Supabase → Project Settings → API',
    step2: '٢. انسخ Project URL و anon public key',
    step3: '٣. حطهم في web/.env.local وأعد تشغيل الخادم',
  },
} as const;
