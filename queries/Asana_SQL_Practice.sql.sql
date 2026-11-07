
----Q1 -------
with 
evnts as (select * from saas.events t  
where date_trunc('month',t.occurred_at::date) = '2026-03-01'::date
and t.event_name in ('task_created', 'task_completed', 'comment_added', 'project_created')),

mems as (select * from saas.memberships m 
where m.joined_at::date < '2026-04-01'::date and (m.left_at is null or m.left_at::date > '2026-04-01'::date)),

non_int_user as (select * from saas.users u where u.is_internal is false),

month_end_mems as (select * from mems where user_id in (select distinct user_id from non_int_user )),

active_mems as (
select count(distinct user_id) as t_count from saas.memberships   where left_at is null 

) 

select * from active_mems
--me_qua_cnt as (
select count(distinct m.user_id) as meq_count from month_end_mems m join evnts e on m.user_id = e.user_id
--)

select round(t_count*100.0/nullif((select meq_count from me_qua_cnt),0),1) as seat_utilization_pct from active_mems

select * from saas.accounts ;


----Q2-----
/*Format */

/*
 * “I’m calculating [metric], 
 * defined as [formula]. 
 * The output is one row per [grain], 
 * for [population] over [time window]. 
 * I’ll use [tables] first rolling [table] up to [intermediate grain] to avoid fan-out, 
 * then [join or aggregate]. I’ll check it by [validation].”
 */

/*
 * E01: Seat utilization by account
Target time: 12 minutes
Business question: For March 2026, how much of each account's month-end membership was active?

Definitions
• Month-end member: a non-internal user with a membership in the account at the instant 2026-04-01 00:00 UTC. That means joined_at is before that instant, and left_at is NULL or at or after it.
• Qualifying event: a logical event named task_created, task_completed, comment_added or project_created, with occurred_at in March 2026 UTC.
• qualifying_events: the qualifying events a month-end member made in that account. Count them even if they happened outside that person's membership spell.
• active_members: month-end members with at least one qualifying event in that account.
• seat_utilization_pct: 100 * active_members / members_eom, rounded to 1 decimal place. Return NULL when members_eom is 0.
 */

/* Question: For March 2026, how much of each account's month-end membership was active?
 * 
 * I am calculating seat util capacity metric for each account.
 * Grain = one row per Account 
 * First we should get end of the member and and qualifying event to get active members.
 * Def = Total Active (EOM) members / Total members (EOM)
 * final columns = account_id, account_name, members_eom, active_members, qualifying_events and seat_utilization_pct.
 */

/* Join Accounts with membership table first on account id and filter users and get only non internal users */


select * from saas.accounts ;
select * from saas.memberships m  ;
select * from saas.events e    ;

 select * from saas.users e    ;



with end_of_mem as (
select a.account_id,a.account_name,m.user_id 
from saas.accounts a join saas.memberships m on m.account_id =a.account_id 
where m.joined_at< '2026-04-01' 
and (left_at is null or left_at>= '2026-04-01' )
),

eom_non_int_user as (select * from end_of_mem where user_id in (select  user_id from saas.users where is_internal is false) ),

qual_event as (

select distinct event_id,e.user_id,e.account_id 
from saas.events e 
join saas.memberships m 
on e.account_id=m.account_id
and e.user_id=m.user_id
and e.occurred_at>m.joined_at
and (m.left_at is null or m.left_at>e.occurred_at)
where event_name in ('task_created','task_completed','comment_added','project_created')
and occurred_at >= '2026-03-01'
and occurred_at < '2026-04-01'

)

/* joining qual_event and eom_non_int_user  you would users who are end of month members with qualified events */


select 
e.account_id, 
e.account_name,
count(distinct em.user_id) as mem_eom,
count(distinct qe.user_id) as active_mems,
count(distinct qe.event_id) as qualifying_events,
round(count(distinct qe.user_id)*100.0/nullif(count(distinct em.user_id),0),1) as seat_utilization_pct

from saas.accounts e 
left join eom_non_int_user em on e.account_id =em.account_id
left join qual_event qe on qe.account_id = em.account_id and qe.user_id= em.user_id
group by 1,2
order by 1





WITH evnts AS (
  SELECT DISTINCT event_id, user_id, account_id
  FROM saas.events t
  WHERE t.occurred_at >= '2026-03-01'
    AND t.occurred_at <  '2026-04-01'
    AND t.event_name IN ('task_created','task_completed',
                         'comment_added','project_created')
),
mems AS (
  SELECT *
  FROM saas.memberships m
  WHERE m.joined_at >= '2026-03-01'
    AND (m.left_at IS NULL OR m.left_at >= '2026-04-01')
),
month_end_mems AS (
  SELECT DISTINCT account_id, user_id
  FROM mems
  WHERE user_id IN (SELECT user_id FROM saas.users
                    WHERE is_internal IS FALSE)
)
SELECT a.account_id,
       a.account_name,
       COUNT(DISTINCT m.user_id)  AS members_eom,
       COUNT(DISTINCT e.user_id)  AS active_members,
       COUNT(DISTINCT e.event_id) AS qualifying_events,
       ROUND(100.0 * COUNT(DISTINCT e.user_id)
             / NULLIF(COUNT(DISTINCT m.user_id), 0), 1) AS seat_utilization_pct
FROM saas.accounts a
LEFT JOIN month_end_mems m ON m.account_id = a.account_id
LEFT JOIN evnts e
  ON e.account_id = m.account_id
 AND e.user_id = m.user_id
GROUP BY a.account_id, a.account_name
ORDER BY a.account_id;


/*
 * How would you count only events that happened during an active membership spell, and which number changes?
 * 
If this became a daily Gold table, what would its grain be, and why can’t you sum active_members across days?

 * 
 */


------ E2 -------

/*Business question: Customer success wants the accounts that had no qualifying activity in March 2026, and when each one was last active.
Use saas.accounts and saas.events, with the same event_id and UTC rules as E01.

Definitions
• Qualifying event: a logical event named task_created, task_completed, comment_added or project_created.
• No March activity: the account has no qualifying event with occurred_at in March 2026 UTC.
• last_qualifying_at: the latest qualifying event in that account before 2026-03-01 UTC, or NULL if there is none.

Required output: one row per matching account, sorted by account_id. The columns are account_id, account_name and last_qualifying_at. */


/* Grain = one row per account 
 * Define no qualifying actvty
 */

select a.account_id ,a.account_name, 
(
select max(p.occurred_at)
from  saas.events p 
where p.account_id =a.account_id 
and p.event_name in ('task_created','task_completed','comment_added','project_created')
and p.occurred_at < '2026-03-01' 
) as last_qualifying_at
from saas.accounts a 
where not exists (
select 1 from  saas.events e 
where e.event_name in ('task_created','task_completed','comment_added','project_created')
and e.occurred_at >= '2026-03-01' 
and e.occurred_at < '2026-04-01' 
and e.account_id =a.account_id )
group by 1,2
order by 1

----using left join ----

select a.account_id ,a.account_name
from saas.accounts a 
left join saas.events e on a.account_id =e.account_id
and  e.event_name  in ('task_created','task_completed','comment_added','project_created')
and  e.occurred_at >= '2026-03-01' 
and  e.occurred_at < '2026-04-01' 
where  e.event_id is null
order by 1


-------- E03 -----
/*
 * Grain: one user per row 
 * join users and events to get qualifying events and remove internal users
 * 
 */

/* using having*/

with Q_eve as (

select user_id,occurred_at from saas.events e 
where e.event_name  in ('task_created','task_completed','comment_added','project_created')
and e.occurred_at >= '2026-02-1'
and  e.occurred_at < '2026-04-1'

)

select 
u.user_id,
u.email
from saas.users u 
join Q_eve q on u.user_id =q.user_id
where u.is_internal is false
group by 1,2
having sum(case when q.occurred_at >= '2026-02-01' and q.occurred_at < '2026-03-01' then 1 else 0 end) > 0 
   and sum(case when q.occurred_at >= '2026-03-01' and q.occurred_at < '2026-04-01' then 1 else 0 end) > 0 
order by 1


/* Using Exists*/

select
m.account_id,
u.user_id,
u.email
from saas.users u join saas.memberships m on m.user_id =u.user_id  
where u.is_internal is false
   and exists (
              select 1 from saas.events e 
              where e.user_id=u.user_id
              and m.account_id = e.account_id 
              --and e.occurred_at> m.joined_at
              --and (m.left_at is null or m.left_at >= '2026-03-01') 
              and (e.occurred_at >= '2026-02-01' and e.occurred_at < '2026-03-01')
              and e.event_name  in ('task_created','task_completed','comment_added','project_created')
              ) 
   and exists (
              select 1 from saas.events e 
              where e.user_id=u.user_id
              and m.account_id = e.account_id 
              --and (m.left_at is null or m.left_at >= '2026-04-01') 
              and (e.occurred_at >= '2026-03-01' and e.occurred_at < '2026-04-01')
              and e.event_name  in ('task_created','task_completed','comment_added','project_created')
              ) 
group by 1,2,3
order by 1,2



---- E 04 ----
/*
 * Grain = one account per one row
 * calculate tasks joining tasks and accounts 
 * one row per account, 
 * including accounts with no in-scope tasks, 
 * sorted by account_id. 
 * The columns are account_id, account_name, total_tasks, completed_tasks, unassigned_tasks and completion_rate_pct.
 * */

select a.account_id,
a.account_name,
count(distinct task_id) as total_tasks,
sum(case when t.completed_at < '2026-04-01' then 1 else 0 end) as completed_tasks,
sum(case when t.assignee_id is null then 1 else 0 end) as unassigned_tasks,
round(sum(case when t.completed_at < '2026-04-01' then 1 else 0 end)*100.0/nullif(count(distinct task_id),0),1) as completion_rate_pct  
from saas.tasks t 
right join saas.accounts a 
on a.account_id = t.account_id 
and t.created_at >= '2026-01-01'
and t.created_at < '2026-04-01'
and t.deleted_at is null
group by 1,2
order by 1

select * from saas.tasks; 


--- E01: B------

--Required output: one row per account, 
--including accounts with zero members or zero activity, 
--sorted by account_id. The columns are account_id, account_name, members_eom, engaged_members, engagement_events and engaged_pct.


with mem as (select m.account_id ,m.user_id  from saas.accounts a left join  saas.memberships m  on a.account_id =m.account_id 
             where (m.joined_at < '2026-03-01' and m.left_at is null) or (m.joined_at < '2026-03-01' and m.left_at >= '2026-03-01' ) ),
            

                   
      events as (select event_id,user_id,account_id from saas.events e
                  where event_name in ('task_completed','comment_added')
                  and e.occurred_at >= '2026-02-01'
                  and  e.occurred_at < '2026-03-01'),
                  
      non_user as (select * from mem where user_id in (select user_id from saas.users u where u.is_internal is false) )
      
      select 
      a.account_id,
      a.account_name,
      count(distinct nu.user_id) as mem_count,
      count(distinct e.user_id) as event_count,
      count( distinct e.event_id) as eng_events,
      round(count( distinct e.user_id)*100.0/nullif(count(distinct nu.user_id),0),1) as eng_pct
  
      from saas.accounts a left join non_user nu 
      on a.account_id =nu.account_id
      left join events e on e.account_id = a.account_id and e.user_id = nu.user_id
      group by 1,2
      order by 1
      
      
 ----- E 05 -----
 
 /* Query A: The columns are project_id, project_name, account_id, completed_tasks and completed_pts
  * 
  * Rows per project id and account id 
  * population: tasks calculation
  * Metric comp task and pnts
  * 
  */
  
  select * from saas.task_projects ;   
  
  select * from saas.projects
      

  select * from saas.tasks deleted_at is null and completed_at >= '2026-01-01' and completed_at < '2026-04-01'
  
  
  select 
  p.project_id,
  p.project_name,
  a.account_id,
  SUM(case when t.deleted_at is null and t.completed_at >= '2026-01-01' and t.completed_at < '2026-04-01' then 1 else 0 end) as completed_tasks,
  coalesce(SUM(case when t.deleted_at is null and t.completed_at >= '2026-01-01' and t.completed_at < '2026-04-01' then t.estimate_pts else 0 end),0) as estimated_points
  from saas.accounts a 
  join saas.projects p 
  on a.account_id = p.account_id
  join saas.task_projects tp
  on tp.project_id=p.project_id 
  join saas.tasks t 
  on a.account_id = t.account_id and t.task_id = tp.task_id
  group by 1,2,3
  order by 1
  
  
  ---- Redo ----
  
   ---Q1-- 
  select 
  p.project_id,
  p.project_name,
  p.account_id,
  count(distinct t.task_id) as completed_tasks,
  coalesce(SUM(t.estimate_pts),0) as estimated_points
  from saas.projects p 
  left join saas.task_projects tp
  on tp.project_id=p.project_id 
  left join saas.tasks t 
  on p.account_id = t.account_id 
  and t.task_id = tp.task_id
  and t.deleted_at is null
  and t.completed_at >= '2026-01-01'
  and t.completed_at < '2026-04-01'
  group by 1,2,3
  order by 1
  ----Q2----
  
   select
  a.account_id,
  a.account_name,
  count(distinct t.task_id) as completed_tasks,
  coalesce(SUM(t.estimate_pts),0) as estimated_points

  from saas.accounts a
  left join saas.tasks t
  on  t.account_id = a.account_id
  and t.deleted_at is null
  and t.completed_at >= '2026-01-01'
  and t.completed_at < '2026-04-01'
  group by 1,2
  order by 1
  

  
  ------ E20 -----
/*
 * A customer success manager says the April active-users report is missing accounts. 
 * Every account should appear, with 0 when it had no activity. 
 * The analyst who wrote it says it uses a LEFT JOIN, so nothing can be missing.
Your tasks
1. Explain the cause in one or two sentences, as you would to the analyst.
2. Fix the query.
3. Propose one SQL check that would catch this bug automatically in future.

Explanation:

1. The problem is in where insread of filtering out using occured date which removes any accounts not in that date range, instead use join on condition.

 */  

 with A_temp as (
  
  SELECT a.account_id,
       a.account_name,
       COUNT(DISTINCT e.user_id) AS active_users
FROM saas.accounts a
LEFT JOIN saas.events e
  ON e.account_id = a.account_id
  where ( e.occurred_at >= '2026-04-01'
  AND e.occurred_at <  '2026-05-01'
  AND e.event_name IN ('task_created','task_completed',
                       'comment_added','project_created'))
OR e.event_id IS NULL
GROUP BY a.account_id, a.account_name
ORDER BY a.account_id ) 


--- Validation ---  
select at.account_id 
from saas.accounts at
where not exists (select 1 from A_temp A where at.account_id = A.account_id )

select * from saas.events


---- E06 ---

/*
 * For a user-status table, what was each real user's most recent event?
 * Definitions
• Scope: non-internal users with at least one event. Any event name counts, and any account, including a NULL account_id.
• Latest event: the event with the greatest occurred_at.
• Tie-break: if several events share that occurred_at, take the one with the highest event_id. Each user must return exactly one row.


Required output: one row per user, sorted by user_id. The columns are user_id, event_id, event_name and occurred_at.

* row per user, 
* 
* event + users table
*
*
**/


select * from saas.events


with A as (
select
u.user_id,
e.event_id,
e.event_name,
occurred_at,
row_number() over (partition by u.user_id order by e.occurred_at desc,e.event_id desc ) as rn
from saas.users u 
 join saas.events e
on u.user_id = e.user_id
where u.is_internal is false )

select user_id,
event_id,
event_name,occurred_at from A where rn=1
order by 1

select * from saas.events where user_id = 118

------ MAx ----
select
u.user_id,
Max(occurred_at)

from saas.users u 
 join saas.events e
on u.user_id = e.user_id
where u.is_internal is false 
group by 1
order by 1

---- redshift/ databricks Version without a sub query -----


select 
u.user_id,
e.event_id,
e.event_name,
occurred_at
from saas.users u 
join saas.events e
on u.user_id = e.user_id
where u.is_internal is false 
qualify row_number() over (partition by user_id order by e.occurred_at desc, event_id desc)=1
order by 1

------

/*Definitions
• Scope: account_id 2, with occurred_at in March 2026 UTC. Every event name counts, and a NULL user_id is kept.
• Logical event: one distinct event_id.
• Copy to keep: the earliest ingested_at for that event_id.


Required output: one row per event_id, sorted by event_id. The columns are event_id, user_id, event_name, occurred_at and ingested_at.
 * 
 */


SET TIME ZONE 'UTC' ;

select
event_id,
user_id,
event_name,
occurred_at,
ingested_at
from (
select 
event_id,
user_id,
event_name,
occurred_at,
ingested_at,
row_number() over (partition by event_id order by ingested_at) as rn
from saas.events e 
where occurred_at >= '2026-03-01'
and occurred_at < '2026-04-01'
and account_id =2
) A where A.rn=1
order by 1

--- E09 ---

/*
 * Definitions
• Qualifying event: a logical event named task_created, task_completed, comment_added or project_created, with occurred_at in March 2026 UTC, and a non-NULL account_id.
• Scope: non-internal users.
• qualifying_events: each user's qualifying events in that account.
• place: users ranked within each account by qualifying_events, highest first. Users with equal counts share a place, and the next place is the next number, with no gaps.
• Top users: users in place 1 or 2. Accounts with no qualifying events don't appear.


Required output: one row per account and user, sorted by account_id, then place, then user_id. The columns are account_id, user_id, qualifying_events and place.

Hihest Qual events - 1st
Equal counts = share rank
Next place is next number , so use dense rank, no gaps
Top users, 1 0r 2, No Qualifying Accounts - Join 
 */





with A as (select 
e.account_id,
u.user_id, 
count(distinct e.event_id) as Qual_events_count
from saas.users u 
join saas.events e
on u.user_id = e.user_id
where u.is_internal is false
and e.event_name in ('task_created','task_completed','project_created','comment_added')
and occurred_at >= '2026-03-01' 
and  occurred_at < '2026-04-01' 
and e.account_id is not null
group by 1,2)



select 
account_id,
user_id,
Qual_events_count,
place 
from 
(
select 
account_id,
user_id,
Qual_events_count,
dense_rank() over (partition by account_id order by Qual_events_count desc ) as place
from A 
) QT
--where QT.place <= 2 
order by 1,4,2



/*
 * Business question: For the executive summary, how did the number of active accounts change each month from January to April 2026?
 * 
 * Definitions
• Qualifying event: an event named task_created, task_completed, comment_added or project_created, by a non-internal user, with a non-NULL account_id.

• Active account in a month: an account with at least one qualifying event in that calendar month UTC.

• active_accounts: active accounts in that month.

• prev_month_active: active_accounts for the previous month; NULL for January.

• change: active_accounts minus prev_month_active.

• pct_change: 100 * change / prev_month_active, rounded to 1 decimal place.

• is_complete: true when the whole month has ended by practice today.

Required output: one row per month, January to April 2026, sorted by month. 

The columns are month (first day of the month, as a date), active_accounts, prev_month_active, change, pct_change and is_complete.
 * 
 */

select 
month_start,
active_accounts,
lag(active_accounts) over ( order by month_start) as prev_month_active,
(active_accounts-lag(active_accounts) over (order by month_start)) as change,
round((active_accounts-lag(active_accounts) over (order by month_start))*100.0/nullif(lag(active_accounts) over ( order by month_start),0),2) as pct_change,
(month_start + interval '1 month')::date <= '2026-04-30'::date as is_complete

from(

select 
date_trunc('month',occurred_at)::date as month_start,
count(distinct e.account_id) as active_accounts
from saas.users u 
join saas.events e 
on u.user_id = e.user_id
where u.is_internal is false
and e.event_name in ('task_created','task_completed','project_created','comment_added')
and e.account_id is not null
and occurred_at >= '2026-01-01' 
and  occurred_at < '2026-05-01' 
group by 1
)
order by 1


------- E09 -----

/*
 * Target time: 10 minutes (stop at 20 if stuck)
Business question: Product wants a daily active users chart for March 2026 with no gaps, so a quiet day shows as 0 rather than disappearing.
Use saas.users and saas.events. Timestamps are UTC.
Definitions
• Qualifying event: an event named task_created, task_completed, comment_added or project_created, by a non-internal user. Any account counts, including a NULL account_id.
• dau: distinct users with at least one qualifying event on that UTC calendar day.
Required output: one row for every day of March 2026 (31 rows), sorted by activity_date. The columns are activity_date (a date) and dau, with 0 on days with no active users.
Expected output
Days not listed below have dau 0. There are 17 of them.
 */





