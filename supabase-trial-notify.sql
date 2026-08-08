-- SALON-TRACK already had: 30-day no-approval trial, signup Telegram alert,
-- admin-mediated PIN reset, admin extend-trial. Two things from the standard
-- commercialization pattern were missing:
--   1. a Telegram alert when a trial actually STARTS (first data entry via
--      activateTrialIfNeeded()), separate from the signup alert
--   2. a 3-day-before-expiry reminder (this app has no user email on file,
--      only mobile/WhatsApp, so it's an admin-facing nudge to reach out --
--      matches the existing admin-mediated forgot-PIN design)
-- Implemented server-side via trigger + pg_cron (same shared worker already
-- used client-side by tg(), and the same pg_net pattern proven in reminder's
-- supabase-trial-notify.sql) rather than threading tg() into the three
-- activateTrialIfNeeded() call sites, so it fires no matter which path sets
-- expiry_date.

alter table users add column if not exists trial_reminder_sent boolean not null default false;

create or replace function public.st_notify_trial_started() returns trigger
language plpgsql
security definer
set search_path to 'public', 'extensions'
as $function$
begin
  if NEW.expiry_date is not null and OLD.expiry_date is null and NEW.plan = 'trial' then
    perform net.http_post(
      url := 'https://telegram-notify.unigoods2026.workers.dev/',
      headers := '{"Content-Type":"application/json"}'::jsonb,
      body := jsonb_build_object(
        'msg', '🎯 <b>SALON-TRACK trial started</b>' || chr(10) ||
          'Shop: ' || coalesce(NEW.shop,'') || chr(10) ||
          'Owner: ' || coalesce(NEW.name,'') || chr(10) ||
          'Mobile: ' || coalesce(NEW.mobile,'') || chr(10) || chr(10) ||
          '30-day trial clock is now running.'
      )
    );
  end if;
  return NEW;
end;
$function$;

drop trigger if exists users_notify_trial_started on users;
create trigger users_notify_trial_started
after update on users
for each row execute function st_notify_trial_started();

-- ---------- 3-day-before-expiry reminder (admin-facing) ----------
create or replace function public.st_send_trial_ending_reminders() returns void
language plpgsql
security definer
set search_path to 'public', 'extensions'
as $function$
declare v_user record; v_days_left int;
begin
  for v_user in
    select * from users
    where plan = 'trial' and is_active = true and trial_reminder_sent = false
      and expiry_date is not null
  loop
    v_days_left := v_user.expiry_date - current_date;
    if v_days_left = 3 then
      perform net.http_post(
        url := 'https://telegram-notify.unigoods2026.workers.dev/',
        headers := '{"Content-Type":"application/json"}'::jsonb,
        body := jsonb_build_object(
          'msg', '⏳ <b>Trial ends in 3 days</b>' || chr(10) ||
            'Shop: ' || coalesce(v_user.shop,'') || chr(10) ||
            'Owner: ' || coalesce(v_user.name,'') || chr(10) ||
            'Mobile: ' || coalesce(v_user.mobile,'') || chr(10) || chr(10) ||
            'Reach out to extend their trial or move them to a paid plan.'
        )
      );
      update users set trial_reminder_sent = true where id = v_user.id;
    end if;
  end loop;
end;
$function$;

select cron.schedule(
  'st-trial-ending-reminders',
  '0 9 * * *',
  $$select st_send_trial_ending_reminders();$$
);

-- Reset the reminder flag whenever admin extends a trial, so it can fire again
create or replace function public.st_admin_extend_trial(p_id uuid, p_start date, p_expiry date, p_password text)
returns boolean
language plpgsql
security definer
set search_path to 'public', 'extensions'
as $function$
begin
  if not st_admin_check_password(p_password) then raise exception 'Unauthorized'; end if;
  update users set start_date = p_start, expiry_date = p_expiry, plan = 'trial', trial_reminder_sent = false where id = p_id;
  return true;
end;
$function$;
