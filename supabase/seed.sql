-- ============================================================================
--  بيانات البداية — نكست كامباين
--
--  Re-runnable. Every insert carries an `on conflict do nothing`, so pasting
--  this a second time changes nothing.
--
--  The products here are REAL shapes with plausible Egyptian pricing, not
--  lorem ipsum — a catalogue you cannot browse honestly is a catalogue you
--  cannot judge. Replace the prices with yours before going live; the ones
--  marked موديل تجريبي in short_pitch_ar are meant to be deleted.
--
--  Note the order at the bottom: products are inserted UNPUBLISHED, then
--  published only after their tiers, methods and positions exist. That is the
--  publish gate in 20260810100003_pricing.sql doing its job, and the seed is
--  the first thing that proves it works.
-- ============================================================================

-- ------------------------------------------------------------- الفئات ------

insert into public.categories (slug, name_ar, name_en, blurb_ar, icon, sort_order) values
  ('mugs',       'مجات وأكواب',        'Mugs',        'سيراميك وسحري وترمس — أكتر هدية بتفضل على المكتب',      'coffee',   10),
  ('bottles',    'زجاجات وترمس',       'Bottles',     'ستانلس وتريتان، للجيم والمكتب والرحلات',                 'bottle',   20),
  ('pens',       'أقلام',              'Pens',        'من القلم الدعائي للطقم الفاخر بعلبته',                    'pen',      30),
  ('notebooks',  'نوتات وأجندات',      'Notebooks',   'أجندات جلد ونوتات سلك بمقاسات المكتب',                   'notebook', 40),
  ('apparel',    'ملابس',              'Apparel',     'تيشرتات وبولو وكابات بالتطريز أو الطباعة',                'shirt',    50),
  ('tech',       'هدايا تكنولوجية',    'Tech gifts',  'فلاشات وباور بانك وماوس باد',                            'usb',      60),
  ('bags',       'شنط',                'Bags',        'توتال قماش وشنط لابتوب',                                  'bag',      70),
  ('desk',       'مستلزمات مكتب',      'Desk',        'حوامل ومنظمات وأطقم مكتب',                                'desk',     80),
  ('keychains',  'ميداليات',           'Keychains',   'معدن وجلد وأكريليك',                                      'key',      90),
  ('clocks',     'ساعات حائط',         'Wall clocks', 'ساعات بلوجو الشركة للمقر والفروع',                        'clock',   100),
  ('giftbox',    'علب هدايا',          'Gift boxes',  'بوكسات مجمّعة للمناسبات',                                 'gift',    110),
  ('printing',   'مطبوعات',            'Printing',    'كروت وبروشور وفواتير وأكياس',                             'print',   120)
on conflict (slug) do nothing;

-- ---------------------------------------------------------- المناسبات ------

insert into public.occasions (slug, name_ar, name_en, blurb_ar, sort_order) values
  ('ramadan',     'رمضان',            'Ramadan',      'بوكسات وهدايا رمضان للموظفين والعملاء', 10),
  ('eid',         'العيد',            'Eid',          'معايدات وهدايا العيد',                  20),
  ('new-year',    'رأس السنة',        'New Year',     'أجندات وهدايا بداية السنة',             30),
  ('birthday',    'عيد ميلاد',        'Birthday',     'هدية باسم صاحبها',                      40),
  ('graduation',  'تخرج',             'Graduation',   'هدايا التخرج والدفعات',                 50),
  ('opening',     'افتتاح',           'Opening',      'هدايا افتتاح الفروع',                   60),
  ('conference',  'مؤتمرات ومعارض',   'Conferences',  'حقائب ونوتات وأقلام للزوار',            70),
  ('love',        'كلمة حب',          'Love note',    'هدية عليها كلمة مش موجودة عند حد تاني',  80),
  ('mothers-day', 'عيد الأم',         'Mother''s Day','هدايا عيد الأم',                         90)
on conflict (slug) do nothing;

-- ------------------------------------------------------ طرق الطباعة ------

insert into public.print_methods
  (code, name_ar, name_en, blurb_ar, color_model, needs_vector, default_setup_fee, default_max_colors, sort_order) values
  ('screen','سلك سكرين','Screen printing',
   'الأقوى والأرخص في الكميات الكبيرة. بتدفع كليشيه لكل لون مرة واحدة.',
   'spot', true, 150, 4, 10),
  ('pad','باد / تامبو','Pad printing',
   'للأسطح الصغيرة والمنحنية زي جسم القلم وودن الكوباية.',
   'spot', true, 120, 2, 20),
  ('laser','حفر ليزر','Laser engraving',
   'بيحفر في الخامة نفسها — مالوش لون، وعمره ما بيمسح.',
   'single_tone', true, 0, null, 30),
  ('embroidery','تطريز','Embroidery',
   'للملابس والكابات والشنط. رسم الديچيتايزنج مرة واحدة على التصميم.',
   'thread', true, 250, 8, 40),
  ('sublimation','سبليميشن','Sublimation',
   'ألوان كاملة على السيراميك والبوليستر. سعر واحد مهما كان عدد الألوان.',
   'full_color', false, 0, null, 50),
  ('uv','طباعة UV','UV printing',
   'ألوان كاملة على أي سطح تقريباً، بحبر بيجف بالأشعة.',
   'full_color', false, 100, null, 60),
  ('dtf','طباعة DTF','DTF',
   'ألوان كاملة على الملابس القطن والبوليستر، من غير حد أدنى للألوان.',
   'full_color', false, 0, null, 70),
  ('transfer','ترانسفير','Heat transfer',
   'للكميات الصغيرة والتصميمات المتغيرة.',
   'full_color', false, 0, null, 80),
  ('digital','طباعة ديچيتال','Digital printing',
   'للمطبوعات الورقية بكميات صغيرة ومتوسطة.',
   'full_color', false, 0, null, 90),
  ('foil','فويل ذهبي/فضي','Foil stamping',
   'ختم معدني لامع — للكروت والعلب الفاخرة.',
   'single_tone', true, 200, null, 100),
  ('emboss','بارز / إمبوس','Embossing',
   'نقش بارز من غير حبر. بيتحس بالإيد قبل ما يتشاف.',
   'single_tone', true, 350, null, 110)
on conflict (code) do nothing;

-- ------------------------------------------------------------ الخطوط ------

insert into public.fonts (key, name_ar, name_en, css_family, script, is_display, sort_order) values
  ('cairo',      'القاهرة',    'Cairo',      'Cairo',       'both',   false, 10),
  ('tajawal',    'تجوّل',      'Tajawal',    'Tajawal',     'both',   false, 20),
  ('almarai',    'المراعي',    'Almarai',    'Almarai',     'arabic', false, 30),
  ('amiri',      'أميري',      'Amiri',      'Amiri',       'arabic', true,  40),
  ('reem-kufi',  'ريم كوفي',   'Reem Kufi',  'Reem Kufi',   'arabic', true,  50),
  ('aref-ruqaa', 'عارف رقعة',  'Aref Ruqaa', 'Aref Ruqaa',  'arabic', true,  60),
  ('lemonada',   'ليمونادة',   'Lemonada',   'Lemonada',    'arabic', true,  70),
  ('changa',     'شنجة',       'Changa',     'Changa',      'arabic', true,  80),
  ('montserrat', 'مونتسيرات',  'Montserrat', 'Montserrat',  'latin',  false, 90)
on conflict (key) do nothing;

-- ------------------------------------------------- كتالوج المواصفات ------

insert into public.spec_defs
  (key, label_ar, unit_ar, kind, higher_is_better, is_filterable, show_in_card, is_key, section_ar, sort_order) values
  ('material_ar',     'الخامة',            null,   'text',   null,  false, true,  true,  'الأساسي',   10),
  ('dimensions_ar',   'المقاس',            null,   'text',   null,  false, false, true,  'الأساسي',   20),
  ('weight_g',        'الوزن',             'جرام', 'number', null,  false, false, false, 'الأساسي',   30),
  ('capacity_ml',     'السعة',             'مل',   'number', true,  true,  true,  true,  'الأساسي',   40),
  ('paper_gsm',       'جراماج الورق',      'جم/م²','number', true,  true,  false, true,  'الورق',     50),
  ('page_count',      'عدد الصفحات',       'صفحة', 'number', true,  true,  true,  true,  'الورق',     60),
  ('usb_capacity_gb', 'سعة الفلاشة',       'جيجا', 'number', true,  true,  true,  true,  'التقنية',   70),
  ('battery_mah',     'سعة البطارية',      'mAh',  'number', true,  true,  true,  true,  'التقنية',   80),
  ('pack_size',       'عدد القطع بالعبوة', 'قطعة', 'number', null,  false, false, false, 'التغليف',   90),
  ('warranty_months', 'الضمان',            'شهر',  'number', true,  false, false, false, 'الضمان',   100),
  ('origin_ar',       'بلد المنشأ',        null,   'text',   null,  true,  false, false, 'الأساسي',  110),
  ('is_eco',          'خامة صديقة للبيئة', null,   'bool',   true,  true,  false, false, 'الأساسي',  120)
on conflict (key) do nothing;

-- Scoping. Remember the convention: NO rows here = applies to every category.
-- So material_ar, dimensions_ar, weight_g, origin_ar and is_eco are absent on
-- purpose — they are asked about every product.
insert into public.spec_def_categories (spec_key, category_id)
select v.spec_key, c.id
  from (values
    ('capacity_ml','mugs'), ('capacity_ml','bottles'),
    ('paper_gsm','notebooks'), ('paper_gsm','printing'),
    ('page_count','notebooks'),
    ('usb_capacity_gb','tech'),
    ('battery_mah','tech'),
    ('warranty_months','tech'), ('warranty_months','clocks'),
    ('pack_size','pens'), ('pack_size','printing'), ('pack_size','keychains')
  ) as v(spec_key, cat_slug)
  join public.categories c on c.slug = v.cat_slug
on conflict do nothing;

-- ---------------------------------------------------------- المنتجات ------
--
-- Inserted UNPUBLISHED. Published at the very bottom, once the tiers, methods
-- and positions each product needs actually exist.

insert into public.products (
  slug, category_id, sku, name_ar, name_en, short_pitch_ar, description_ar,
  for_corporate, for_individual, moq, max_positions, max_text_lines,
  allows_logo, allows_text, lead_days_min, lead_days_max,
  material_ar, dimensions_ar, weight_g, capacity_ml, paper_gsm, page_count,
  usb_capacity_gb, battery_mah, pack_size, warranty_months, origin_ar, is_eco,
  sort_order
)
select
  v.slug, c.id, v.sku, v.name_ar, v.name_en, v.pitch, v.descr,
  v.corp::boolean, v.indiv::boolean, v.moq::int, v.max_pos::int, v.max_lines::int,
  v.logo::boolean, v.txt::boolean, v.lead_min::int, v.lead_max::int,
  v.material, v.dims, v.weight::int, v.capacity::int, v.gsm::int, v.pages::int,
  v.usb::int, v.mah::int, v.pack::int, v.warranty::int, v.origin, v.eco::boolean,
  v.sort::int
from (values
  -- ---- مجات وأكواب ----
  ('mug-ceramic-white','mugs','NC-MUG-01','مج سيراميك أبيض','White ceramic mug',
   'أشهر هدية دعائية على الإطلاق — وأرخص تكلفة للقطعة في الكميات الكبيرة.',
   'مج سيراميك درجة أولى، سعة ٣٣٠ مل، يتحمل غسالة الأطباق والميكروويف. الطباعة سبليميشن بألوان كاملة على وش واحد أو الاتنين. أنسب اختيار لهدايا المؤتمرات وأطقم الترحيب بالموظفين الجدد.',
   true,false,36,2,2,true,true,3,5,'سيراميك','9.5 × 8 سم',320,330,null,null,null,null,null,null,'الصين',false,10),

  ('mug-magic-color','mugs','NC-MUG-02','مج سحري بيتغير لونه','Magic colour-change mug',
   'أسود وهو فاضي، وبيكشف التصميم لما تصب فيه حاجة سخنة.',
   'مج سحري بطبقة حرارية: التصميم بيظهر عند ٤٥ درجة وبيختفي لما يبرد. بيعمل انطباع قوي في هدايا العملاء وبيتصوّر كتير على السوشيال. الطباعة سبليميشن فقط.',
   true,true,24,1,2,true,true,4,7,'سيراميك بطبقة حرارية','9.5 × 8 سم',340,330,null,null,null,null,null,null,'الصين',false,20),

  ('mug-travel-steel','mugs','NC-MUG-03','ترمس سفر ستانلس','Steel travel mug',
   'بيحافظ على السخونة ٦ ساعات، وبيتحفر بالليزر فيفضل مدى الحياة.',
   'ترمس ستانلس ٣٠٤ مزدوج الجدار بغطاء محكم، سعة ٤٥٠ مل. الحفر بالليزر بيدي شكل راقي ومش بيمسح مع الغسيل. مناسب لهدايا الإدارة العليا.',
   true,false,25,1,2,true,true,5,8,'ستانلس ستيل 304','19 × 7 سم',290,450,null,null,null,null,null,null,'الصين',false,30),

  ('mug-name-gift','mugs','NC-MUG-04','مج باسمك — هدية','Personalised name mug',
   'قطعة واحدة، باسمها أو بكلمة انت اللي تكتبها.',
   'نفس المج السيراميك، بس معمول لهدية شخصية: اكتب الاسم أو كلمة الحب أو المعايدة، اختار الخط، وشوف الشكل قبل ما تطلب. بنسلّمه في علبة هدية.',
   false,true,1,2,3,false,true,2,4,'سيراميك','9.5 × 8 سم',320,330,null,null,null,null,null,null,'الصين',false,40),

  -- ---- زجاجات ----
  ('bottle-steel-750','bottles','NC-BTL-01','زجاجة ستانلس ٧٥٠ مل','Steel bottle 750ml',
   'للجيم والمكتب — والحفر عليها بيعيش أطول من الوظيفة.',
   'زجاجة ستانلس مزدوجة الجدار بغطاء رياضي، ٧٥٠ مل. بتحافظ على البرودة ١٢ ساعة. الحفر بالليزر على جسم الزجاجة.',
   true,false,25,1,2,true,true,5,8,'ستانلس ستيل 304','26 × 7 سم',390,750,null,null,null,null,null,null,'الصين',false,50),

  ('bottle-tritan-700','bottles','NC-BTL-02','زجاجة تريتان شفافة','Tritan bottle 700ml',
   'خفيفة وشفافة، والطباعة عليها بتبان من بعيد.',
   'زجاجة تريتان خالية من BPA، ٧٠٠ مل، بغطاء لولبي ومقبض. أنسب للفعاليات الرياضية وهدايا الطلبة. طباعة سلك سكرين أو UV.',
   true,false,50,1,2,true,true,4,7,'تريتان','24 × 6.5 سم',120,700,null,null,null,null,null,null,'الصين',true,60),

  -- ---- أقلام ----
  ('pen-metal-classic','pens','NC-PEN-01','قلم معدن كلاسيك','Classic metal pen',
   'وزنه في الإيد هو اللي بيفرق — والحفر بالليزر بيبان فضي على الأسود.',
   'قلم جاف معدني بآلية ضغط، حبر أزرق ألماني، جسم مطلي. الحفر بالليزر بيكشف لون المعدن تحت الطلاء. بيتسلّم في علبة كرتون أو مخمل حسب الطلب.',
   true,false,100,1,1,true,true,4,7,'معدن مطلي','14 سم',28,null,null,null,null,null,1,null,'الصين',false,70),

  ('pen-plastic-promo','pens','NC-PEN-02','قلم بلاستيك دعائي','Promo plastic pen',
   'أرخص حاجة بتوصّل اسمك لأكبر عدد ناس.',
   'قلم بلاستيك خفيف بحبر أزرق، متاح بألوان جسم متعددة. طباعة باد على الجسم أو الكليب. الاختيار الأول لتوزيعات المعارض.',
   true,false,250,2,1,true,true,3,6,'بلاستيك ABS','14 سم',9,null,null,null,null,null,1,null,'مصر',false,80),

  ('pen-set-gift','pens','NC-PEN-03','طقم قلم فاخر بعلبة','Gift pen set',
   'قلم جاف وحبر سائل في علبة مخمل — هدية الاجتماع المهم.',
   'طقم من قطعتين (جاف + حبر سائل) في علبة مخمل بقفل مغناطيسي. الحفر بالليزر على القلمين وعلى بلاكة العلبة.',
   true,true,25,2,2,true,true,6,10,'معدن + علبة مخمل','17 × 6 سم',180,null,null,null,null,null,2,null,'الصين',false,90),

  -- ---- نوتات ----
  ('notebook-a5-pu','notebooks','NC-NTB-01','أجندة A5 جلد صناعي','A5 PU notebook',
   'الأجندة اللي بتفضل على المكتب سنة كاملة وعليها لوجوك.',
   'أجندة مقاس A5 بغلاف جلد صناعي وحزام مطاطي وفاصل شريطي، ١٩٢ صفحة ورق ٨٠ جرام مسطّر. اللوجو بالحفر البارز أو الطباعة الحرارية على الغلاف.',
   true,false,50,1,2,true,true,6,10,'جلد صناعي','21 × 14.5 سم',420,null,80,192,null,null,null,null,'الصين',false,100),

  ('notebook-spiral-a4','notebooks','NC-NTB-02','نوتة سلك A4','A4 spiral notebook',
   'للتدريب والمؤتمرات — بتتفتح على الطربيزة وبتفضل مفتوحة.',
   'نوتة سلك معدني مقاس A4، ١٠٠ ورقة ٧٠ جرام، غلاف كوشيه مقوى. الغلاف بيتطبع بالكامل بألوان كاملة — مساحة إعلانية كاملة مش مجرد لوجو.',
   true,false,100,1,2,true,true,5,9,'كرتون كوشيه مقوى','29.7 × 21 سم',380,null,70,100,null,null,null,null,'مصر',true,110),

  -- ---- ملابس ----
  ('tshirt-cotton-round','apparel','NC-APP-01','تيشرت قطن نص كم','Cotton round-neck tee',
   'قطن ١٨٠ جرام — مش التيشرت اللي بيتكرمش بعد أول غسلة.',
   'تيشرت قطن ١٠٠٪ بوزن ١٨٠ جرام/م²، ياقة مستديرة مضلعة، مقاسات من S لـ 3XL. متاح بالطباعة DTF بألوان كاملة أو التطريز على الصدر.',
   true,false,24,3,2,true,true,5,9,'قطن 100% — 180 جم','حسب المقاس',180,null,null,null,null,null,null,null,'مصر',true,120),

  ('polo-pique','apparel','NC-APP-02','بولو بيكيه','Piqué polo shirt',
   'زي الفريق اللي بيقابل العميل.',
   'بولو بيكيه قطن/بوليستر بياقة وأزرار، مقاسات S–3XL، ألوان متعددة. التطريز على الصدر الشمال هو الاختيار المعتاد ليونيفورم الشركات.',
   true,false,24,2,1,true,true,7,12,'بيكيه 65% قطن','حسب المقاس',220,null,null,null,null,null,null,null,'مصر',false,130),

  ('cap-baseball','apparel','NC-APP-03','كاب بيسبول','Baseball cap',
   'التطريز عليه بيبان من مسافة عشرين متر.',
   'كاب ٦ قطع بحزام خلفي قابل للضبط، قطن مبروش. التطريز الأمامي حتى ٨ ألوان خيط.',
   true,false,50,2,1,true,false,6,10,'قطن مبروش','مقاس واحد',85,null,null,null,null,null,null,null,'الصين',false,140),

  -- ---- تكنولوجيا ----
  ('usb-metal-flip','tech','NC-TEC-01','فلاشة معدن قلاب','Metal flip USB',
   'هدية بتفضل في جيب العميل — وعليها لوجوك محفور.',
   'فلاشة USB 3.0 بجسم معدني قلاب، متاحة ١٦ / ٣٢ / ٦٤ جيجا. الحفر بالليزر على الجسم. بنقدر نحمّل عليها ملفاتك التعريفية قبل التسليم.',
   true,false,50,1,1,true,true,7,12,'معدن','6 × 2 سم',18,null,null,null,32,null,null,12,'الصين',false,150),

  ('powerbank-10000','tech','NC-TEC-02','باور بانك ١٠٠٠٠','Powerbank 10000mAh',
   'أغلى هدية بتُستخدم كل يوم.',
   'باور بانك ١٠٠٠٠ مللي أمبير بمدخل Type-C ومخرجين، شاشة نسبة شحن. الطباعة UV بألوان كاملة على الوش. بضمان سنة.',
   true,false,25,1,1,true,true,8,14,'ألومنيوم + ABS','14 × 6.8 × 1.5 سم',210,null,null,null,null,10000,null,12,'الصين',false,160),

  ('mousepad-fabric','tech','NC-TEC-03','ماوس باد قماش','Fabric mouse pad',
   'مساحة إعلانية بتقعد قدام العميل ٨ ساعات في اليوم.',
   'ماوس باد بسطح قماش وقاعدة مطاط مانعة للانزلاق، بحواف مخيطة. الطباعة سبليميشن على السطح بالكامل.',
   true,false,50,1,2,true,true,4,8,'قماش + مطاط','25 × 21 × 0.3 سم',95,null,null,null,null,null,null,null,'مصر',false,170),

  -- ---- شنط ----
  ('bag-canvas-tote','bags','NC-BAG-01','شنطة قماش توتال','Canvas tote bag',
   'بديل الكيس البلاستيك — وبتتشاف في الشارع.',
   'شنطة قماش كانفاس ١٢ أونصة بحمالات طويلة، ٣٨ × ٤٢ سم. طباعة سلك سكرين على وش واحد أو الاتنين. الاختيار المعتاد للمعارض والمبادرات البيئية.',
   true,false,50,2,2,true,true,5,9,'كانفاس 12 أونصة','38 × 42 سم',160,null,null,null,null,null,null,null,'مصر',true,180),

  ('backpack-laptop','bags','NC-BAG-02','شنطة ظهر لابتوب','Laptop backpack',
   'هدية الدفعة الجديدة أو المؤتمر الكبير.',
   'شنطة ظهر بجيب لابتوب ١٥.٦ بوصة مبطّن، قماش بوليستر مقاوم للماء، منفذ USB خارجي. التطريز أو الطباعة على الجيب الأمامي.',
   true,false,25,1,1,true,false,10,16,'بوليستر 600D','45 × 30 × 15 سم',680,null,null,null,null,null,null,6,'الصين',false,190),

  -- ---- ميداليات وساعات وبوكسات ----
  ('keychain-metal','keychains','NC-KEY-01','ميدالية معدن','Metal keychain',
   'أرخص حاجة بتفضل مع صاحبها سنين.',
   'ميدالية معدن مطلي بحلقة مفاتيح، وجهين قابلين للحفر. الحفر بالليزر أو الطباعة UV بألوان كاملة.',
   true,false,100,2,1,true,true,5,9,'معدن مطلي','4 × 3 سم',32,null,null,null,null,null,1,null,'الصين',false,200),

  ('keychain-name-gift','keychains','NC-KEY-02','ميدالية باسمك','Personalised keychain',
   'قطعة واحدة، محفور عليها الاسم اللي انت عايزه.',
   'ميدالية معدن بحفر ليزر للاسم أو التاريخ أو الإحداثيات. هدية سريعة وسعرها في المتناول، وبتتسلّم في علبة صغيرة.',
   false,true,1,2,2,false,true,2,4,'معدن مطلي','4 × 3 سم',32,null,null,null,null,null,1,null,'الصين',false,210),

  ('wallclock-round','clocks','NC-CLK-01','ساعة حائط دائرية','Round wall clock',
   'اللوجو في وش كل واحد داخل المقر.',
   'ساعة حائط قطر ٣٠ سم بحركة كوارتز صامتة وإطار بلاستيك. طباعة UV بألوان كاملة على القرص بالكامل.',
   true,false,25,1,2,true,true,7,12,'بلاستيك + زجاج','قطر 30 سم',520,null,null,null,null,null,null,12,'الصين',false,220),

  ('giftbox-ramadan','giftbox','NC-BOX-01','بوكس رمضان','Ramadan gift box',
   'مج وأجندة وقلم وتمر في علبة واحدة عليها اسم الشركة.',
   'بوكس مجمّع بيتظبط حسب طلبك: مج سيراميك + أجندة A5 + قلم معدن + علبة تمر، في علبة كرتون فاخرة بطباعة كاملة وشريطة. المحتويات قابلة للتغيير.',
   true,true,20,1,2,true,true,10,18,'كرتون مقوى','30 × 25 × 10 سم',1400,null,null,null,null,null,null,null,'مصر',false,230),

  -- ---- مطبوعات ----
  ('businesscards-500','printing','NC-PRN-01','كروت شخصية','Business cards',
   'أول حاجة بتتسلّم في إيد العميل.',
   'كروت شخصية ٣٥٠ جرام كوشيه بسلوفان مط أو لامع، طباعة وجهين بألوان كاملة. السعر بالعبوة (٥٠٠ كارت). متاح الفويل الذهبي والحفر البارز كإضافة.',
   true,false,1,2,3,true,true,3,5,'كوشيه 350 جرام','9 × 5.5 سم',null,null,350,null,null,null,500,null,'مصر',false,240)
) as v(slug, cat_slug, sku, name_ar, name_en, pitch, descr,
       corp, indiv, moq, max_pos, max_lines, logo, txt, lead_min, lead_max,
       material, dims, weight, capacity, gsm, pages, usb, mah, pack, warranty,
       origin, eco, sort)
join public.categories c on c.slug = v.cat_slug
on conflict (slug) do nothing;

-- ------------------------------------------------------ شرايح الأسعار ------
--
-- Non-increasing as min_qty rises — the trigger in 20260810100003 refuses
-- anything else, because a rung that goes UP with quantity is a typo that
-- silently overcharges.

insert into public.product_price_tiers (product_id, min_qty, unit_price)
select p.id, v.min_qty::int, v.unit_price::numeric
  from (values
    ('mug-ceramic-white',36,75),('mug-ceramic-white',100,65),('mug-ceramic-white',250,58),('mug-ceramic-white',500,52),('mug-ceramic-white',1000,47),
    ('mug-magic-color',24,135),('mug-magic-color',100,120),('mug-magic-color',250,108),('mug-magic-color',500,98),
    ('mug-travel-steel',25,295),('mug-travel-steel',100,270),('mug-travel-steel',250,248),('mug-travel-steel',500,229),
    ('mug-name-gift',1,190),('mug-name-gift',5,155),('mug-name-gift',12,125),('mug-name-gift',36,88),('mug-name-gift',100,72),
    ('bottle-steel-750',25,340),('bottle-steel-750',100,312),('bottle-steel-750',250,288),('bottle-steel-750',500,265),
    ('bottle-tritan-700',50,118),('bottle-tritan-700',100,105),('bottle-tritan-700',250,95),('bottle-tritan-700',500,86),
    ('pen-metal-classic',100,42),('pen-metal-classic',250,37),('pen-metal-classic',500,33),('pen-metal-classic',1000,29),
    ('pen-plastic-promo',250,9),('pen-plastic-promo',500,7.5),('pen-plastic-promo',1000,6.25),('pen-plastic-promo',5000,5),
    ('pen-set-gift',25,320),('pen-set-gift',100,290),('pen-set-gift',250,265),
    ('notebook-a5-pu',50,165),('notebook-a5-pu',100,148),('notebook-a5-pu',250,132),('notebook-a5-pu',500,119),
    ('notebook-spiral-a4',100,72),('notebook-spiral-a4',250,64),('notebook-spiral-a4',500,57),('notebook-spiral-a4',1000,51),
    ('tshirt-cotton-round',24,185),('tshirt-cotton-round',100,168),('tshirt-cotton-round',250,152),('tshirt-cotton-round',500,138),
    ('polo-pique',24,285),('polo-pique',100,262),('polo-pique',250,240),('polo-pique',500,222),
    ('cap-baseball',50,118),('cap-baseball',100,106),('cap-baseball',250,95),('cap-baseball',500,86),
    ('usb-metal-flip',50,205),('usb-metal-flip',100,188),('usb-metal-flip',250,172),('usb-metal-flip',500,158),
    ('powerbank-10000',25,485),('powerbank-10000',100,445),('powerbank-10000',250,412),('powerbank-10000',500,385),
    ('mousepad-fabric',50,68),('mousepad-fabric',100,60),('mousepad-fabric',250,53),('mousepad-fabric',500,47),
    ('bag-canvas-tote',50,95),('bag-canvas-tote',100,85),('bag-canvas-tote',250,76),('bag-canvas-tote',500,68),
    ('backpack-laptop',25,720),('backpack-laptop',100,665),('backpack-laptop',250,615),
    ('keychain-metal',100,34),('keychain-metal',250,29),('keychain-metal',500,25),('keychain-metal',1000,21),
    ('keychain-name-gift',1,85),('keychain-name-gift',5,68),('keychain-name-gift',12,54),('keychain-name-gift',50,36),
    ('wallclock-round',25,265),('wallclock-round',100,242),('wallclock-round',250,222),
    ('giftbox-ramadan',20,520),('giftbox-ramadan',50,478),('giftbox-ramadan',100,442),('giftbox-ramadan',250,408),
    ('businesscards-500',1,320),('businesscards-500',5,285),('businesscards-500',10,255),('businesscards-500',25,228)
  ) as v(slug, min_qty, unit_price)
  join public.products p on p.slug = v.slug
on conflict (product_id, min_qty) do nothing;

-- ------------------------------------------------ طرق الطباعة لكل منتج ------

insert into public.product_print_methods
  (product_id, method_code, setup_fee, setup_fee_per_color, setup_fee_waived_over_qty,
   unit_addon, addon_per_color, max_colors, method_min_qty, is_default)
select p.id, v.method_code, v.setup::numeric, v.per_color::boolean, v.waived::int,
       v.addon::numeric, v.addon_color::numeric, v.max_colors::int, v.min_qty::int, v.is_def::boolean
  from (values
    ('mug-ceramic-white','sublimation',0,false,null,0,0,null,null,true),
    ('mug-ceramic-white','screen',150,true,500,0,2,3,36,false),
    ('mug-magic-color','sublimation',0,false,null,0,0,null,null,true),
    ('mug-travel-steel','laser',0,false,null,12,0,null,null,true),
    ('mug-travel-steel','uv',100,false,250,8,0,null,null,false),
    ('mug-name-gift','sublimation',0,false,null,0,0,null,null,true),
    ('bottle-steel-750','laser',0,false,null,15,0,null,null,true),
    ('bottle-steel-750','uv',100,false,250,10,0,null,null,false),
    ('bottle-tritan-700','screen',150,true,500,0,1.5,3,50,true),
    ('bottle-tritan-700','uv',100,false,250,7,0,null,null,false),
    ('pen-metal-classic','laser',0,false,null,4,0,null,null,true),
    ('pen-metal-classic','pad',120,true,1000,0,1,2,100,false),
    ('pen-plastic-promo','pad',120,true,1000,0,0.75,2,250,true),
    ('pen-set-gift','laser',0,false,null,18,0,null,null,true),
    ('notebook-a5-pu','emboss',350,false,500,0,0,null,50,true),
    ('notebook-a5-pu','foil',200,false,500,6,0,null,50,false),
    ('notebook-a5-pu','screen',150,true,500,0,2,2,50,false),
    ('notebook-spiral-a4','digital',0,false,null,0,0,null,null,true),
    ('tshirt-cotton-round','dtf',0,false,null,22,0,null,null,true),
    ('tshirt-cotton-round','embroidery',250,false,250,18,3,8,24,false),
    ('tshirt-cotton-round','screen',150,true,500,0,3,4,50,false),
    ('polo-pique','embroidery',250,false,250,20,3,8,24,true),
    ('polo-pique','dtf',0,false,null,22,0,null,null,false),
    ('cap-baseball','embroidery',250,false,250,16,3,8,50,true),
    ('usb-metal-flip','laser',0,false,null,6,0,null,null,true),
    ('usb-metal-flip','uv',100,false,250,9,0,null,null,false),
    ('powerbank-10000','uv',100,false,250,14,0,null,null,true),
    ('powerbank-10000','laser',0,false,null,10,0,null,null,false),
    ('mousepad-fabric','sublimation',0,false,null,0,0,null,null,true),
    ('bag-canvas-tote','screen',150,true,500,0,2.5,4,50,true),
    ('bag-canvas-tote','dtf',0,false,null,20,0,null,null,false),
    ('backpack-laptop','embroidery',250,false,250,24,3,8,25,true),
    ('backpack-laptop','screen',150,true,500,0,3,3,50,false),
    ('keychain-metal','laser',0,false,null,3,0,null,null,true),
    ('keychain-metal','uv',100,false,500,5,0,null,null,false),
    ('keychain-name-gift','laser',0,false,null,3,0,null,null,true),
    ('wallclock-round','uv',100,false,250,18,0,null,null,true),
    ('giftbox-ramadan','digital',0,false,null,0,0,null,null,true),
    ('giftbox-ramadan','foil',200,false,250,12,0,null,null,false),
    ('businesscards-500','digital',0,false,null,0,0,null,null,true),
    ('businesscards-500','foil',200,false,25,45,0,null,null,false),
    ('businesscards-500','emboss',350,false,25,55,0,null,null,false)
  ) as v(slug, method_code, setup, per_color, waived, addon, addon_color, max_colors, min_qty, is_def)
  join public.products p on p.slug = v.slug
on conflict (product_id, method_code) do nothing;

-- ----------------------------------------------- أماكن الطباعة لكل منتج ----
--
-- preview_* are PERCENTAGES of the cover image. They are what makes the live
-- preview data-driven: four numbers per position instead of a component per
-- product. Left null here for products whose cover photo does not exist yet —
-- the preview simply does not render, which is the correct degradation.

insert into public.print_positions
  (product_id, code, name_ar, area_w_mm, area_h_mm,
   preview_x, preview_y, preview_w, preview_h, is_default, sort_order)
select p.id, v.code, v.name_ar, v.w::numeric, v.h::numeric,
       v.px::numeric, v.py::numeric, v.pw::numeric, v.ph::numeric, v.is_def::boolean, v.sort::int
  from (values
    ('mug-ceramic-white','front','الوش',90,80,34,32,32,30,true,10),
    ('mug-ceramic-white','back','الضهر',90,80,null,null,null,null,false,20),
    ('mug-magic-color','front','الوش',90,80,34,32,32,30,true,10),
    ('mug-travel-steel','body','جسم الترمس',60,40,36,38,28,18,true,10),
    ('mug-name-gift','front','الوش',90,80,34,32,32,30,true,10),
    ('mug-name-gift','back','الضهر',90,80,null,null,null,null,false,20),
    ('bottle-steel-750','body','جسم الزجاجة',55,120,40,32,20,34,true,10),
    ('bottle-tritan-700','body','جسم الزجاجة',60,100,40,32,20,30,true,10),
    ('pen-metal-classic','barrel','جسم القلم',45,6,30,46,40,6,true,10),
    ('pen-plastic-promo','barrel','جسم القلم',50,7,30,46,40,6,true,10),
    ('pen-plastic-promo','clip','الكليب',25,4,null,null,null,null,false,20),
    ('pen-set-gift','barrel','جسم القلم',45,6,30,46,40,6,true,10),
    ('pen-set-gift','box','بلاكة العلبة',40,15,null,null,null,null,false,20),
    ('notebook-a5-pu','cover','الغلاف',80,40,32,34,36,22,true,10),
    ('notebook-spiral-a4','cover','الغلاف الكامل',297,210,12,10,76,80,true,10),
    ('tshirt-cotton-round','chest_left','صدر شمال',90,90,58,30,16,16,true,10),
    ('tshirt-cotton-round','chest_full','الصدر بالكامل',280,300,30,28,40,40,false,20),
    ('tshirt-cotton-round','back','الضهر',300,350,null,null,null,null,false,30),
    ('polo-pique','chest_left','صدر شمال',80,80,58,30,15,15,true,10),
    ('polo-pique','sleeve','الكم',60,60,null,null,null,null,false,20),
    ('cap-baseball','front','الوش',110,50,34,38,32,16,true,10),
    ('cap-baseball','side','الجنب',60,30,null,null,null,null,false,20),
    ('usb-metal-flip','body','جسم الفلاشة',35,10,32,44,36,10,true,10),
    ('powerbank-10000','front','الوش',90,50,30,32,40,26,true,10),
    ('mousepad-fabric','full','السطح بالكامل',250,210,8,10,84,80,true,10),
    ('bag-canvas-tote','front','الوش',280,300,28,30,44,40,true,10),
    ('bag-canvas-tote','back','الضهر',280,300,null,null,null,null,false,20),
    ('backpack-laptop','front_pocket','الجيب الأمامي',120,80,36,42,28,18,true,10),
    ('keychain-metal','side_a','الوجه الأول',30,20,36,40,28,20,true,10),
    ('keychain-metal','side_b','الوجه التاني',30,20,null,null,null,null,false,20),
    ('keychain-name-gift','side_a','الوجه الأول',30,20,36,40,28,20,true,10),
    ('keychain-name-gift','side_b','الوجه التاني',30,20,null,null,null,null,false,20),
    ('wallclock-round','dial','قرص الساعة',260,260,18,18,64,64,true,10),
    ('giftbox-ramadan','lid','غطا العلبة',250,200,20,22,60,48,true,10),
    ('businesscards-500','front','الوش',90,55,10,14,80,72,true,10),
    ('businesscards-500','back','الضهر',90,55,null,null,null,null,false,20)
  ) as v(slug, code, name_ar, w, h, px, py, pw, ph, is_def, sort)
  join public.products p on p.slug = v.slug
on conflict (product_id, code) do nothing;

-- A worked example of the override table. Everywhere else it stays empty,
-- which by the documented convention means "every method the product supports
-- works here". On the travel mug the handle is the exception: pad printing
-- reaches it, laser does not.
insert into public.position_print_methods (position_id, method_code, area_w_mm, area_h_mm, max_colors)
select pos.id, 'uv', 40, 25, null
  from public.print_positions pos
  join public.products p on p.id = pos.product_id
 where p.slug = 'mug-travel-steel' and pos.code = 'body'
on conflict do nothing;

-- ------------------------------------------------------------- خيارات ------

insert into public.product_option_groups (product_id, code, label_ar, is_required, sort_order)
select p.id, v.code, v.label_ar, v.req::boolean, v.sort::int
  from (values
    ('mug-ceramic-white','color','لون الداخل والودن',false,10),
    ('mug-name-gift','color','لون الداخل والودن',false,10),
    ('bottle-steel-750','color','لون الزجاجة',true,10),
    ('pen-plastic-promo','color','لون جسم القلم',true,10),
    ('tshirt-cotton-round','color','اللون',true,10),
    ('tshirt-cotton-round','size','المقاس',true,20),
    ('polo-pique','color','اللون',true,10),
    ('polo-pique','size','المقاس',true,20),
    ('cap-baseball','color','اللون',true,10),
    ('usb-metal-flip','capacity','السعة',true,10),
    ('notebook-a5-pu','color','لون الغلاف',true,10),
    ('bag-canvas-tote','color','لون القماش',true,10),
    ('businesscards-500','finish','التشطيب',true,10)
  ) as v(slug, code, label_ar, req, sort)
  join public.products p on p.slug = v.slug
on conflict (product_id, code) do nothing;

insert into public.product_option_items (group_id, value, label_ar, hex, price_delta, is_available, sort_order)
select g.id, v.value, v.label_ar, v.hex, v.delta::numeric, v.avail::boolean, v.sort::int
  from (values
    ('mug-ceramic-white','color','white','أبيض بالكامل','#FFFFFF',0,true,10),
    ('mug-ceramic-white','color','black','داخل أسود','#111111',8,true,20),
    ('mug-ceramic-white','color','red','داخل أحمر','#C62828',8,true,30),
    ('mug-ceramic-white','color','blue','داخل أزرق','#1565C0',8,false,40),
    ('mug-name-gift','color','white','أبيض بالكامل','#FFFFFF',0,true,10),
    ('mug-name-gift','color','black','داخل أسود','#111111',10,true,20),
    ('mug-name-gift','color','pink','داخل بمبي','#EC407A',10,true,30),
    ('bottle-steel-750','color','silver','فضي','#C0C4CC',0,true,10),
    ('bottle-steel-750','color','black','أسود مط','#1A1A1A',12,true,20),
    ('bottle-steel-750','color','navy','كحلي','#1B2A4A',12,true,30),
    ('pen-plastic-promo','color','white','أبيض','#FFFFFF',0,true,10),
    ('pen-plastic-promo','color','blue','أزرق','#1565C0',0,true,20),
    ('pen-plastic-promo','color','red','أحمر','#C62828',0,true,30),
    ('pen-plastic-promo','color','green','أخضر','#2E7D32',0,true,40),
    ('tshirt-cotton-round','color','white','أبيض','#FFFFFF',0,true,10),
    ('tshirt-cotton-round','color','black','أسود','#111111',0,true,20),
    ('tshirt-cotton-round','color','navy','كحلي','#1B2A4A',0,true,30),
    ('tshirt-cotton-round','color','grey','رمادي','#9E9E9E',0,true,40),
    ('tshirt-cotton-round','size','s','S',null,0,true,10),
    ('tshirt-cotton-round','size','m','M',null,0,true,20),
    ('tshirt-cotton-round','size','l','L',null,0,true,30),
    ('tshirt-cotton-round','size','xl','XL',null,0,true,40),
    ('tshirt-cotton-round','size','xxl','2XL',null,12,true,50),
    ('tshirt-cotton-round','size','xxxl','3XL',null,20,true,60),
    ('polo-pique','color','white','أبيض','#FFFFFF',0,true,10),
    ('polo-pique','color','navy','كحلي','#1B2A4A',0,true,20),
    ('polo-pique','color','black','أسود','#111111',0,true,30),
    ('polo-pique','size','s','S',null,0,true,10),
    ('polo-pique','size','m','M',null,0,true,20),
    ('polo-pique','size','l','L',null,0,true,30),
    ('polo-pique','size','xl','XL',null,0,true,40),
    ('polo-pique','size','xxl','2XL',null,15,true,50),
    ('cap-baseball','color','black','أسود','#111111',0,true,10),
    ('cap-baseball','color','navy','كحلي','#1B2A4A',0,true,20),
    ('cap-baseball','color','white','أبيض','#FFFFFF',0,true,30),
    ('usb-metal-flip','capacity','16','١٦ جيجا',null,0,true,10),
    ('usb-metal-flip','capacity','32','٣٢ جيجا',null,35,true,20),
    ('usb-metal-flip','capacity','64','٦٤ جيجا',null,85,true,30),
    ('notebook-a5-pu','color','black','أسود','#111111',0,true,10),
    ('notebook-a5-pu','color','navy','كحلي','#1B2A4A',0,true,20),
    ('notebook-a5-pu','color','brown','بني','#6D4C41',0,true,30),
    ('bag-canvas-tote','color','natural','بيچ طبيعي','#D9CDB4',0,true,10),
    ('bag-canvas-tote','color','black','أسود','#111111',6,true,20),
    ('businesscards-500','finish','matte','سلوفان مط',null,0,true,10),
    ('businesscards-500','finish','gloss','سلوفان لامع',null,0,true,20),
    ('businesscards-500','finish','softtouch','سوفت تاتش',null,45,true,30)
  ) as v(slug, group_code, value, label_ar, hex, delta, avail, sort)
  join public.products p on p.slug = v.slug
  join public.product_option_groups g on g.product_id = p.id and g.code = v.group_code
on conflict (group_id, value) do nothing;

-- ------------------------------------------------- ربط المنتج بالمناسبة ----

insert into public.product_occasions (product_id, occasion_id, is_primary)
select p.id, o.id, v.prim::boolean
  from (values
    ('giftbox-ramadan','ramadan',true),
    ('mug-ceramic-white','conference',true),
    ('notebook-a5-pu','new-year',true),
    ('notebook-spiral-a4','conference',true),
    ('bag-canvas-tote','conference',false),
    ('pen-set-gift','opening',true),
    ('mug-name-gift','birthday',true),
    ('mug-name-gift','love',false),
    ('keychain-name-gift','love',true),
    ('keychain-name-gift','graduation',false),
    ('tshirt-cotton-round','graduation',true),
    ('wallclock-round','opening',false),
    ('mug-magic-color','mothers-day',true)
  ) as v(slug, occ_slug, prim)
  join public.products  p on p.slug = v.slug
  join public.occasions o on o.slug = v.occ_slug
on conflict do nothing;

-- ------------------------------------------------------------- النشر ------
--
-- Last, and only now. Every product below has a tier at or below its MOQ, at
-- least one print method and at least one position — the three things
-- pricing_complete() insists on. Publishing before this point raises
-- PRICING_INCOMPLETE, which is the gate working, not the seed failing.

update public.products set is_published = true where is_published = false;

update public.products set is_featured = true
 where slug in ('mug-ceramic-white','notebook-a5-pu','tshirt-cotton-round',
                'usb-metal-flip','bag-canvas-tote','giftbox-ramadan');
