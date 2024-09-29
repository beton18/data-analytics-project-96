-- Формируем дашборд для маркетинговой команды на основе запроса для
-- aggregate_last_paid_click.
-- Результат по aggregate_last_paid_click проверяется автоматически,
-- а значит дашборд, составленный
-- на основе этого запроса будет корректен
-- Подзапрос visitors_and_leads получает уникальные
-- визиты пользователей с данными о лидах
with visitors_and_leads as (
    select distinct on (s.visitor_id)
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
            and s.visit_date <= l.created_at
    -- Только если визит был до или в момент создания лида
    where s.medium in ('cpc', 'cpm', 'cpa', 'youtube', 'cpp', 'tg', 'social')
    -- Ограничиваем типы трафика
    order by 1, 2 desc  -- Сортируем по visitor_id и дате визита (для distinct)
),

-- Подзапрос costs собирает расходы по рекламным кампаниям из двух таблиц
costs as (
    select
        campaign_date::date as campaign_date,  -- Дата кампании
        sum(daily_spent) as daily_spent,  -- Общие расходы за день
        utm_source,  -- UTM-источник
        utm_medium,  -- UTM-тип трафика
        utm_campaign  -- UTM-кампания
    from vk_ads  -- Таблица расходов ВК
    group by campaign_date::date, utm_source, utm_medium, utm_campaign

    union all

    select
        campaign_date::date as campaign_date,  -- Аналогично для яндекс-рекламы
        sum(daily_spent) as daily_spent,
        utm_source,
        utm_medium,
        utm_campaign
    from ya_ads  -- Таблица расходов Яндекс
    group by campaign_date::date, utm_source, utm_medium, utm_campaign
)

-- Основной запрос, соединяющий данные визитов с расходами и считающий метрики
select
    vl.visit_date::date as visit_date,  -- Дата визита
    vl.utm_source,  -- UTM-источник
    vl.utm_medium,  -- UTM-тип трафика
    vl.utm_campaign,  -- UTM-кампания
    c.daily_spent as total_cost,  -- Общие расходы на рекламу в этот день
    count(*) as visitors_count,  -- Количество визитов
    count(*) filter (where vl.lead_id is not null) as leads_count,  -- Количество лидов
    count(*) filter (where vl.status_id = 142) as purchases_count,  -- Количество покупок
    coalesce(sum(vl.amount) filter (where vl.status_id = 142), 0) as revenue  -- Доход от покупок
from visitors_and_leads as vl
left join costs as c  -- Левый джойн с таблицей расходов
    on
        vl.utm_source = c.utm_source  -- По UTM-источнику
        and vl.utm_medium = c.utm_medium  -- По типу трафика
        and vl.utm_campaign = c.utm_campaign  -- По кампании
        and vl.visit_date::date = c.campaign_date  -- И по дате
group by
    vl.visit_date::date,
    vl.utm_source,
    vl.utm_medium,
    vl.utm_campaign,
    c.daily_spent
order by
    revenue desc nulls last,
    visitors_count desc,
    visit_date asc,
    vl.utm_source asc,
    vl.utm_medium asc,
    vl.utm_campaign asc;

-- Находим затраты на рекламу по дням
select
    campaign_date::date as campaign_day,
    'VK' as ad_source,
    sum(daily_spent) as total_spent
from vk_ads
group by campaign_date::date

union all

select
    campaign_date::date as campaign_day,
    'Yandex' as ad_source,
    sum(daily_spent) as total_spent
from ya_ads
group by campaign_date::date
order by campaign_day asc, ad_source asc;
