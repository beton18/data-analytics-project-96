--Формируем дашборд для маркетинговой команды на основе запроса для aggregate_last_paid_click. Результат по aggregate_last_paid_click проверяется автоматически, а значит дашборд, составленный на основе этого запроса будет корректен
-- Подзапрос visitors_and_leads получает уникальные визиты пользователей с данными о лидах
with visitors_and_leads as (
    select distinct on (s.visitor_id)  -- Убираем дубли по visitor_id, берём последний визит
        s.visitor_id,  -- ID посетителя
        s.visit_date,  -- Дата визита
        s.source as utm_source,  -- UTM-источник
        s.medium as utm_medium,  -- UTM-тип трафика (cpc, cpm и т.д.)
        s.campaign as utm_campaign,  -- UTM-кампания
        l.lead_id,  -- ID лида, если есть
        l.amount,  -- Сумма лида
        l.created_at,  -- Дата создания лида
        l.status_id  -- Статус лида (например, покупка)
    from sessions as s
    left join leads as l
        on
            s.visitor_id = l.visitor_id  -- Привязываем лиды к визитам
            and s.visit_date <= l.created_at  -- Только если визит был до или в момент создания лида
    where s.medium in ('cpc', 'cpm', 'cpa', 'youtube', 'cpp', 'tg', 'social')  -- Ограничиваем типы трафика
    order by 1, 2 desc  -- Сортируем по visitor_id и дате визита (для distinct)
),

-- Подзапрос costs собирает расходы по рекламным кампаниям из двух таблиц
costs as (
    select
        campaign_date::date,  -- Дата кампании
        SUM(daily_spent) as daily_spent,  -- Общие расходы за день
        utm_source,  -- UTM-источник
        utm_medium,  -- UTM-тип трафика
        utm_campaign  -- UTM-кампания
    from vk_ads  -- Таблица расходов ВК
    group by 1, 3, 4, 5  -- Группируем по дате, источнику, типу трафика и кампании
    union all
    select
        campaign_date::date,  -- Аналогично для яндекс-рекламы
        SUM(daily_spent) as daily_spent,
        utm_source,
        utm_medium,
        utm_campaign
    from ya_ads  -- Таблица расходов Яндекс
    group by 1, 3, 4, 5
)

-- Основной запрос, соединяющий данные визитов с расходами и считающий метрики
select
    vl.visit_date::date,  -- Дата визита
    COUNT(*) as visitors_count,  -- Количество визитов
    vl.utm_source,  -- UTM-источник
    vl.utm_medium,  -- UTM-тип трафика
    vl.utm_campaign,  -- UTM-кампания
    daily_spent as total_cost,  -- Общие расходы на рекламу в этот день
    COUNT(*) filter (where lead_id is not NULL) as leads_count,  -- Количество лидов
    COUNT(*) filter (where status_id = 142) as purchases_count,  -- Количество покупок (лиды со статусом покупки)
    COALESCE(SUM(amount) filter (where status_id = 142), 0) as revenue,  -- Доход от покупок
    CASE WHEN COUNT(*) > 0 THEN daily_spent / COUNT(*) END as cpu,  -- Стоимость за уникального посетителя
    CASE WHEN COUNT(*) filter (where lead_id is not NULL) > 0 THEN daily_spent / COUNT(*) filter (where lead_id is not NULL) END as cpl,  -- Стоимость за лид
    CASE WHEN COUNT(*) filter (where status_id = 142) > 0 THEN daily_spent / COUNT(*) filter (where status_id = 142) END as cppu,  -- Стоимость за покупку
    CASE WHEN daily_spent > 0 THEN (COALESCE(SUM(amount) filter (where status_id = 142), 0) - daily_spent) / daily_spent * 100 END as roi  -- ROI
from visitors_and_leads as vl
left join costs as c  -- Левый джойн с таблицей расходов
    on
        vl.utm_source = c.utm_source  -- По UTM-источнику
        and vl.utm_medium = c.utm_medium  -- По типу трафика
        and vl.utm_campaign = c.utm_campaign  -- По кампании
        and vl.visit_date::date = c.campaign_date::date  -- И по дате
group by 1, 3, 4, 5, 6  -- Группируем по дате, источнику, типу трафика, кампании и расходам
order by 9 desc nulls last, 2 desc, 1, 3, 4, 5;  -- Сортируем сначала по доходу, затем по количеству визитов

--Формируем самые дорогие рекламные кампании рекламные кампании
WITH ad_data AS (
    -- Собираем данные из таблиц с рекламой
    SELECT
        utm_source,
        utm_medium,
        utm_campaign,
        utm_content,
        campaign_date,
        -- считаем общие затраты по каждой рекламе
        SUM(daily_spent) AS total_cost
    FROM ya_ads
    GROUP BY utm_source, utm_medium, utm_campaign, utm_content, campaign_date
    UNION ALL
    SELECT
        utm_source,
        utm_medium,
        utm_campaign,
        utm_content,
        campaign_date,
        SUM(daily_spent) AS total_cost
    FROM vk_ads
    GROUP BY utm_source, utm_medium, utm_campaign, utm_content, campaign_date
)
-- Выводим все уникальные рекламные кампании
SELECT
    utm_source,      -- источник (например, Яндекс, ВК)
    utm_medium,      -- тип рекламы (CPC, CPM, etc)
    utm_campaign,    -- название кампании
    SUM(total_cost) AS total_spent -- общие затраты на кампанию
FROM ad_data
GROUP BY utm_source, utm_medium, utm_campaign
-- сортируем по затратам, чтобы понять, какие самые дорогие
ORDER BY total_spent DESC;
--Сравниваем roi, cppu, cpl, cpu по utm_source, utm_campaign, и utm_medium 
WITH visitors_and_leads AS (
    -- Достаем уникальных посетителей и лидов
    SELECT DISTINCT ON (s.visitor_id)
        s.visitor_id,
        s.visit_date,
        s.source AS utm_source,
        s.medium AS utm_medium,
        s.campaign AS utm_campaign,
        l.lead_id,
        l.amount,
        l.created_at,
        l.status_id
    FROM sessions AS s
    LEFT JOIN leads AS l
        ON s.visitor_id = l.visitor_id
        AND s.visit_date <= l.created_at
    WHERE s.medium IN ('cpc', 'cpm', 'cpa', 'youtube', 'cpp', 'tg', 'social')
    ORDER BY s.visitor_id, s.visit_date DESC
),
costs AS (
    -- Собираем затраты на рекламу из всех источников
    SELECT
        campaign_date::date,
        SUM(daily_spent) AS daily_spent,
        utm_source,
        utm_medium,
        utm_campaign
    FROM vk_ads
    GROUP BY campaign_date::date, utm_source, utm_medium, utm_campaign
    UNION ALL
    SELECT
        campaign_date::date,
        SUM(daily_spent) AS daily_spent,
        utm_source,
        utm_medium,
        utm_campaign
    FROM ya_ads
    GROUP BY campaign_date::date, utm_source, utm_medium, utm_campaign
),
results AS (
    -- Собираем итоговые данные
    SELECT
        vl.visit_date::date,
        COUNT(*) AS visitors_count,
        vl.utm_source,
        vl.utm_medium,
        vl.utm_campaign,
        COALESCE(c.daily_spent, 0) AS total_cost,
        COUNT(*) FILTER (WHERE vl.lead_id IS NOT NULL) AS leads_count,
        COUNT(*) FILTER (WHERE vl.status_id = 142) AS purchases_count,
        COALESCE(SUM(vl.amount) FILTER (WHERE vl.status_id = 142), 0) AS revenue
    FROM visitors_and_leads AS vl
    LEFT JOIN costs AS c
        ON vl.utm_source = c.utm_source
        AND vl.utm_medium = c.utm_medium
        AND vl.utm_campaign = c.utm_campaign
        AND vl.visit_date::date = c.campaign_date::date
    GROUP BY vl.visit_date::date, vl.utm_source, vl.utm_medium, vl.utm_campaign, c.daily_spent
    ORDER BY revenue DESC NULLS LAST, visitors_count DESC, vl.visit_date::date, vl.utm_source, vl.utm_medium, vl.utm_campaign
)
-- Вывод итогов с фильтром на нулевые значения метрик
SELECT
    vl.utm_source, -- Разделяем по источникам
    vl.utm_medium, -- Разделяем по типу кампании
    vl.utm_campaign, -- Разделяем по конкретным кампаниям
    ROUND(COALESCE(SUM(total_cost), 0) / NULLIF(SUM(visitors_count), 0), 2) AS cpu, -- Стоимость привлечения пользователя
    ROUND(COALESCE(SUM(total_cost), 0) / NULLIF(SUM(leads_count), 0), 2) AS cpl, -- Стоимость лида
    ROUND(COALESCE(SUM(total_cost), 0) / NULLIF(SUM(purchases_count), 0), 2) AS cppu, -- Стоимость покупки
    ROUND((SUM(revenue) - SUM(total_cost)) / NULLIF(SUM(total_cost), 0) * 100, 2) AS roi -- ROI
FROM results AS vl
GROUP BY vl.utm_source, vl.utm_medium, vl.utm_campaign
HAVING
    COALESCE(ROUND(COALESCE(SUM(total_cost), 0) / NULLIF(SUM(visitors_count), 0), 2), 0) > 0
    OR COALESCE(ROUND(COALESCE(SUM(total_cost), 0) / NULLIF(SUM(leads_count), 0), 2), 0) > 0
    OR COALESCE(ROUND(COALESCE(SUM(total_cost), 0) / NULLIF(SUM(purchases_count), 0), 2), 0) > 0
    OR COALESCE(ROUND((SUM(revenue) - SUM(total_cost)) / NULLIF(SUM(total_cost), 0) * 100, 2), 0) > 0
ORDER BY vl.utm_source, vl.utm_medium, vl.utm_campaign;
--Находим затраты на рекламу по дням
-- Суммируем затраты по VK за каждый день
SELECT
    campaign_date AS day,
    'VK' AS source,
    SUM(daily_spent) AS total_spent
FROM vk_ads
GROUP BY day
UNION ALL
SELECT
    campaign_date AS day,
    'Yandex' AS source,
    SUM(daily_spent) AS total_spent
FROM ya_ads
GROUP BY day
ORDER BY day, source;
--считаем окупаемость каналов (roi) (скорее всего неправильно)
WITH a AS (
    SELECT
        campaign_date::date AS campaign_date,
        utm_source,
        daily_spent
    FROM ya_ads
    UNION ALL
    SELECT
        campaign_date::date AS campaign_date,
        utm_source,
        daily_spent
    FROM vk_ads
),
revenue_and_costs AS (
    SELECT
        s.visit_date::date AS day,
        s.source AS utm_source,
        COALESCE(SUM(l.amount), 0) AS revenue,
        COALESCE(SUM(a.daily_spent), 0) AS total_cost
    FROM sessions AS s
    LEFT JOIN leads AS l ON s.visitor_id = l.visitor_id
    LEFT JOIN a
        ON
            s.source = a.utm_source
            AND s.visit_date::date = a.campaign_date::date
    GROUP BY day, s.source
),
roi_calculation AS (
    SELECT
        utm_source,
        SUM(total_cost) AS total_cost,
        SUM(revenue) AS total_revenue,
        CASE
            WHEN
                SUM(total_cost) > 0
                THEN
                    ROUND(
                        (SUM(revenue) - SUM(total_cost))
                        / SUM(total_cost)
                        * 100,
                        2
                    )
        END AS roi
    FROM revenue_and_costs
    GROUP BY utm_source
)
SELECT
    utm_source,
    total_cost,
    total_revenue,
    roi
FROM roi_calculation
WHERE total_cost > 0;
--запрос для формирования воронки в preset
WITH channel_data AS (
    SELECT
        -- Количество уникальных пользователей
        COUNT(DISTINCT s.visitor_id) AS total_visitors,
        -- Количество уникальных лидов
        COUNT(DISTINCT l.lead_id) AS total_leads,
        -- Покупки (статус сделки "успех")
        COUNT(
            DISTINCT CASE WHEN l.status_id = 142 THEN l.lead_id END
        ) AS total_purchases
    FROM sessions AS s
    LEFT JOIN leads AS l ON s.visitor_id = l.visitor_id
)
SELECT
    total_visitors,    -- Количество пользователей
    total_leads,       -- Количество лидов
    total_purchases    -- Количество покупок
FROM channel_data;
