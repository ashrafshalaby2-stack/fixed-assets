-- ============================================================
--  إعداد قاعدة بيانات نظام الأصول الثابتة على Supabase
--  انسخ هذا الملف كاملاً والصقه في:  Supabase ← SQL Editor ← New query ← Run
--  ثم في التطبيق: الإعدادات ← المزامنة السحابية ← أدخل Project URL و anon key
-- ============================================================

-- 1) الجداول ----------------------------------------------------

create table if not exists public.companies (
  id         uuid primary key default gen_random_uuid(),
  name       text not null,
  currency   text default 'ر.س',
  owner      uuid not null references auth.users(id) on delete cascade,
  created_at timestamptz default now()
);

create table if not exists public.company_members (
  company_id uuid not null references public.companies(id) on delete cascade,
  user_id    uuid not null references auth.users(id) on delete cascade,
  role       text default 'editor',          -- owner | editor
  email      text,
  created_at timestamptz default now(),
  primary key (company_id, user_id)
);

create table if not exists public.company_meta (
  company_id uuid primary key references public.companies(id) on delete cascade,
  categories jsonb default '[]'::jsonb,       -- شجرة التصنيفات
  org        jsonb default '[]'::jsonb,       -- الهيكل الإداري
  refs       jsonb default '{}'::jsonb,       -- القوائم المرجعية
  updated_at timestamptz default now()
);

create table if not exists public.assets (
  id         text primary key,               -- معرّف الأصل المُولّد في التطبيق
  company_id uuid not null references public.companies(id) on delete cascade,
  data       jsonb not null,                 -- كامل بيانات الأصل
  updated_at timestamptz default now()
);
create index if not exists assets_company_idx on public.assets(company_id);


-- 2) دالة مساعدة: هل المستخدم الحالي عضو/مالك للشركة؟ -----------
--    SECURITY DEFINER لتجاوز RLS ومنع التكرار اللانهائي في السياسات.

create or replace function public.is_company_member(cid uuid)
returns boolean
language sql
security definer
set search_path = public
stable
as $$
  select
    exists (select 1 from public.companies c
            where c.id = cid and c.owner = auth.uid())
    or
    exists (select 1 from public.company_members m
            where m.company_id = cid and m.user_id = auth.uid());
$$;


-- 3) تفعيل حماية مستوى الصف (RLS) ------------------------------

alter table public.companies        enable row level security;
alter table public.company_members  enable row level security;
alter table public.company_meta     enable row level security;
alter table public.assets           enable row level security;


-- 4) السياسات ---------------------------------------------------

-- companies: يقرأها الأعضاء، ويتحكّم بها المالك فقط
drop policy if exists companies_select on public.companies;
create policy companies_select on public.companies
  for select using (public.is_company_member(id));

drop policy if exists companies_insert on public.companies;
create policy companies_insert on public.companies
  for insert with check (owner = auth.uid());

drop policy if exists companies_update on public.companies;
create policy companies_update on public.companies
  for update using (owner = auth.uid());

drop policy if exists companies_delete on public.companies;
create policy companies_delete on public.companies
  for delete using (owner = auth.uid());

-- company_members: يراهم الأعضاء؛ يضيف المستخدم نفسه (انضمام) أو يضيف المالك؛ يحذف المالك أو العضو نفسه
drop policy if exists members_select on public.company_members;
create policy members_select on public.company_members
  for select using (public.is_company_member(company_id));

drop policy if exists members_insert on public.company_members;
create policy members_insert on public.company_members
  for insert with check (
    user_id = auth.uid()
    or exists (select 1 from public.companies c
               where c.id = company_id and c.owner = auth.uid())
  );

drop policy if exists members_delete on public.company_members;
create policy members_delete on public.company_members
  for delete using (
    user_id = auth.uid()
    or exists (select 1 from public.companies c
               where c.id = company_id and c.owner = auth.uid())
  );

-- company_meta: متاح لأعضاء الشركة
drop policy if exists meta_all on public.company_meta;
create policy meta_all on public.company_meta
  for all
  using (public.is_company_member(company_id))
  with check (public.is_company_member(company_id));

-- assets: متاح لأعضاء الشركة (قراءة/إضافة/تعديل/حذف)
drop policy if exists assets_all on public.assets;
create policy assets_all on public.assets
  for all
  using (public.is_company_member(company_id))
  with check (public.is_company_member(company_id));

-- ============================================================
--  انتهى. ملاحظات:
--  • للسماح بتسجيل دخول فوري بدون تأكيد بريد (للاستخدام الداخلي):
--      Authentication ← Providers ← Email ← أوقف "Confirm email".
--  • مشاركة شركة مع زميل: انسخ "معرّف مساحة العمل" من شاشة الإعدادات
--    وأدخله هو في "الانضمام لمساحة عمل" بعد تسجيل دخوله.
--  • المالك يستطيع إزالة الأعضاء من شاشة الإعدادات.
-- ============================================================
