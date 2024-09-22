WITH ad_data AS (
    SELECT
        utm_source,
        utm_medium,
        utm_campaign,
        utm_content,
        campaign_date,
        daily_spent
    FROM ya_ads
    UNION ALL
    SELECT
        utm_source,
        utm_medium,
        utm_campaign,
        utm_content,
        campaign_date,
        daily_spent
    FROM vk_ads
),

sessions_with_ads AS (
    SELECT
        s.visitor_id,
        s.visit_date,
        l.lead_id,
        l.created_at,
        l.amount,
        l.closing_reason,
        l.status_id,
        COALESCE(a.utm_source, s.source) AS utm_source,
        COALESCE(a.utm_medium, s.medium) AS utm_medium,
        COALESCE(a.utm_campaign, s.campaign) AS utm_campaign
    FROM sessions AS s
    LEFT JOIN ad_data AS a
        ON
            s.source = a.utm_source
            AND s.medium = a.utm_medium
            AND s.campaign = a.utm_campaign
            AND s.visit_date::date = a.campaign_date
    LEFT JOIN leads AS l
        ON
            s.visitor_id = l.visitor_id
            AND s.visit_date <= l.created_at
),

last_paid_clicks AS (
    SELECT DISTINCT ON (visitor_id)
        visitor_id,
        visit_date,
        utm_source,
        utm_medium,
        utm_campaign,
        lead_id,
        created_at,
        amount,
        closing_reason,
        status_id
    FROM sessions_with_ads
    WHERE utm_medium IN ('cpc', 'cpm', 'cpa', 'youtube', 'cpp', 'tg', 'social')
    ORDER BY visitor_id ASC, visit_date DESC
)

SELECT *
FROM last_paid_clicks
ORDER BY
    amount DESC NULLS LAST, visit_date ASC, utm_source ASC, utm_medium ASC, utm_campaign ASC
    LIMIT 10;
