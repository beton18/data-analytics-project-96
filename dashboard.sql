WITH ad_data AS (  -- Собираем данные по рекламным объявлениям из двух таблиц
    SELECT
        utm_source,  -- Источник трафика
        utm_medium,  -- Тип рекламной кампании
        utm_campaign, -- Название кампании
        utm_content,  -- Контент объявления
        campaign_date,  -- Дата расхода на рекламную кампанию
        daily_spent  -- Сколько денег в день потратили на эту рекламу
    FROM ya_ads  -- Рекламные данные из Yandex
    UNION ALL
    SELECT
        utm_source,
        utm_medium,
        utm_campaign,
        utm_content,
        campaign_date,
        daily_spent
    FROM vk_ads  -- Рекламные данные из VK
),
-- Теперь соединим сессии пользователей с рекламными данными и лидами
sessions_with_ads AS (
    SELECT
        s.visit_date::date AS visit_date,  -- Дата визита на сайт (без времени)
        s.visitor_id,  -- Уникальный ID посетителя
        l.lead_id,  -- ID лида, если посетитель сконвертировался в лид
        l.created_at,  -- Когда лид был создан
        l.amount,  -- Сумма сделки
        l.closing_reason,  -- Причина закрытия сделки
        l.status_id,  -- Статус сделки
        a.daily_spent,  -- Сколько денег потратили на рекламу для этой сессии
        COALESCE(a.utm_source, s.source) AS utm_source,  -- Источник трафика с приоритетом рекламы
        COALESCE(a.utm_medium, s.medium) AS utm_medium,  -- Тип рекламной кампании с приоритетом рекламы
        COALESCE(a.utm_campaign, s.campaign) AS utm_campaign  -- Название кампании с приоритетом рекламы
    FROM sessions AS s  -- Таблица сессий пользователей
    LEFT JOIN ad_data AS a  -- Присоединяем рекламные данные, если они есть
        ON s.source = a.utm_source  -- Соединяем по utm_source
        AND s.medium = a.utm_medium  -- Соединяем по utm_medium
        AND s.campaign = a.utm_campaign  -- Соединяем по utm_campaign
        AND s.visit_date::date = a.campaign_date  -- И дата визита должна совпадать с датой кампании
    LEFT JOIN leads AS l  -- Присоединяем данные по лидам
        ON s.visitor_id = l.visitor_id  -- Соединяем по ID посетителя
        AND s.visit_date <= l.created_at  -- Убедимся, что визит был до создания лида или в то же время
),
-- Здесь определяем последние оплаченные клики для каждого пользователя
last_paid_clicks AS (
    SELECT DISTINCT ON (visitor_id)  -- Берем по одному последнему визиту на каждого пользователя
        visit_date,  -- Дата визита
        utm_source,  -- Источник трафика
        utm_medium,  -- Тип рекламной кампании
        utm_campaign,  -- Название рекламной кампании
        visitor_id,  -- ID посетителя
        lead_id,  -- ID лида
        created_at,  -- Когда был создан лид
        amount,  -- Сумма сделки
        closing_reason,  -- Причина закрытия сделки
        status_id,  -- Статус сделки
        daily_spent  -- Сколько денег потратили на эту рекламу
    FROM sessions_with_ads  -- Используем данные сессий и рекламы
    WHERE utm_medium IN ('cpc', 'cpm', 'cpa', 'youtube', 'cpp', 'tg', 'social')  -- Отбираем только платные клики
    ORDER BY visitor_id ASC, visit_date DESC  -- Берем последние визиты по каждому пользователю
)
-- Финальная выборка с расчетами
SELECT
    visit_date,  -- Дата визита
    utm_source,  -- Источник трафика
    utm_medium,  -- Тип рекламной кампании
    utm_campaign,  -- Название кампании
    -- Считаем, сколько визитов с этими метками
    COUNT(visitor_id) AS visitors_count,
    SUM(daily_spent) AS total_cost,  -- Суммируем расходы на рекламу
    -- Считаем количество уникальных лидов
    COUNT(DISTINCT lead_id) AS leads_count,
    COUNT(
        CASE
            -- Если сделка успешна
            WHEN closing_reason = 'Успешно реализовано' OR status_id = 142
                THEN lead_id  -- Учитываем лид
        END
    ) AS purchases_count,  -- Считаем количество успешных сделок
    SUM(
        CASE
            -- Если сделка успешна
            WHEN closing_reason = 'Успешно реализовано' OR status_id = 142
                THEN amount  -- Учитываем сумму сделки
        END
    ) AS revenue,  -- Суммируем выручку по успешным сделкам
    -- Теперь начинаем вычислять метрики:
    CASE
        -- Если посетителей нет, метрики не считаем
        WHEN COUNT(visitor_id) = 0 THEN NULL
        -- CPU = общие затраты / количество визитов
        ELSE SUM(daily_spent) / COUNT(visitor_id)
    END AS cpu,
    CASE
        -- Если лидов нет, не считаем CPL
        WHEN COUNT(DISTINCT lead_id) = 0 THEN NULL
        -- CPL = общие затраты / количество лидов
        ELSE SUM(daily_spent) / COUNT(DISTINCT lead_id)
    END AS cpl,
    CASE
        WHEN COUNT(
            CASE
                -- Если сделка успешна
                WHEN closing_reason = 'Успешно реализовано' OR status_id = 142
                    THEN lead_id
            END
        ) = 0 THEN NULL  -- Если покупок нет, не считаем CPPU
        ELSE SUM(daily_spent) / COUNT(
            CASE
                -- Если сделка успешна
                WHEN closing_reason = 'Успешно реализовано' OR status_id = 142
                    THEN lead_id
            END
        )  -- CPPU = общие затраты / количество успешных сделок
    END AS cppu,
    CASE
        -- Если затраты нулевые, не считаем ROI
        WHEN SUM(daily_spent) = 0 THEN NULL
        ELSE (SUM(
            CASE
                -- Если сделка успешна
                WHEN closing_reason = 'Успешно реализовано' OR status_id = 142
                    THEN amount  -- Берем выручку
            END
        -- ROI = (выручка - затраты) / затраты * 100%
        ) - SUM(daily_spent)) / SUM(daily_spent) * 100
    END AS roi
FROM last_paid_clicks  -- Используем данные последних оплаченных кликов
-- Группируем по дате визита и меткам
GROUP BY visit_date, utm_source, utm_medium, utm_campaign
ORDER BY
    revenue DESC NULLS LAST,  -- Сортируем по выручке (null в конце)
    visit_date ASC,  -- Затем по дате (от ранних к поздним)
    -- Потом по количеству визитов (от большего к меньшему)
    visitors_count DESC,
    -- И в конце по меткам в алфавитном порядке
    utm_source ASC, utm_medium ASC, utm_campaign ASC;
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
--запрос покажет, сколько пользователей заходит на сайт каждый день, и из каких каналов они пришли. В конце добавим итоговую колонку за месяц.
WITH daily_visitors AS (
    SELECT
        visit_date::date AS day,
        source AS utm_source,
        COUNT(DISTINCT visitor_id) AS daily_users
    FROM sessions
    GROUP BY day, utm_source
),
total_monthly_visitors AS (
    SELECT COUNT(DISTINCT visitor_id) AS total_users
    FROM sessions
)
-- Первый запрос: Ежедневный трафик
SELECT
    day,
    utm_source,
    daily_users
FROM daily_visitors
-- Второй запрос: Общая сумма трафика за месяц
UNION ALL
SELECT
    NULL::date AS day,  -- Используем NULL для пустого дня
    'All Sources' AS utm_source,  -- Указываем текст для источника
    SUM(daily_users) AS total_users  -- Считаем сумму по всем дням
FROM daily_visitors;
--считаем количество лидов по дням и каналам
WITH daily_leads AS (
    SELECT
        s.visit_date::date AS day,
        s.source AS utm_source,
        COUNT(DISTINCT l.lead_id) AS daily_leads
    FROM sessions AS s
    LEFT JOIN leads AS l ON s.visitor_id = l.visitor_id
    WHERE l.lead_id IS NOT NULL
    GROUP BY day, utm_source
),
monthly_leads AS (
    SELECT
        s.source AS utm_source,
        COUNT(DISTINCT l.lead_id) AS monthly_leads
    FROM sessions AS s
    LEFT JOIN leads AS l ON s.visitor_id = l.visitor_id
    WHERE l.lead_id IS NOT NULL
    GROUP BY utm_source
)
SELECT
    day,
    utm_source,
    daily_leads
FROM daily_leads
UNION ALL
SELECT
    NULL AS day,  -- Используем NULL вместо строки для суммарного значения
    utm_source,
    monthly_leads AS daily_leads
FROM monthly_leads;
--конверсия из клика в лид и из лида в оплату
WITH conversion_data AS (
    SELECT
        s.visit_date::date AS day,
        s.source AS utm_source,
        COUNT(DISTINCT s.visitor_id) AS visitors_count,
        COUNT(DISTINCT l.lead_id) AS leads_count,
        COUNT(
            DISTINCT CASE WHEN l.status_id = 142 THEN l.lead_id END
        ) AS purchases_count
    FROM sessions AS s
    LEFT JOIN leads AS l ON s.visitor_id = l.visitor_id
    GROUP BY day, utm_source
)
SELECT
    day,
    utm_source,
    leads_count::float / visitors_count AS click_to_lead,
    purchases_count::float / leads_count AS lead_to_purchase
FROM conversion_data
WHERE visitors_count > 0 AND leads_count > 0;
--Посчитаем, сколько тратим на рекламу по дням и каналам
SELECT
    COALESCE(vk.utm_source, ya.utm_source) AS source,
    DATE_TRUNC('month', COALESCE(vk.campaign_date, ya.campaign_date)) AS month,
    SUM(
        COALESCE(vk.daily_spent, 0) + COALESCE(ya.daily_spent, 0)
    ) AS total_spent
FROM vk_ads AS vk
FULL JOIN ya_ads AS ya
    ON
        vk.utm_source = ya.utm_source
        AND vk.utm_campaign = ya.utm_campaign
        AND vk.campaign_date = ya.campaign_date
GROUP BY source, month
ORDER BY month ASC, total_spent DESC;

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
