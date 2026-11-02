---- Day 1 ----
--Q1,. Deduplication
--Write a query to return each distinct order_id along with its latest status based on updated_at.

with A as (
select order_id,status, row_number() over (partition by order_id order by updated_at desc) rw_no from order_updates)

select order_id, status from A where rw_no =1 ;


--Q2: Deterministic Tie-Breaking
-- order_id = 102 has two events with the identical updated_at timestamp ('2026-03-01 14:00:00.500000').
--Update your query so ties on updated_at are resolved deterministically by picking the highest update_id

select * from order_updates ou 

select * from (
select order_id, status, updated_at, row_number()over (partition by order_id order by updated_at desc, update_id desc) as rn
from order_updates ou ) AB where AB.rn =1

--Q3: Prompt: For order_id = 103, the earliest event had status = NULL before becoming DELIVERED.
--Requirement: Write a query that returns the latest non-null status for every order.
--Condition: If an order’s latest record contains a NULL status, your query must look backward and return the most recent status that is not NULL.


select * from (
select order_id,status,row_number() over (partition by order_id order by updated_at desc) rw_no from order_updates
where status is not null )BH where BH.rw_no =1



--Q4: Prompt: Without running it first, consider what happens if you substitute ROW_NUMBER() with RANK() or DENSE_RANK() ordered by updated_at DESC on order_id = 102 and filter by WHERE rnk = 1.

--Task: Run the query using RANK() in DBeaver and explain why this behavior causes silent data duplication bugs in production reporting.

select * from (
select order_id,status,updated_at,dense_rank() over (partition by order_id order by updated_at desc) rw_no from order_updates
where status is not null )BH where BH.rw_no =1

-- Both Rank and dense rank create duplicates as it ranks based on rank instead of rows, wherever the updated_at rows are same the ranks are same and hence fails.

--Q5: Prompt: Write a query that returns each order's current status alongside its immediately preceding status.

--Target Columns: order_id, current_status, current_updated_at, previous_status, previous_updated_at

--Requirement: Combine window deduplication with LAG(). If an order has only ever had one update, previous_status should display as NULL.

select * from (
select order_id,status as current_status,updated_at as current_updated_at,
lag(status) over (partition by order_id order by updated_at) as previous_status,
lag(updated_at) over (partition by order_id order by updated_at) as previous_updated_at,
row_number() over (partition by order_id order by updated_at desc) rw_no

--lag(status) over (order by updated_at desc) as previous_updated_at
from order_updates) BHJ where BHJ.rw_no =1



--------------------------------------- Day 2 ----------------------------------------------




-Question 1: Cumulative Running Revenue
--Prompt: Calculate the cumulative running total of gross_revenue over time for each region.

--Target Columns: region, order_date, gross_revenue, running_total_revenue

--Requirement: The running total must reset for each region and accumulate chronologically by order_date.

--Concept Check: Ensure you explicitly understand the default frame specification (RANGE BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW vs. ROWS BETWEEN).

--- concepts ---
rows between unbounded preceding and current row
rows between 1 preceding and current row
range between interval '1 day' preceding and current row

--range aggrgates the sum for that partiuclar date (02/20, 02/30, i.e. 02=50(30+20) total for both rows)

---by default its range between unbounded preceding and current row: 



select * from daily_revenue ;

select region, order_date, gross_revenue, 

from daily_revenue


select region, order_date, gross_revenue, 
sum(gross_revenue) over (partition by region order by order_date rows between unbounded preceding and current row) as running_total_rev_rows,
sum(gross_revenue) over (partition by region order by order_date range between unbounded preceding and current row ) as running_range_rev
from daily_revenue

--Question 2: The Naive Trailing 7-Day Moving Average (The Trap)
--Prompt: Write a query using AVG(gross_revenue) OVER (PARTITION BY region ORDER BY order_date ROWS BETWEEN 6 PRECEDING AND CURRENT ROW).

--Task: Run this query and inspect the output for region NA.

--Question to Answer: Why is ROWS BETWEEN 6 PRECEDING AND CURRENT ROW statistically incorrect for calculating a true "trailing 7-day average" when there are missing calendar dates in your table?

select region, order_date, gross_revenue, 
avg(gross_revenue) over (partition by region order by order_date range between interval '7 days' preceding and current row ) as moving_avg_7day_range,
avg(gross_revenue) over (partition by region order by order_date rows between 6 preceding and current row ) as moving_avg_7day_row
from daily_revenue

--rows is statistically incorrect here because it's calculating not the last 7 days but 8 days, since 03/03 is missing 7 rows. 
--For ex. 03/10 would caculate till 03/02 but technically it should look only till 03/07

--Question 3: Continuous Calendar Spine (The Production Solution)Prompt: To calculate a true rolling 7-day average, missing dates must be filled with 0 revenue.
--Requirement:Generate a continuous date spine for every date between '2026-03-01' and '2026-03-10'.
--Produce a Cartesian grid of all distinct regions (NA, EU) $\times$ all generated dates.LEFT JOIN the daily_revenue data so missing days show as 0.00 revenue.
--Compute the true trailing 7-day moving average (inclusive of the current day) per region.
--Target Columns: region, calendar_date, daily_revenue, trailing_7d_avg_revenue (rounded to 2 decimal places).

with A as (select d::date as day from generate_series('2026-03-01'::date,'2026-03-10'::date, interval '1 day' ) as d)

, B as (select distinct region from   daily_revenue)

, Q as (select A.day,B.region from A cross join B)

, C as (select Q.region, Q.day as order_date, coalesce(gross_revenue, 0) as gross_revenue from daily_revenue dr right join Q  on dr.order_date =Q.day and dr.region =Q.region) 

select C.region, order_date, gross_revenue, 
avg(gross_revenue) over (partition by C.region order by order_date range between interval '6 days' preceding and current row ) as moving_avg_7day_range
from C

--Question 4: Period-Over-Period (Day-over-Day & Trailing Day Growth)
--Prompt: Using your dense calendar data from Question 3:
--Requirement: Calculate the Day-over-Day (DoD) absolute revenue change and the DoD percentage change for each region.
--Target Columns: region, calendar_date, daily_revenue, previous_day_revenue, dod_absolute_diff, dod_pct_changeEdge 
--Case Check: Handle division by zero cleanly when the previous day had 0.00 revenue (use NULLIF or CASE).

with A1 as (select d::date as day from generate_series('2026-03-01'::date,'2026-03-10'::date, interval '1 day') d),
B1 as (select distinct region from daily_revenue dr ),
C1 as (select A1.day, B1.region from A1 cross join B1 ),

D as (select C1.region, C1.day as order_date, coalesce(dr.gross_revenue,0) as gross_rev from daily_revenue dr right join C1 on C1.day=dr.order_date and C1.region = dr.region),

E as (select D.*,(lag(gross_rev) over (partition by region order by order_date)) as prev_day_rev from D ) 
select E.*, 
(gross_rev-prev_day_rev) as abs_rev_change,
round((gross_rev-prev_day_rev)/nullif(prev_day_rev,0)*100,2) as DOD_change from E




-------------------- Day 3: Consecutive Events & Island/Gap Problems --------------------------------




--Q1. Write a query or CTE that extracts distinct user_id and activity_date combinations, ordered by user_id and activity_date.--
select user_id,activity_date  from user_activity group by 1,2 order by 1,2;

---------Q2--------------: 
--Consecutive Day Detection using LAG()---
with ua as (select user_id,activity_date  from user_activity group by 1,2),
t2 as (select ua.*, lag(activity_date) over (partition by user_id order by activity_date) as comp_date from ua)

select t2.*, 
case 
when comp_date is null then 'first_day'	
when (activity_date-comp_date)=1 then '1' else 'broke the streak' end as consecutive_flag from t2

------Q3---------------
----The Classic "Gaps & Islands" Pattern (Row Number Difference)----
with ua as (select user_id,activity_date  from user_activity group by 1,2),
--t2 as (select ua.*, lag(activity_date) over (partition by user_id order by activity_date) as comp_date from ua),
t3 as (select ua.*, row_number() over (partition by user_id order by activity_date)as rw_no  from ua)

select t3.*,activity_date::date-cast(rw_no as int) as island_group_id from t3

---- Q4 -----
----Identifying 3+ Day Streaks---

with ua as (select user_id,activity_date  from user_activity group by 1,2),
t3 as (select ua.*, row_number() over (partition by user_id order by activity_date)as rw_no  from ua),

t4 as (select t3.*,activity_date::date-cast(rw_no as int) as island_group_id from t3)

select user_id
,min(activity_date) as start_date
,max(activity_date) as end_date
,count(*) from t4  group by user_id,island_group_id having count(*) >= 3 order by 1


-------------------- Day 4: Consecutive Events & Island/Gap Problems --------------------------------

--Question 1: Strict Sequential Funnel Conversion
select * from funnel_events

with page_view as (select  distinct user_id, min(fe.event_timestamp ) as first_entry from funnel_events fe where fe.event_name = 'page_view' group by 1),
     add_to_cart as (select  distinct fe.user_id, min(fe.event_timestamp ) as first_atc_entry 
                     from funnel_events fe join page_view pv on fe.user_id =pv.user_id 
                     where fe.event_name = 'add_to_cart'
                           and fe.event_timestamp > pv.first_entry  group by 1),
     checkout as (select  distinct fe.user_id, min(fe.event_timestamp ) as first_chk_entry 
                     from funnel_events fe join add_to_cart pv on fe.user_id =pv.user_id 
                     where fe.event_name = 'checkout'
                           and fe.event_timestamp > pv.first_atc_entry  group by 1),
     purchase as (select  distinct fe.user_id, min(fe.event_timestamp ) as first_Prch_entry 
                     from funnel_events fe join checkout pv on fe.user_id =pv.user_id 
                     where fe.event_name = 'purchase'
                           and fe.event_timestamp > pv.first_chk_entry  group by 1),
temp as (                           

select user_id, '1' as step from page_view
union 
select user_id, '2' as step from add_to_cart
union 
select user_id, '3' as step from checkout
union 
select user_id, '4' as step from purchase ),

t2 as (select step,count(distinct user_id) as cnt from temp group by 1),

t3 as (select step,cnt,lag(cnt) over (order by step) as cnt_p from t2)

select t3.*, round((cnt*100.0/nullif(cnt_p,0)),2) as perc from t3;

----Day 4, Question 2: Flag-Based Funnel Pivot----

with page_view as (select  distinct user_id, min(fe.event_timestamp ) as first_entry from funnel_events fe where fe.event_name = 'page_view' group by 1),
     add_to_cart as (select  distinct fe.user_id, min(fe.event_timestamp ) as first_atc_entry 
                     from funnel_events fe join page_view pv on fe.user_id =pv.user_id 
                     where fe.event_name = 'add_to_cart'
                           and fe.event_timestamp > pv.first_entry  group by 1),
     checkout as (select  distinct fe.user_id, min(fe.event_timestamp ) as first_chk_entry 
                     from funnel_events fe join add_to_cart pv on fe.user_id =pv.user_id 
                     where fe.event_name = 'checkout'
                           and fe.event_timestamp > pv.first_atc_entry  group by 1),
     purchase as (select  distinct fe.user_id, min(fe.event_timestamp ) as first_Prch_entry 
                     from funnel_events fe join checkout pv on fe.user_id =pv.user_id 
                     where fe.event_name = 'purchase'
                           and fe.event_timestamp > pv.first_chk_entry  group by 1),
temp as (                           

select user_id, '1' as step from page_view
union 
select user_id, '2' as step from add_to_cart
union 
select user_id, '3' as step from checkout
union 
select user_id, '4' as step from purchase ),

a1 as (select 
user_id,
1 as "page_view"
from temp where step in ('1')),

a2 as (select 
user_id,
1 as "add_to_cart"
from temp where step in ('2')),

a3 as (select 
user_id,
1 as "checkout"
from temp where step in ('3')),

a4 as (select 
user_id,
1 as "purchase"
from temp where step in ('4'))

select a1.user_id,coalesce(a1.page_view,0),coalesce(a2.add_to_cart,0),coalesce(a3.checkout,0),coalesce(a4.purchase,0)
from a1 left join a2 on a1.user_id = a2.user_id 
left join a3 on a1.user_id = a3.user_id 
left join a4 on a1.user_id = a4.user_id 


----------------------------- short version --------------------------------------------------

WITH user_timestamps AS (
    SELECT 
        u.user_id,
        MIN(CASE WHEN fe.event_name = 'page_view'   THEN fe.event_timestamp END) AS first_view,
        MIN(CASE WHEN fe.event_name = 'add_to_cart' THEN fe.event_timestamp END) AS first_cart,
        MIN(CASE WHEN fe.event_name = 'checkout'    THEN fe.event_timestamp END) AS first_checkout,
        MIN(CASE WHEN fe.event_name = 'purchase'    THEN fe.event_timestamp END) AS first_purchase
    FROM user_signups u
    LEFT JOIN funnel_events fe ON u.user_id = fe.user_id
    GROUP BY u.user_id
)
SELECT 
    user_id,
    CASE WHEN first_view     IS NOT NULL THEN 1 ELSE 0 END AS has_viewed,
    CASE WHEN first_cart     IS NOT NULL THEN 1 ELSE 0 END AS has_carted,
    CASE WHEN first_checkout IS NOT NULL THEN 1 ELSE 0 END AS has_checked_out,
    CASE WHEN first_purchase IS NOT NULL THEN 1 ELSE 0 END AS has_purchased,
    ROUND(
        (EXTRACT(EPOCH FROM (first_purchase - first_view)) / 60.0)::numeric, 
        2
    ) AS view_to_purchase_time_minutes
FROM user_timestamps
ORDER BY user_id;


-------------------------------- Q2 Cohort Retention -------------------------------------------------------


with sups as (select user_id, date_trunc('week',signup_date)::date as cohort_week from user_signups), 

rtn as (select user_id, date_trunc('week',fe.event_timestamp )::date as week_alive from funnel_events fe ),

cte as (select 
s.user_id,
s.cohort_week,
r.week_alive
from sups s left join rtn r on s.user_id=r.user_id)

select 
cohort_week,
count(distinct user_id) as cohort_group,
count(distinct case when week_alive=cohort_week then user_id end) as week_0_retention,
count(distinct case when week_alive=cohort_week+7 then user_id end) as week_1_retention,
count(distinct case when week_alive=cohort_week+14 then user_id end) as week_2_retention,
round(count(distinct case when week_alive=cohort_week+7 then user_id end)*100.00/count(distinct user_id),2) as week_1_retention
from cte
group by 1

 










