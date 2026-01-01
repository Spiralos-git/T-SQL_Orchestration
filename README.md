Copyright (c) 2026 Dominique Beneteau (dombeneteau@yahoo.com)

This SQL Server package allows you to orchestrate processes (in our case stored procedures, but can easily be extended to command line execs, etc).

It is organised around:

- A table listing the jobs you might have to run. Think of a job as a group of tasks to perform, like an ETL populating n tables for instance. That's the PJob.Job table.
- A table listing the tasks you want to perform. Think of a task as a unit exec. In this package, I made a set of stored procedures my tasks. That's the PJob.Task table.
- A table describing the orchestration of the tasks (and the job(s) they run under). A ParentTaskID column and a TaskID column define the sequence (e.g. TaskID can run after ParentTaskID has completed). One can use different ParentTaskIDs for the same TaskID to define dependencies. That's the PJob.TaskPlan table.
- A table logging the execution in real time. That's the PJob.TaskPlanRun table.
- A SQL Agent job regularly polling the Pjob.TaskPlan and Pjob.TaskPlanRun tables. That's the engine. Its name is JobPolling, it runs the PJob.JobPolling stored proc every 15 seconds.
- A flexible number of SQL Agent jobs, all of them have the same purpose: Running a dynamically assigned task. In this package I created 8 instances meaning that in theory we can run 8 tasks in parallel. Their names are JobAgent1 to JobAgent8. They all run the same stored procedure called PJob.RunAgent, passing it an integer defining the Agent number in question. They run every 15 seconds as well.
- A list (AKA number...) of available Agents which is defined in the PJob.Agent table.
able.
The jobs history is stored in an archive table called PJob.TaskRunHistory, and there is also a reference table called PJob.Status used by the engine.

In summary, the polling job:

- Execute a one-off stored proc that prepares the list of tasks to run from the PJob.TaskPlan table into the PJob.TaskPlanRun table. This stored proc is called PJob.TaskPlanInit.
- Start preparing the task execution of the orphans TaskID (ParentTaskID NULL) by assigning a free Agent to each of them. That updates the PJob.TaskPlanRun table.
- In parallel, each JobAgent is running, polling to check if something is assigned to them. If yes, the JobAgent executes the task and updates the PJob.TaskPlanRun table.
- As per the PJob.TaskPlanRun table updates, next eligible tasks are assigned, etc. This process continues until all tasks are executed (or an error occurs).

--------------------------------------------------------------------------------------------------------------------------------
NOTE: The jobs provided in the Init.sql file are using a database named 'dev'. Please rename it in the script using your own db.
--------------------------------------------------------------------------------------------------------------------------------

Just run the Init.sql file on your platform. It will create the Pjob schema, the tables (and the predefined tests), the stored procs and the jobs. 
Familiarise yourself with the Pjob.TaskPlan table, check the Pjob.sp_test* stored procs (they are just example of tasks for demo purpose, you'll use your own later).
Give the JobPolling job a go, check the progression of updates into the PJob.TaskPlanRun table and see the results in the PJob.TaskRunHistory table.
Adapt it to your tasks, etc.

That's just a core engine. You can adapt it to monitor executions in real time (select PJob.TaskPlanRun), to report past executions (select PJob.TaskRunHistory), to create operational notifications or alerts (tweak/enhance error handling), etc.

Feel free to get in touch.

