-- 20261113_fix_agency_join_flow.sql
-- Fixes agency join requests not reaching the agency owner:
--   1) Align status CHECK constraints with the statuses the Flutter app writes.
--   2) Auto-create a pending join request from the owner notification
--      (works even on already-installed app versions).
--   3) Backfill pending join requests from existing notifications.

-- 1) Status constraints ------------------------------------------------------
ALTER TABLE public.host_agency_members
  DROP CONSTRAINT IF EXISTS host_agency_members_status_check;
ALTER TABLE public.host_agency_members
  ADD CONSTRAINT host_agency_members_status_check
  CHECK (status = ANY (ARRAY[
    'active','pending','pending_exit','suspended','terminated',
    'kicked','left','rejected'
  ]));

ALTER TABLE public.host_agency_join_requests
  DROP CONSTRAINT IF EXISTS host_agency_join_requests_status_check;
ALTER TABLE public.host_agency_join_requests
  ADD CONSTRAINT host_agency_join_requests_status_check
  CHECK (status = ANY (ARRAY[
    'pending','approved','accepted','rejected','expired','invited'
  ]));

-- 2) Notification -> join request trigger ------------------------------------
CREATE OR REPLACE FUNCTION public.trg_notifications_agency_join_request()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_agency text;
  v_uid    text;
BEGIN
  IF NEW.type IS DISTINCT FROM 'agency_host_request' THEN
    RETURN NEW;
  END IF;

  v_agency := NULLIF(NEW.data->>'agency_id', '');
  v_uid    := COALESCE(NULLIF(NEW.actor_uid, ''), NULLIF(NEW.data->>'applicant_uid', ''));

  IF v_agency IS NULL OR v_uid IS NULL THEN
    RETURN NEW;
  END IF;

  IF NOT EXISTS (SELECT 1 FROM host_agencies WHERE id = v_agency) THEN
    RETURN NEW;
  END IF;

  IF NOT EXISTS (SELECT 1 FROM users WHERE uid = v_uid) THEN
    RETURN NEW;
  END IF;

  IF EXISTS (
    SELECT 1 FROM host_agency_join_requests
    WHERE agency_id = v_agency
      AND (host_uid = v_uid OR user_id = v_uid)
      AND status IN ('pending','invited')
  ) THEN
    RETURN NEW;
  END IF;

  IF EXISTS (
    SELECT 1 FROM host_agency_members
    WHERE agency_id = v_agency
      AND (host_uid = v_uid OR user_id = v_uid)
      AND status = 'active'
  ) THEN
    RETURN NEW;
  END IF;

  INSERT INTO host_agency_join_requests
    (agency_id, host_uid, user_id, status, created_at)
  VALUES
    (v_agency, v_uid, v_uid, 'pending', now());

  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS notifications_agency_join_request ON public.notifications;
CREATE TRIGGER notifications_agency_join_request
AFTER INSERT ON public.notifications
FOR EACH ROW
EXECUTE FUNCTION public.trg_notifications_agency_join_request();

-- 3) Backfill from existing notifications ------------------------------------
INSERT INTO public.host_agency_join_requests
  (agency_id, host_uid, user_id, status, created_at)
SELECT DISTINCT ON (
         n.data->>'agency_id',
         COALESCE(NULLIF(n.actor_uid, ''), n.data->>'applicant_uid'))
       n.data->>'agency_id',
       COALESCE(NULLIF(n.actor_uid, ''), n.data->>'applicant_uid'),
       COALESCE(NULLIF(n.actor_uid, ''), n.data->>'applicant_uid'),
       'pending',
       COALESCE(n.created_at, now())
FROM public.notifications n
WHERE n.type = 'agency_host_request'
  AND n.data ? 'agency_id'
  AND COALESCE(NULLIF(n.actor_uid, ''), n.data->>'applicant_uid') IS NOT NULL
  AND EXISTS (
    SELECT 1 FROM public.host_agencies a
    WHERE a.id = n.data->>'agency_id'
  )
  AND EXISTS (
    SELECT 1 FROM public.users u
    WHERE u.uid = COALESCE(NULLIF(n.actor_uid, ''), n.data->>'applicant_uid')
  )
  AND NOT EXISTS (
    SELECT 1 FROM public.host_agency_join_requests r
    WHERE r.agency_id = n.data->>'agency_id'
      AND (r.host_uid = COALESCE(NULLIF(n.actor_uid, ''), n.data->>'applicant_uid')
           OR r.user_id = COALESCE(NULLIF(n.actor_uid, ''), n.data->>'applicant_uid'))
  )
ORDER BY n.data->>'agency_id',
         COALESCE(NULLIF(n.actor_uid, ''), n.data->>'applicant_uid'),
         n.created_at DESC;

NOTIFY pgrst, 'reload schema';
