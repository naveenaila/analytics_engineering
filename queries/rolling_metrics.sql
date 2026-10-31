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

--Question 1: Cumulative Running Revenue
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
(gross_rev-prev_day_rev)/nullif(prev_day_rev,0)as DOD_change from E









