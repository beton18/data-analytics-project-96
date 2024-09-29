WITH last_paid_clicks AS (
    SELECT DISTINCT ON (s.visitor_id)
        s.visitor_id,
        s.visit_date,
        s.source AS utm_source,
        s.medium AS utm_medium,
        s.campaign AS utm_campaign,
        l.lead_id,
        l.created_at,
        l.amount,
        l.closing_reason,
        l.status_id
    FROM sessions AS s
    LEFT JOIN leads AS l
        ON
            s.visitor_id = l.visitor_id
            AND s.visit_date <= l.created_at
    WHERE s.medium IN ('cpc', 'cpm', 'cpa', 'youtube', 'cpp', 'tg', 'social')
    ORDER BY s.visitor_id ASC, s.visit_date DESC
)

SELECT *
FROM last_paid_clicks
ORDER BY
    amount DESC NULLS LAST, visit_date ASC, utm_source ASC,
    utm_medium ASC, utm_campaign ASC
LIMIT 10;
