-- Allow 'other' kind in report_wallpaper RPC (entry point global from Profile).
CREATE OR REPLACE FUNCTION public.report_wallpaper(
    p_wallpaper_id    text,
    p_wallpaper_kind  text,
    p_reason          text,
    p_description     text DEFAULT NULL,
    p_reporter_id     text DEFAULT NULL,
    p_reporter_email  text DEFAULT NULL,
    p_wallpaper_meta  jsonb DEFAULT NULL
)
RETURNS uuid
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_id uuid;
BEGIN
    IF p_reason NOT IN ('sexual', 'violence', 'hate', 'copyright', 'drugs', 'spam', 'other') THEN
        RAISE EXCEPTION 'invalid reason: %', p_reason;
    END IF;

    IF p_wallpaper_kind NOT IN ('static', 'live', 'canvas_scene', 'ai_generated', 'panoramic', 'story', 'tone', 'other') THEN
        RAISE EXCEPTION 'invalid wallpaper_kind: %', p_wallpaper_kind;
    END IF;

    IF p_reporter_id IS NOT NULL THEN
        SELECT id INTO v_id
        FROM public.wallpaper_reports
        WHERE wallpaper_id = p_wallpaper_id
          AND reporter_id  = p_reporter_id
          AND reported_at > now() - interval '24 hours'
        LIMIT 1;

        IF v_id IS NOT NULL THEN
            RETURN v_id;
        END IF;
    END IF;

    INSERT INTO public.wallpaper_reports (
        wallpaper_id, wallpaper_kind, reason, description,
        reporter_id, reporter_email, wallpaper_meta
    ) VALUES (
        p_wallpaper_id, p_wallpaper_kind, p_reason, p_description,
        p_reporter_id, p_reporter_email, p_wallpaper_meta
    )
    RETURNING id INTO v_id;

    RETURN v_id;
END;
$$;
