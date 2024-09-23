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
--Находим затраты на рекламу по дням
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

