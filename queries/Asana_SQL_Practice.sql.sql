
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

