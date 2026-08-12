-- ============================================================================
--  العيادة — كتالوج الأدوية والتحاليل
--
--  ⚠  Sorts AFTER 20260810100006_rls.sql. Carries its own grants, at the
--     bottom.
--
--  THE CATALOGUE IS DOWNLOADED WHOLE ONTO EVERY CLINIC DEVICE.
--
--  That is the entire reason "type one letter, see the drug" is instant and
--  keeps working when the clinic's internet drops. A server-side search would
--  be both slower on every keystroke AND the first thing to fail at the moment
--  it is needed most.
--
--  So the sync has to be cheap to repeat: clinic.drug_catalog(since) returns
--  only rows touched after `since`, plus the catalogue version from settings.
--  First run pulls everything; every run after that pulls almost nothing.
-- ============================================================================

-- Any change to the catalogue bumps the version, so a device holding a stale
-- copy can tell without diffing a few thousand rows.
create or replace function clinic.bump_catalog_version()
returns trigger
language plpgsql set search_path = clinic, public as $$
begin
  update clinic.settings set drug_catalog_version = drug_catalog_version + 1 where id;
  return null;
end $$;

drop trigger if exists drugs_bump_version on clinic.drugs;
create trigger drugs_bump_version after insert or update or delete on clinic.drugs
  for each statement execute function clinic.bump_catalog_version();

-- ---------------------------------------------------------------------------
--  المزامنة — اللي اتغيّر بس
--
--  Deletions are handled by is_active rather than DELETE: a device that never
--  hears about a removed row would otherwise keep offering a drug the clinic
--  has withdrawn. A row flipped inactive still arrives in the delta and the
--  device drops it locally.
-- ---------------------------------------------------------------------------
create or replace function clinic.drug_catalog(p_since timestamptz default null)
returns jsonb
language sql stable security definer set search_path = clinic, public as $$
  select case when not clinic.is_staff() then null else jsonb_build_object(
    'version', (select drug_catalog_version from clinic.settings where id),
    'now',     now(),
    'drugs',   coalesce((
      select jsonb_agg(jsonb_build_object(
               'id', d.id, 'trade_name', d.trade_name,
               'trade_name_ar', d.trade_name_ar,
               'generic_ar', d.generic_ar, 'generic_en', d.generic_en,
               'form_ar', d.form_ar, 'strength', d.strength,
               'name_key', d.name_key, 'is_active', d.is_active))
        from clinic.drugs d
       where p_since is null or d.updated_at > p_since), '[]'::jsonb),
    -- This doctor's own habits, so the picker can float what they actually
    -- prescribe to the top without a second round trip.
    'usage',   coalesce((
      select jsonb_object_agg(u.drug_id::text, u.uses)
        from clinic.drug_usage u where u.doctor_id = auth.uid()), '{}'::jsonb),
    'tests',   coalesce((
      select jsonb_agg(jsonb_build_object(
               'id', t.id, 'name_ar', t.name_ar, 'name_en', t.name_en,
               'category', t.category, 'name_key', t.name_key,
               'is_active', t.is_active))
        from clinic.lab_tests t
       where p_since is null or t.updated_at > p_since), '[]'::jsonb)
  ) end
$$;

-- Adding a drug that is not in the list, from the prescription screen, without
-- leaving it. A catalogue nobody can extend at the moment of need is a
-- catalogue people work around by typing free text, and free text is what the
-- snapshot columns exist to avoid depending on.
create or replace function clinic.add_drug(
  p_trade_name    text,
  p_generic_ar    text default null,
  p_form_ar       text default '',
  p_strength      text default '',
  p_trade_name_ar text default ''
) returns uuid
language plpgsql security definer set search_path = clinic, public as $$
declare v_id uuid; v_name text := nullif(trim(coalesce(p_trade_name,'')), '');
begin
  if not clinic.is_clinician() then
    raise exception 'NOT_ALLOWED' using errcode = 'P0001';
  end if;
  if v_name is null then
    raise exception 'NAME_REQUIRED' using errcode = 'P0001';
  end if;

  insert into clinic.drugs (trade_name, trade_name_ar, generic_ar, form_ar, strength)
  values (v_name, coalesce(trim(p_trade_name_ar), ''),
          nullif(trim(coalesce(p_generic_ar,'')),''),
          coalesce(trim(p_form_ar), ''), coalesce(trim(p_strength), ''))
  on conflict (trade_name, strength, form_ar) do update
    set is_active = true                    -- re-adding a withdrawn one revives it
  returning id into v_id;

  return v_id;
end $$;

-- ============================================================================
--  البذرة — أدوية شائعة في السوق المصري
--
--  A STARTING POINT, not a formulary. It exists so the picker is useful on day
--  one instead of empty, and every row is editable from the screen. The
--  clinic's own list — the drugs this doctor actually writes — is a better
--  seed than this one by a wide margin, and replacing it is a paste into the
--  drugs screen, not a migration.
--
--  Re-runnable: `on conflict do nothing`, keyed on (trade_name, strength,
--  form_ar).
-- ============================================================================
insert into clinic.drugs (trade_name, generic_ar, generic_en, form_ar, strength) values
  -- مسكنات وخافضات حرارة
  ('Panadol',      'باراسيتامول',            'Paracetamol',            'أقراص', '500 مجم'),
  ('Panadol Extra','باراسيتامول وكافيين',    'Paracetamol/Caffeine',   'أقراص', '500 مجم'),
  ('Adol',         'باراسيتامول',            'Paracetamol',            'أقراص', '500 مجم'),
  ('Abimol',       'باراسيتامول',            'Paracetamol',            'شراب',  '120 مجم/5 مل'),
  ('Cataflam',     'ديكلوفيناك بوتاسيوم',    'Diclofenac Potassium',   'أقراص', '50 مجم'),
  ('Voltaren',     'ديكلوفيناك صوديوم',      'Diclofenac Sodium',      'أمبول', '75 مجم'),
  ('Rofenac',      'ديكلوفيناك صوديوم',      'Diclofenac Sodium',      'أقراص', '50 مجم'),
  ('Brufen',       'إيبوبروفين',             'Ibuprofen',              'أقراص', '400 مجم'),
  ('Brufen',       'إيبوبروفين',             'Ibuprofen',              'شراب',  '100 مجم/5 مل'),
  ('Ketolac',      'كيتورولاك',              'Ketorolac',              'أمبول', '30 مجم'),
  ('Ketofan',      'كيتوبروفين',             'Ketoprofen',             'أقراص', '100 مجم'),
  ('Myofen',       'إيبوبروفين وباراسيتامول','Ibuprofen/Paracetamol',  'أقراص', ''),

  -- مضادات حيوية
  ('Augmentin',    'أموكسيسيللين وكلافولانيك','Amoxicillin/Clavulanate','أقراص','1 جم'),
  ('Augmentin',    'أموكسيسيللين وكلافولانيك','Amoxicillin/Clavulanate','شراب', '457 مجم/5 مل'),
  ('Hibiotic',     'أموكسيسيللين وكلافولانيك','Amoxicillin/Clavulanate','أقراص','1 جم'),
  ('Amoxil',       'أموكسيسيللين',           'Amoxicillin',            'كبسول','500 مجم'),
  ('Unictam',      'أمبيسيللين وسلباكتام',   'Ampicillin/Sulbactam',   'فيال', '1.5 جم'),
  ('Zithromax',    'أزيثرومايسين',           'Azithromycin',           'أقراص','500 مجم'),
  ('Zisrocin',     'أزيثرومايسين',           'Azithromycin',           'شراب', '200 مجم/5 مل'),
  ('Klaricid',     'كلاريثرومايسين',         'Clarithromycin',         'أقراص','500 مجم'),
  ('Ciprocin',     'سيبروفلوكساسين',         'Ciprofloxacin',          'أقراص','500 مجم'),
  ('Tavanic',      'ليفوفلوكساسين',          'Levofloxacin',           'أقراص','500 مجم'),
  ('Cefotax',      'سيفوتاكسيم',             'Cefotaxime',             'فيال', '1 جم'),
  ('Ceftriaxone',  'سيفترياكسون',            'Ceftriaxone',            'فيال', '1 جم'),
  ('Zinnat',       'سيفوروكسيم',             'Cefuroxime',             'أقراص','500 مجم'),
  ('Flagyl',       'ميترونيدازول',           'Metronidazole',          'أقراص','500 مجم'),
  ('Amrizole',     'ميترونيدازول',           'Metronidazole',          'شراب', '125 مجم/5 مل'),
  ('Doxymycin',    'دوكسيسيكلين',            'Doxycycline',            'كبسول','100 مجم'),

  -- الجهاز الهضمي
  ('Nexium',       'إيزوميبرازول',           'Esomeprazole',           'أقراص','40 مجم'),
  ('Controloc',    'بانتوبرازول',            'Pantoprazole',           'أقراص','40 مجم'),
  ('Omez',         'أوميبرازول',             'Omeprazole',             'كبسول','20 مجم'),
  ('Motilium',     'دومبيريدون',             'Domperidone',            'أقراص','10 مجم'),
  ('Primperan',    'ميتوكلوبراميد',          'Metoclopramide',         'أمبول','10 مجم'),
  ('Buscopan',     'هيوسين بيوتيل بروميد',   'Hyoscine Butylbromide',  'أقراص','10 مجم'),
  ('Spasmo-Digestin','إنزيمات هاضمة',        'Digestive Enzymes',      'أقراص',''),
  ('Antinal',      'نيفوروكسازيد',           'Nifuroxazide',           'كبسول','200 مجم'),
  ('Smecta',       'ديوسميكتيت',             'Diosmectite',            'أكياس','3 جم'),
  ('Duphalac',     'لاكتيولوز',              'Lactulose',              'شراب', '10 جم/15 مل'),
  ('Gaviscon',     'ألجينات الصوديوم',       'Sodium Alginate',        'شراب', ''),
  ('Epicogel',     'مضاد حموضة',             'Antacid',                'شراب', ''),
  ('Colona',       'ميبيفيرين',              'Mebeverine',             'كبسول','200 مجم'),

  -- الحساسية والجهاز التنفسي
  ('Telfast',      'فيكسوفينادين',           'Fexofenadine',           'أقراص','180 مجم'),
  ('Claritine',    'لوراتادين',              'Loratadine',             'أقراص','10 مجم'),
  ('Zyrtec',       'سيتريزين',               'Cetirizine',             'أقراص','10 مجم'),
  ('Allergyl',     'كلورفينيرامين',          'Chlorpheniramine',       'شراب', ''),
  ('Ventolin',     'سالبيوتامول',            'Salbutamol',             'بخاخ', '100 ميكروجم'),
  ('Ventolin',     'سالبيوتامول',            'Salbutamol',             'محلول بخار','5 مجم/مل'),
  ('Flixotide',    'فلوتيكازون',             'Fluticasone',            'بخاخ', '125 ميكروجم'),
  ('Symbicort',    'بوديزونيد وفورموتيرول',  'Budesonide/Formoterol',  'بخاخ', ''),
  ('Mucosolvan',   'أمبروكسول',              'Ambroxol',               'شراب', '30 مجم/5 مل'),
  ('Fluimucil',    'أسيتيل سيستئين',         'Acetylcysteine',         'أكياس','200 مجم'),
  ('Otrivin',      'زيلوميتازولين',          'Xylometazoline',         'نقط أنف',''),
  ('Congestal',    'مضاد احتقان',            'Decongestant',           'أقراص',''),

  -- القلب والضغط والدهون
  ('Concor',       'بيسوبرولول',             'Bisoprolol',             'أقراص','5 مجم'),
  ('Tritace',      'راميبريل',               'Ramipril',               'أقراص','5 مجم'),
  ('Norvasc',      'أملوديبين',              'Amlodipine',             'أقراص','5 مجم'),
  ('Capoten',      'كابتوبريل',              'Captopril',              'أقراص','25 مجم'),
  ('Lasix',        'فوروسيميد',              'Furosemide',             'أقراص','40 مجم'),
  ('Aspocid',      'أسبرين',                 'Aspirin',                'أقراص','75 مجم'),
  ('Plavix',       'كلوبيدوجريل',            'Clopidogrel',            'أقراص','75 مجم'),
  ('Lipitor',      'أتورفاستاتين',           'Atorvastatin',           'أقراص','20 مجم'),
  ('Crestor',      'روسوفاستاتين',           'Rosuvastatin',           'أقراص','10 مجم'),

  -- السكر والغدة
  ('Glucophage',   'ميتفورمين',              'Metformin',              'أقراص','850 مجم'),
  ('Amaryl',       'جليمبيريد',              'Glimepiride',            'أقراص','2 مجم'),
  ('Januvia',      'سيتاجليبتين',            'Sitagliptin',            'أقراص','100 مجم'),
  ('Lantus',       'إنسولين جلارجين',        'Insulin Glargine',       'قلم',  '100 وحدة/مل'),
  ('Mixtard',      'إنسولين مخلوط',          'Insulin Mixed',          'قلم',  '100 وحدة/مل'),
  ('Eltroxin',     'ليفوثيروكسين',           'Levothyroxine',          'أقراص','50 ميكروجم'),

  -- فيتامينات ومعادن
  ('Vidrop',       'فيتامين د',              'Vitamin D3',             'نقط', ''),
  ('Devarol-S',    'فيتامين د',              'Vitamin D3',             'أمبول','200000 وحدة'),
  ('Ossofortin',   'كالسيوم وفيتامين د',     'Calcium/Vitamin D',      'أقراص',''),
  ('Ferrofol',     'حديد وحمض فوليك',        'Iron/Folic Acid',        'كبسول',''),
  ('Neurorubine',  'فيتامين ب المركب',       'Vitamin B Complex',      'أقراص',''),
  ('Depovit B12',  'فيتامين ب ١٢',           'Vitamin B12',            'أمبول',''),
  ('Zincoral',     'زنك',                    'Zinc',                   'شراب', ''),

  -- الأعصاب والنفسية
  ('Lyrica',       'بريجابالين',             'Pregabalin',             'كبسول','75 مجم'),
  ('Neurontin',    'جابابنتين',              'Gabapentin',             'كبسول','300 مجم'),
  ('Depakine',     'صوديوم فالبروات',        'Sodium Valproate',       'أقراص','500 مجم'),
  ('Tegretol',     'كاربامازيبين',           'Carbamazepine',          'أقراص','200 مجم'),
  ('Cipralex',     'إيسيتالوبرام',           'Escitalopram',           'أقراص','10 مجم'),
  ('Prozac',       'فلوكسيتين',              'Fluoxetine',             'كبسول','20 مجم'),
  ('Xanax',        'ألبرازولام',             'Alprazolam',             'أقراص','0.5 مجم'),
  ('Mydocalm',     'تولبيريزون',             'Tolperisone',            'أقراص','150 مجم'),
  ('Myogesic',     'مرخي عضلات ومسكن',       'Muscle Relaxant',        'أقراص',''),

  -- كورتيزون وإنزيمات وموضعي
  ('Solu-Medrol',  'ميثيل بريدنيزولون',      'Methylprednisolone',     'فيال', '40 مجم'),
  ('Hydrocortisone','هيدروكورتيزون',         'Hydrocortisone',         'فيال', '100 مجم'),
  ('Alphintern',   'إنزيمات مضادة للالتهاب', 'Trypsin/Chymotrypsin',   'أقراص',''),
  ('Fucidin',      'حمض الفيوسيديك',         'Fusidic Acid',           'كريم', ''),
  ('Fucicort',     'فيوسيديك وبيتاميثازون',  'Fusidic/Betamethasone',  'كريم', ''),
  ('Kenacomb',     'مرهم مركب',              'Combination Ointment',   'مرهم', ''),
  ('Canesten',     'كلوتريمازول',            'Clotrimazole',           'كريم', ''),
  ('Diflucan',     'فلوكونازول',             'Fluconazole',            'كبسول','150 مجم'),
  ('Nystatin',     'نيستاتين',               'Nystatin',               'معلق', ''),
  ('Zovirax',      'أسيكلوفير',              'Aciclovir',              'أقراص','400 مجم'),

  -- المسالك والنساء
  ('Uvamin',       'نيتروفورانتوين',         'Nitrofurantoin',         'كبسول','100 مجم'),
  ('Rowatinex',    'زيوت طيارة',             'Terpene Combination',    'كبسول',''),
  ('Duphaston',    'ديدروجستيرون',           'Dydrogesterone',         'أقراص','10 مجم'),
  ('Cyclo-Progynova','هرمونات بديلة',        'Estradiol/Norgestrel',   'أقراص','')
on conflict (trade_name, strength, form_ar) do nothing;

-- ---------------------------------------------------------------------------
--  الأسماء التجارية بالعربي
--
--  ⚠ THIS BLOCK IS NOT COSMETIC. Egyptian doctors prescribe by brand, and many
--    of them type Arabic. Without these spellings the search box answers
--    "كونكور" with nothing while holding Concor, and "فلاجيل" with nothing
--    while holding Flagyl — the drug is in the catalogue and simply cannot be
--    found by the words the doctor used.
--
--  Kept as a separate UPDATE rather than a sixth column on the INSERT above so
--  that the list reads as what it is: a spelling map, extendable one line at a
--  time by whoever notices a name that will not come up.
-- ---------------------------------------------------------------------------
update clinic.drugs d set trade_name_ar = v.ar
  from (values
    ('Panadol','بانادول'), ('Panadol Extra','بانادول إكسترا'), ('Adol','أدول'),
    ('Abimol','أبيمول'), ('Cataflam','كتافلام'), ('Voltaren','فولتارين'),
    ('Rofenac','روفيناك'), ('Brufen','بروفين'), ('Ketolac','كيتولاك'),
    ('Ketofan','كيتوفان'), ('Myofen','مايوفين'),

    ('Augmentin','أوجمنتين'), ('Hibiotic','هاي بيوتك'), ('Amoxil','أموكسيل'),
    ('Unictam','يونيكتام'), ('Zithromax','زيثروماكس'), ('Zisrocin','زيسروسين'),
    ('Klaricid','كلاريسيد'), ('Ciprocin','سيبروسين'), ('Tavanic','تافانيك'),
    ('Cefotax','سيفوتاكس'), ('Ceftriaxone','سيفترياكسون'), ('Zinnat','زينات'),
    ('Flagyl','فلاجيل'), ('Amrizole','أمريزول'), ('Doxymycin','دوكسيميسين'),

    ('Nexium','نيكسيوم'), ('Controloc','كونترولوك'), ('Omez','أوميز'),
    ('Motilium','موتيليوم'), ('Primperan','بريمبران'), ('Buscopan','بوسكوبان'),
    ('Spasmo-Digestin','سبازمو ديچستين'), ('Antinal','أنتينال'),
    ('Smecta','سميكتا'), ('Duphalac','دوفالاك'), ('Gaviscon','جافيسكون'),
    ('Epicogel','إبيكوجيل'), ('Colona','كولونا'),

    ('Telfast','تلفاست'), ('Claritine','كلاريتين'), ('Zyrtec','زيرتك'),
    ('Allergyl','أليرجيل'), ('Ventolin','فنتولين'), ('Flixotide','فليكسوتايد'),
    ('Symbicort','سيمبيكورت'), ('Mucosolvan','ميوكوسولفان'),
    ('Fluimucil','فلوموسيل'), ('Otrivin','أوتريفين'), ('Congestal','كونجستال'),

    ('Concor','كونكور'), ('Tritace','تريتاس'), ('Norvasc','نورفاسك'),
    ('Capoten','كابوتين'), ('Lasix','لازيكس'), ('Aspocid','أسبوسيد'),
    ('Plavix','بلافكس'), ('Lipitor','ليبيتور'), ('Crestor','كريستور'),

    ('Glucophage','جلوكوفاج'), ('Amaryl','أماريل'), ('Januvia','جانوفيا'),
    ('Lantus','لانتوس'), ('Mixtard','ميكستارد'), ('Eltroxin','إلتروكسين'),

    ('Vidrop','فيدروب'), ('Devarol-S','ديفارول'), ('Ossofortin','أوسوفورتين'),
    ('Ferrofol','فيروفول'), ('Neurorubine','نيوروروبين'),
    ('Depovit B12','ديبوفيت'), ('Zincoral','زنكورال'),

    ('Lyrica','ليريكا'), ('Neurontin','نيورونتين'), ('Depakine','ديباكين'),
    ('Tegretol','تيجريتول'), ('Cipralex','سيبرالكس'), ('Prozac','بروزاك'),
    ('Xanax','زاناكس'), ('Mydocalm','ميدوكالم'), ('Myogesic','مايوجيسك'),

    ('Solu-Medrol','سولومدرول'), ('Hydrocortisone','هيدروكورتيزون'),
    ('Alphintern','ألفنترن'), ('Fucidin','فيوسيدين'), ('Fucicort','فيوسيكورت'),
    ('Kenacomb','كيناكومب'), ('Canesten','كانستين'), ('Diflucan','ديفلوكان'),
    ('Nystatin','نيستاتين'), ('Zovirax','زوفيراكس'),

    ('Uvamin','يوفامين'), ('Rowatinex','رواتينكس'), ('Duphaston','دوفاستون'),
    ('Cyclo-Progynova','سيكلو بروجينوفا')
  ) as v(name, ar)
 where d.trade_name = v.name and d.trade_name_ar = '';

-- ---------------------------------------------------------- تحاليل وأشعة ----
insert into clinic.lab_tests (name_ar, name_en, category) values
  ('صورة دم كاملة',            'CBC',                    'تحاليل'),
  ('سرعة الترسيب',             'ESR',                    'تحاليل'),
  ('بروتين سي التفاعلي',       'CRP',                    'تحاليل'),
  ('سكر صائم',                 'Fasting Blood Sugar',    'تحاليل'),
  ('سكر بعد الأكل بساعتين',    'Post-Prandial Sugar',    'تحاليل'),
  ('السكر التراكمي',           'HbA1c',                  'تحاليل'),
  ('وظائف كبد',                'Liver Function Tests',   'تحاليل'),
  ('وظائف كلى',                'Kidney Function Tests',  'تحاليل'),
  ('دهون كاملة',               'Lipid Profile',          'تحاليل'),
  ('حمض بوليك',                'Uric Acid',              'تحاليل'),
  ('وظائف غدة درقية',          'TSH / T3 / T4',          'تحاليل'),
  ('تحليل بول',                'Urine Analysis',         'تحاليل'),
  ('تحليل براز',               'Stool Analysis',         'تحاليل'),
  ('مزرعة بول',                'Urine Culture',          'تحاليل'),
  ('فيتامين د',                'Vitamin D (25-OH)',      'تحاليل'),
  ('فيتامين ب ١٢',             'Vitamin B12',            'تحاليل'),
  ('مخزون الحديد',             'Serum Ferritin',         'تحاليل'),
  ('صوديوم وبوتاسيوم',         'Serum Electrolytes',     'تحاليل'),
  ('أشعة عادية على الصدر',     'Chest X-Ray',            'أشعة'),
  ('أشعة عادية على البطن',     'Abdominal X-Ray',        'أشعة'),
  ('سونار على البطن والحوض',   'Abdominopelvic US',      'أشعة'),
  ('سونار على الغدة الدرقية',  'Thyroid US',             'أشعة'),
  ('دوبلر على الشرايين',       'Arterial Doppler',       'أشعة'),
  ('أشعة مقطعية',              'CT Scan',                'أشعة'),
  ('رنين مغناطيسي',            'MRI',                    'أشعة'),
  ('رسم قلب',                  'ECG',                    'وظائف'),
  ('إيكو على القلب',           'Echocardiography',       'وظائف'),
  ('وظائف تنفس',               'Spirometry',             'وظائف')
on conflict (name_ar, category) do nothing;

-- ---------------------------------------------------------------- grants ---

revoke execute on function clinic.drug_catalog(timestamptz)              from public, anon;
revoke execute on function clinic.add_drug(text, text, text, text, text) from public, anon;
revoke execute on function clinic.bump_catalog_version()                 from public, anon;

grant execute on function clinic.drug_catalog(timestamptz)        to authenticated;
grant execute on function clinic.add_drug(text, text, text, text, text) to authenticated;
