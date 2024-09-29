-- Подзапрос visitors_and_leads получает уникальные 
-- визиты пользователей с данными о лидах
WITH visitors_and_leads AS (
    SELECT DISTINCT ON (s.visitor_id) -- убираем дубли
        s.visitor_id,  -- ID посетителя
        s.visit_date,  -- Дата визита
        s.source AS utm_source,  -- UTM-источник
        s.medium AS utm_medium,  -- UTM-тип трафика (cpc, cpm и т.д.)
        s.campaign AS utm_campaign,  -- UTM-кампания
        l.lead_id,  -- ID лида, если есть
        l.amount,  -- Сумма лида
        l.created_at,  -- Дата создания лида
        l.status_id  -- Статус лида (например, покупка)
    FROM sessions AS s
    LEFT JOIN leads AS l
        ON
            s.visitor_id = l.visitor_id  -- Привязываем лиды к визитам
            AND s.visit_date <= l.created_at
    WHERE s.medium IN ('cpc', 'cpm', 'cpa', 'youtube', 'cpp', 'tg', 'social')
    ORDER BY 1, 2 DESC  -- Сортируем по visitor_id и дате визита (для distinct)
),

-- Подзапрос costs собирает расходы по рекламным кампаниям из двух таблиц
costs AS (
    SELECT
        campaign_date::date,  -- Дата кампании
        SUM(daily_spent) AS daily_spent,  -- Общие расходы за день
        utm_source,  -- UTM-источник
        utm_medium,  -- UTM-тип трафика
        utm_campaign  -- UTM-кампания
    FROM vk_ads  -- Таблица расходов ВК
    GROUP BY 1, 3, 4, 5--Группируем по дате, источнику, типу трафика и кампании
    UNION ALL
    SELECT
        campaign_date::date,  -- Аналогично для яндекс-рекламы
        SUM(daily_spent) AS daily_spent,
        utm_source,
        utm_medium,
        utm_campaign
    FROM ya_ads  -- Таблица расходов Яндекс
    GROUP BY 1, 3, 4, 5
)

-- Соединяем данные визитов с расходами и считаем метрики
SELECT
    vl.visit_date::date,  -- Дата визита
    vl.utm_source,  -- UTM-источник
    vl.utm_medium,  -- UTM-тип трафика
    vl.utm_campaign,  -- UTM-кампания
    c.daily_spent AS total_cost, -- Общие расходы на рекламу
    COUNT(*) AS visitors_count,  -- Количество визитов
    COUNT(*) FILTER (WHERE vl.lead_id IS NOT NULL) AS leads_count,
    COUNT(*) FILTER (WHERE vl.status_id = 142) AS purchases_count,
    COALESCE(SUM(vl.amount) FILTER (WHERE vl.status_id = 142), 0) AS revenue
FROM visitors_and_leads AS vl
LEFT JOIN costs AS c  -- Левый джойн с таблицей расходов
    ON
        vl.utm_source = c.utm_source  -- По UTM-источнику
        AND vl.utm_medium = c.utm_medium  -- По типу трафика
        AND vl.utm_campaign = c.utm_campaign  -- По кампании
        AND vl.visit_date::date = c.campaign_date::date  -- И по дате
GROUP BY 1, 2, 3, 4, 5
-- Группируем по дате, источнику, типу трафика, кампании и расходам
ORDER BY 9 DESC NULLS LAST, 6 DESC, 1, 2, 3, 4
-- Сортируем сначала по доходу, затем по количеству визитов
LIMIT 15; -- Лимитируем результат
