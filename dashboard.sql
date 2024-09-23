-- Формируем дашборд для маркетинговой команды на основе запроса для aggregate_last_paid_click.
-- Результат по aggregate_last_paid_click проверяется автоматически,
-- а значит дашборд, составленный на основе этого запроса, будет корректен.

-- Подзапрос visitors_and_leads получает уникальные визиты пользователей с данными о лидах
WITH visitors_and_leads AS (
    SELECT DISTINCT ON (s.visitor_id)  -- Убираем дубли по visitor_id, берём последний визит
        s.visitor_id,                  -- ID посетителя
        s.visit_date,                  -- Дата визита
        s.source AS utm_source,        -- UTM-источник
        s.medium AS utm_medium,        -- UTM-тип трафика (cpc, cpm и т.д.)
        s.campaign AS utm_campaign,    -- UTM-кампания
        l.lead_id,                     -- ID лида, если есть
        l.amount,                      -- Сумма лида
        l.created_at,                  -- Дата создания лида
        l.status_id                     -- Статус лида (например, покупка)
    FROM sessions AS s
    LEFT JOIN leads AS l
        ON s.visitor_id = l.visitor_id   -- Привязываем лиды к визитам
        AND s.visit_date <= l.created_at  -- Только если визит был до или в момент создания лида
    WHERE s.medium IN ('cpc', 'cpm', 'cpa', 'youtube', 'cpp', 'tg', 'social')  -- Ограничиваем типы трафика
    ORDER BY 1, 2 DESC  -- Сортируем по visitor_id и дате визита (для distinct)
),

-- Подзапрос costs собирает расходы по рекламным кампаниям из двух таблиц
costs AS (
    SELECT
        campaign_date::date,      -- Дата кампании
        SUM(daily_spent) AS daily_spent,  -- Общие расходы за день
        utm_source,               -- UTM-источник
        utm_medium,               -- UTM-тип трафика
        utm_campaign               -- UTM-кампания
    FROM vk_ads  -- Таблица расходов ВК
    GROUP BY 1, 3, 4, 5  -- Группируем по дате, источнику, типу трафика и кампании

    UNION ALL

    SELECT
        campaign_date::date,      -- Аналогично для яндекс-рекламы
        SUM(daily_spent) AS daily_spent,
        utm_source,
        utm_medium,
        utm_campaign
    FROM ya_ads  -- Таблица расходов Яндекс
    GROUP BY 1, 3, 4, 5
)

-- Основной запрос, соединяющий данные визитов с расходами и считающий метрики
SELECT
    vl.visit_date::date,                       -- Дата визита
    COUNT(*) AS visitors_count,                 -- Количество визитов
    vl.utm_source,                              -- UTM-источник
    vl.utm_medium,                              -- UTM-тип трафика
    vl.utm_campaign,                            -- UTM-кампания
    daily_spent AS total_cost,                 -- Общие расходы на рекламу в этот день
    COUNT(*) FILTER (WHERE lead_id IS NOT NULL) AS leads_count,  -- Количество лидов
    COUNT(*) FILTER (WHERE status_id = 142) AS purchases_count,   -- Количество покупок (лиды со статусом покупки)
    COALESCE(SUM(amount) FILTER (WHERE status_id = 142), 0) AS revenue,  -- Доход от покупок
    CASE 
        WHEN COUNT(*) > 0 THEN daily_spent / COUNT(*) 
    END AS cpu,  -- Стоимость за уникального посетителя
    CASE 
        WHEN COUNT(*) FILTER (WHERE lead_id IS NOT NULL) > 0 
        THEN daily_spent / COUNT(*) FILTER (WHERE lead_id IS NOT NULL) 
    END AS cpl,  -- Стоимость за лид
    CASE 
        WHEN COUNT(*) FILTER (WHERE status_id = 142) > 0 
        THEN daily_spent / COUNT(*) FILTER (WHERE status_id = 142) 
    END AS cppu,  -- Стоимость за покупку
    CASE 
        WHEN daily_spent > 0 
        THEN (COALESCE(SUM(amount) FILTER (WHERE status_id = 142), 0) - daily_spent) / daily_spent * 100 
    END AS roi  -- ROI
FROM visitors_and_leads AS vl
LEFT JOIN costs AS c  -- Левый джойн с таблицей расходов
    ON vl.utm_source = c.utm_source   -- По UTM-источнику
    AND vl.utm_medium = c.utm_medium   -- По типу трафика
    AND vl.utm_campaign = c.utm_campaign  -- По кампании
    AND vl.visit_date::date = c.campaign_date::date  -- И по дате
GROUP BY 1, 3, 4, 5, 6  -- Группируем по дате, источнику, типу трафика, кампании и расходам
ORDER BY revenue DESC NULLS LAST, visitors_count DESC, vl.visit_date, vl.utm_source, vl.utm_medium, vl.utm_campaign;  -- Сортируем сначала по доходу, затем по количеству визитов

-- Находим затраты на рекламу по дням
SELECT
    campaign_date::date AS day,
    'VK' AS source,
    SUM(daily_spent) AS total_spent
FROM vk_ads
GROUP BY day

UNION ALL

SELECT
    campaign_date::date AS day,
    'Yandex' AS source,
    SUM(daily_spent) AS total_spent
FROM ya_ads
GROUP BY day
ORDER BY day, source;
