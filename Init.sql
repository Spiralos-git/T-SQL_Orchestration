-- Copyright (c) 2026 by Dominique Beneteau (dombeneteau@yahoo.com)

SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO

-- init script
--
-- Create schema if not exists
IF (NOT EXISTS (SELECT * FROM sys.schemas WHERE name = 'PJob'))
BEGIN
    EXEC('CREATE SCHEMA [PJob] AUTHORIZATION [dbo]');
END

drop table if exists [PJob].[Agent];
CREATE TABLE [PJob].[Agent](
	[AgentID] [int] NOT NULL,			-- Agent number
	[AgentStatusID] [int] NOT NULL,		-- Init with 3
 CONSTRAINT [AgentPK] PRIMARY KEY CLUSTERED ([AgentID] ASC)
)
GO
-- data for demo
INSERT into [PJob].[Agent] ([AgentID], [AgentStatusID]) VALUES 
(1, 3), (2, 3), (3, 3), (4, 3), (5, 3), (6, 3), (7, 3), (8, 3)	
GO

drop TABLE if exists [PJob].[Job];
CREATE TABLE [PJob].[Job](
	[JobID] [int] NOT NULL,				-- Job number
	[JobName] [nvarchar](255) NOT NULL,	-- Name
	[StatusID] [int] NOT NULL,			-- Init with 2
 CONSTRAINT [JobPK] PRIMARY KEY CLUSTERED ([JobID] ASC)
)
GO
-- data for demo
INSERT into [PJob].[Job] ([JobID], [JobName], [StatusID]) VALUES 
(1, N'Job 1', 2), (2, N'Job 2', 2)	
GO

-- Reference table 
DROP TABLE if exists [PJob].[Status];
CREATE TABLE [PJob].[Status](
	[StatusID] [int] NOT NULL,
	[StatusLabel] [nvarchar](255) NOT NULL,
 CONSTRAINT [StatusPK] PRIMARY KEY CLUSTERED ([StatusID] ASC)
)
GO
-- Static data
INSERT into [PJob].[Status] ([StatusID], [StatusLabel]) VALUES 
(1, N'Job running'), (2, N'Job not running'), (3, N'Agent free'), (4, N'Agent running'), (5, N'Agent allocated')
GO

DROP TABLE if exists [PJob].[Task];
CREATE TABLE [PJob].[Task](
	[TaskID] [int] NOT NULL,
	[TaskName] [nvarchar](255) NOT NULL,
	[JobID] [int] NOT NULL,
 CONSTRAINT [TaskPK] PRIMARY KEY CLUSTERED ([TaskID] ASC)
)
GO
-- data for demo
INSERT into [PJob].[Task] ([TaskID], [TaskName], [JobID]) VALUES
(1, N'PJob.sp_test1_1', 1), (2, N'PJob.sp_test1_2', 1), (3, N'PJob.sp_test1_3', 1), (4, N'PJob.sp_test1_4', 1),
(5, N'PJob.sp_test2_1', 2), (6, N'PJob.sp_test2_2', 2), (7, N'PJob.sp_test2_3', 2), (8, N'PJob.sp_test2_4', 2), (9, N'PJob.sp_test2_5', 2)
GO

DROP TABLE if exists [PJob].[TaskPlan];
CREATE TABLE [PJob].[TaskPlan](
	[TaskPlanID] [int] IDENTITY(1,1) NOT NULL,
	[ParentTaskID] [int] NULL,
	[TaskID] [int] NOT NULL,
	[JobID] [int] NOT NULL,
 CONSTRAINT [TaskPlanPK] PRIMARY KEY CLUSTERED ([TaskPlanID] ASC)
)
GO
-- data for demo
SET IDENTITY_INSERT [PJob].[TaskPlan] ON 
GO
INSERT into [PJob].[TaskPlan] ([TaskPlanID], [ParentTaskID], [TaskID], [JobID]) VALUES 
(1, NULL, 1, 1), (2, NULL, 2, 1), (3, 1, 3, 1), (4, 2, 3, 1), (5, 3, 4, 1),
(6, NULL, 5, 2), (7, NULL, 6, 2), (8, NULL, 7, 2), (9, 5, 8, 2), (10, 6, 8, 2), (11, 7, 8, 2), (12, 8, 9, 2)
GO
SET IDENTITY_INSERT [PJob].[TaskPlan] OFF
GO

DROP TABLE if exists [PJob].[TaskPlanRun];
CREATE TABLE [PJob].[TaskPlanRun](
	[TaskPlanRunID] [int] IDENTITY(1,1) NOT NULL,
	[JobID] [int] NOT NULL,
	[ParentTaskID] [int] NULL,
	[ParentTaskLastEndDatetime] [datetime2](7) NULL,
	[TaskID] [int] NOT NULL,
	[TaskLastEndDatetime] [datetime2](7) NULL,
	[AllocatedAgentID] [int] NULL,
	[IsComplete] [bit] NOT NULL,
	CONSTRAINT [TaskPlanRunPK] PRIMARY KEY CLUSTERED ([TaskPlanRunID] ASC)
)
GO

DROP TABLE if exists [PJob].[TaskRunHistory];
CREATE TABLE [PJob].[TaskRunHistory](
	[TaskRunHistory] [int] IDENTITY(1,1) NOT NULL,
	[TaskID] [int] NOT NULL,
	[AgentID] [int] NOT NULL,
	[StartDatetime] [datetime2](7) NOT NULL,
	[EndDatetime] [datetime2](7) NOT NULL,
	[IsSuccess] [bit] NOT NULL,
	[ErrorMessage] [nvarchar](255) NULL,
	CONSTRAINT [TaskRunHistoryPK] PRIMARY KEY CLUSTERED ([TaskRunHistory] ASC)
)
GO

create OR ALTER proc [PJob].[JobPolling]
@JobID int = NULL	-- optional
as
begin
	declare @TaskPlanRunID int, @TaskID int, @AgentID int

	if not exists (select top 1 1 from PJob.Job where JobID = ISNULL(@JobID, JobID))
		throw 51000, 'PJob.JobPolling: Invalid @JobID', 1;
	
	-- Is there at least one task remaining to be processed?
	if not exists (select top 1 1 from PJob.TaskPlanRun where JobID = ISNULL(@JobID, JobID) and IsComplete = 0)
		return 0

	-- Is there at least one agent free?
	if not exists (select top 1 1 from PJob.Agent where AgentStatusID = (SELECT StatusID from PJob.[Status] where StatusLabel = 'Agent free'))
		return 0

	-- Creating a set of eligible tasks from the PJobTaskPlanRun table

	drop table if exists #Eligible
	select TaskID
	into #Eligible
	from PJob.TaskPlanRun
	where ParentTaskID IS NULL
	and IsComplete = 0
	and AllocatedAgentID IS NULL
	and JobID = ISNULL(@JobID, JobID);

	;with dependencies as (
		select	min(ParentTaskLastEndDatetime) as minParent,
				min(TaskLastEndDatetime) as minTask,
				TaskID
		from	PJob.TaskPlanRun
		where IsComplete = 0
		and ParentTaskID IS NOT NULL
		and	AllocatedAgentID IS NULL
	--	and JobID = ISNULL(@JobID, JobID)
		group by TaskID)

		insert into #Eligible (TaskID)
			select TaskID
			from dependencies
			where minParent > minTask

	-- Assigning free agents to eligible tasks
	while (1=1)
	begin
		set @AgentID = NULL;
		select top 1 @AgentID = AgentID from PJob.Agent where AgentStatusID = (SELECT StatusID from PJob.[Status] where StatusLabel = 'Agent free');
		if @AgentID IS NULL break;

		set @TaskID = NULL;
		select top 1 @TaskID = TaskID
		from #Eligible;
		if @TaskID IS NULL break;

		begin tran
			
			UPDATE PJob.Agent
			set AgentStatusID = (SELECT StatusID from PJob.[Status] where StatusLabel = 'Agent allocated')
			where AgentID = @AgentID;

			UPDATE PJob.TaskPlanRun
			set AllocatedAgentID = @AgentID
			where TaskID = @TaskID

			delete #Eligible
			where TaskID = @TaskID
		commit
	end
end
GO

create OR ALTER proc [PJob].[RunAgent]
@AgentID int
as
begin
	declare @TaskID int, @TaskName nvarchar(255);
	declare @StartDatetime datetime2(7), @EndDatetime datetime2(7), @IsSuccess bit = 1, @ErrorMessage nvarchar(255) = NULL;

	-- Is Agent allocated?
	if not exists (select top 1 1 from PJob.Agent where AgentID = @AgentID and AgentStatusID = (SELECT StatusID from PJob.[Status] where StatusLabel = 'Agent allocated'))
		return 0

	select top 1 @TaskID = TaskID from PJob.TaskPlanRun where AllocatedAgentID = @AgentID and IsComplete = 0

	begin try

		select @TaskName = TaskName from PJob.Task where TaskID = @TaskID;

		UPDATE PJob.Agent
		set AgentStatusID = (SELECT StatusID from PJob.[Status] where StatusLabel = 'Agent running')
		where AgentID = @AgentID;

		set @StartDatetime = getdate();

		execute sp_executesql @TaskName;

	end try
	
	begin catch
		set @IsSuccess = 0;
		set @ErrorMessage = ERROR_MESSAGE();
	end catch

	set @EndDatetime = getdate();

	UPDATE PJob.TaskPlanRun
	set	TaskLastEndDatetime = @EndDatetime,
		IsComplete = 1
	where TaskID = @TaskID;

	UPDATE PJob.TaskPlanRun
	set	ParentTaskLastEndDatetime = @EndDatetime
	where ParentTaskID = @TaskID;

	UPDATE PJob.Agent
	set AgentStatusID = (SELECT StatusID from PJob.[Status] where StatusLabel = 'Agent free')
	where AgentID = @AgentID;

	insert into PJob.TaskRunHistory
				(TaskID,
				AgentID,
				StartDatetime,
				EndDatetime,
				IsSuccess,
				ErrorMessage
				)
		values	(@TaskID,
				@AgentID,
				@StartDatetime,
				@EndDatetime,
				@IsSuccess,
				@ErrorMessage)
end
GO

-- demo tasks...
create OR ALTER proc [PJob].[sp_test1_1] as
waitfor delay '00:00:10'
GO
create OR ALTER proc [PJob].[sp_test1_2] as
waitfor delay '00:00:11'
GO
create OR ALTER proc [PJob].[sp_test1_3] as
waitfor delay '00:00:12'
GO
create OR ALTER proc [PJob].[sp_test1_4] as
waitfor delay '00:00:13'
GO
create OR ALTER proc [PJob].[sp_test2_1] as
waitfor delay '00:00:14'
GO
create OR ALTER proc [PJob].[sp_test2_2] as
waitfor delay '00:00:15'
GO
create OR ALTER proc [PJob].[sp_test2_3] as
waitfor delay '00:00:16'
GO
create OR ALTER proc [PJob].[sp_test2_4] as
waitfor delay '00:00:17'
GO
create OR ALTER proc [PJob].[sp_test2_5] as
waitfor delay '00:00:18'
GO

create OR ALTER proc [PJob].[TaskPlanInit]
@JobID int
as
begin
	if not exists (select top 1 1 from PJob.Job where JobID = @JobID)
		throw 51000, 'PJob.TaskPlanInit: Invalid @JobID', 1;

	delete PJob.TaskPlanRun
	where JobID = @JobID;

	with LastHistory as (
		select	TaskID,
				Max(EndDatetime) as MaxEndDatetime
		from PJob.TaskRunHistory
		where IsSuccess = 1
		group by TaskID)

	insert into PJob.TaskPlanRun
		(JobID,
		ParentTaskID,
		ParentTaskLastEndDatetime,
		TaskID,
		TaskLastEndDatetime,
		AllocatedAgentID,
		IsComplete)

		select	@JobID,
				T.ParentTaskID,
				coalesce(H1.MaxEndDatetime, '19010101'),
				T.TaskID,
				coalesce(H2.MaxEndDatetime, '19010101'),
				NULL,
				0
		from PJob.TaskPlan T
		left join LastHistory H1 on H1.TaskID = T.ParentTaskID
		left join LastHistory H2 on H2.TaskID = T.TaskID
		where JobID = @JobID;
		
	--while (1=1)
	--begin
	--	if not exists (select top 1 1 from PJob.TaskPlanRun where JobID = @JobID and IsComplete = 0)
	--		break;
	--	waitfor delay '00:00:15'; 
	--end
end
GO

-- SQL Agent jobs
USE [msdb]
GO

EXEC msdb.dbo.sp_delete_job @job_id=N'0333380c-a3a1-4eaa-b9c9-beac7666fc80', @delete_unused_schedule=1
GO

BEGIN TRANSACTION
DECLARE @ReturnCode INT
SELECT @ReturnCode = 0

IF NOT EXISTS (SELECT name FROM msdb.dbo.syscategories WHERE name=N'[Uncategorized (Local)]' AND category_class=1)
BEGIN
EXEC @ReturnCode = msdb.dbo.sp_add_category @class=N'JOB', @type=N'LOCAL', @name=N'[Uncategorized (Local)]'
IF (@@ERROR <> 0 OR @ReturnCode <> 0) GOTO QuitWithRollback

END

DECLARE @jobId BINARY(16)
EXEC @ReturnCode =  msdb.dbo.sp_add_job @job_name=N'JobPolling', 
		@enabled=1, 
		@notify_level_eventlog=0, 
		@notify_level_email=0, 
		@notify_level_netsend=0, 
		@notify_level_page=0, 
		@delete_level=0, 
		@description=N'No description available.', 
		@category_name=N'[Uncategorized (Local)]', 
		@owner_login_name=N'sa', @job_id = @jobId OUTPUT
IF (@@ERROR <> 0 OR @ReturnCode <> 0) GOTO QuitWithRollback

EXEC @ReturnCode = msdb.dbo.sp_add_jobstep @job_id=@jobId, @step_name=N'Poll', 
		@step_id=1, 
		@cmdexec_success_code=0, 
		@on_success_action=1, 
		@on_success_step_id=0, 
		@on_fail_action=2, 
		@on_fail_step_id=0, 
		@retry_attempts=0, 
		@retry_interval=0, 
		@os_run_priority=0, @subsystem=N'TSQL', 
		@command=N'exec PJob.JobPolling', 
		@database_name=N'dev', 
		@flags=0
IF (@@ERROR <> 0 OR @ReturnCode <> 0) GOTO QuitWithRollback
EXEC @ReturnCode = msdb.dbo.sp_update_job @job_id = @jobId, @start_step_id = 1
IF (@@ERROR <> 0 OR @ReturnCode <> 0) GOTO QuitWithRollback
EXEC @ReturnCode = msdb.dbo.sp_add_jobschedule @job_id=@jobId, @name=N'Polling every 15 seconds', 
		@enabled=1, 
		@freq_type=4, 
		@freq_interval=1, 
		@freq_subday_type=2, 
		@freq_subday_interval=15, 
		@freq_relative_interval=0, 
		@freq_recurrence_factor=0, 
		@active_start_date=20250305, 
		@active_end_date=99991231, 
		@active_start_time=0, 
		@active_end_time=235959, 
		@schedule_uid=N'b88b71fa-d458-4147-9cd9-d557e4b0d433'
IF (@@ERROR <> 0 OR @ReturnCode <> 0) GOTO QuitWithRollback
EXEC @ReturnCode = msdb.dbo.sp_add_jobserver @job_id = @jobId, @server_name = N'(local)'
IF (@@ERROR <> 0 OR @ReturnCode <> 0) GOTO QuitWithRollback
COMMIT TRANSACTION
GOTO EndSave
QuitWithRollback:
    IF (@@TRANCOUNT > 0) ROLLBACK TRANSACTION
EndSave:
GO

USE [msdb]
GO

EXEC msdb.dbo.sp_delete_job @job_id=N'b2275d8a-6952-4259-bf9d-aade187d351d', @delete_unused_schedule=1
GO

BEGIN TRANSACTION
DECLARE @ReturnCode INT
SELECT @ReturnCode = 0

IF NOT EXISTS (SELECT name FROM msdb.dbo.syscategories WHERE name=N'[Uncategorized (Local)]' AND category_class=1)
BEGIN
EXEC @ReturnCode = msdb.dbo.sp_add_category @class=N'JOB', @type=N'LOCAL', @name=N'[Uncategorized (Local)]'
IF (@@ERROR <> 0 OR @ReturnCode <> 0) GOTO QuitWithRollback

END

DECLARE @jobId BINARY(16)
EXEC @ReturnCode =  msdb.dbo.sp_add_job @job_name=N'JobAgent1', 
		@enabled=1, 
		@notify_level_eventlog=0, 
		@notify_level_email=0, 
		@notify_level_netsend=0, 
		@notify_level_page=0, 
		@delete_level=0, 
		@description=N'No description available.', 
		@category_name=N'[Uncategorized (Local)]', 
		@owner_login_name=N'sa', @job_id = @jobId OUTPUT
IF (@@ERROR <> 0 OR @ReturnCode <> 0) GOTO QuitWithRollback

EXEC @ReturnCode = msdb.dbo.sp_add_jobstep @job_id=@jobId, @step_name=N'RunMe', 
		@step_id=1, 
		@cmdexec_success_code=0, 
		@on_success_action=1, 
		@on_success_step_id=0, 
		@on_fail_action=2, 
		@on_fail_step_id=0, 
		@retry_attempts=0, 
		@retry_interval=0, 
		@os_run_priority=0, @subsystem=N'TSQL', 
		@command=N'exec PJob.RunAgent @AgentID = 1', 
		@database_name=N'dev', 
		@flags=0
IF (@@ERROR <> 0 OR @ReturnCode <> 0) GOTO QuitWithRollback
EXEC @ReturnCode = msdb.dbo.sp_update_job @job_id = @jobId, @start_step_id = 1
IF (@@ERROR <> 0 OR @ReturnCode <> 0) GOTO QuitWithRollback
EXEC @ReturnCode = msdb.dbo.sp_add_jobschedule @job_id=@jobId, @name=N'Runs every 15 seconds', 
		@enabled=1, 
		@freq_type=4, 
		@freq_interval=1, 
		@freq_subday_type=2, 
		@freq_subday_interval=15, 
		@freq_relative_interval=0, 
		@freq_recurrence_factor=0, 
		@active_start_date=20250305, 
		@active_end_date=99991231, 
		@active_start_time=0, 
		@active_end_time=235959, 
		@schedule_uid=N'c38de5da-a294-4ff1-acfc-a1dbf77a4dd1'
IF (@@ERROR <> 0 OR @ReturnCode <> 0) GOTO QuitWithRollback
EXEC @ReturnCode = msdb.dbo.sp_add_jobserver @job_id = @jobId, @server_name = N'(local)'
IF (@@ERROR <> 0 OR @ReturnCode <> 0) GOTO QuitWithRollback
COMMIT TRANSACTION
GOTO EndSave
QuitWithRollback:
    IF (@@TRANCOUNT > 0) ROLLBACK TRANSACTION
EndSave:
GO

USE [msdb]
GO


EXEC msdb.dbo.sp_delete_job @job_id=N'02dd5b7e-e530-4549-a260-3d0517420358', @delete_unused_schedule=1
GO


BEGIN TRANSACTION
DECLARE @ReturnCode INT
SELECT @ReturnCode = 0

IF NOT EXISTS (SELECT name FROM msdb.dbo.syscategories WHERE name=N'[Uncategorized (Local)]' AND category_class=1)
BEGIN
EXEC @ReturnCode = msdb.dbo.sp_add_category @class=N'JOB', @type=N'LOCAL', @name=N'[Uncategorized (Local)]'
IF (@@ERROR <> 0 OR @ReturnCode <> 0) GOTO QuitWithRollback

END

DECLARE @jobId BINARY(16)
EXEC @ReturnCode =  msdb.dbo.sp_add_job @job_name=N'JobAgent2', 
		@enabled=1, 
		@notify_level_eventlog=0, 
		@notify_level_email=0, 
		@notify_level_netsend=0, 
		@notify_level_page=0, 
		@delete_level=0, 
		@description=N'No description available.', 
		@category_name=N'[Uncategorized (Local)]', 
		@owner_login_name=N'sa', @job_id = @jobId OUTPUT
IF (@@ERROR <> 0 OR @ReturnCode <> 0) GOTO QuitWithRollback

EXEC @ReturnCode = msdb.dbo.sp_add_jobstep @job_id=@jobId, @step_name=N'RunMe', 
		@step_id=1, 
		@cmdexec_success_code=0, 
		@on_success_action=1, 
		@on_success_step_id=0, 
		@on_fail_action=2, 
		@on_fail_step_id=0, 
		@retry_attempts=0, 
		@retry_interval=0, 
		@os_run_priority=0, @subsystem=N'TSQL', 
		@command=N'exec PJob.RunAgent @AgentID = 2', 
		@database_name=N'dev', 
		@flags=0
IF (@@ERROR <> 0 OR @ReturnCode <> 0) GOTO QuitWithRollback
EXEC @ReturnCode = msdb.dbo.sp_update_job @job_id = @jobId, @start_step_id = 1
IF (@@ERROR <> 0 OR @ReturnCode <> 0) GOTO QuitWithRollback
EXEC @ReturnCode = msdb.dbo.sp_add_jobschedule @job_id=@jobId, @name=N'Runs every 15 seconds', 
		@enabled=1, 
		@freq_type=4, 
		@freq_interval=1, 
		@freq_subday_type=2, 
		@freq_subday_interval=15, 
		@freq_relative_interval=0, 
		@freq_recurrence_factor=0, 
		@active_start_date=20250305, 
		@active_end_date=99991231, 
		@active_start_time=0, 
		@active_end_time=235959, 
		@schedule_uid=N'c38de5da-a294-4ff1-acfc-a1dbf77a4dd1'
IF (@@ERROR <> 0 OR @ReturnCode <> 0) GOTO QuitWithRollback
EXEC @ReturnCode = msdb.dbo.sp_add_jobserver @job_id = @jobId, @server_name = N'(local)'
IF (@@ERROR <> 0 OR @ReturnCode <> 0) GOTO QuitWithRollback
COMMIT TRANSACTION
GOTO EndSave
QuitWithRollback:
    IF (@@TRANCOUNT > 0) ROLLBACK TRANSACTION
EndSave:
GO

USE [msdb]
GO


EXEC msdb.dbo.sp_delete_job @job_id=N'ff371fea-6290-4a53-964b-1a628eef9e12', @delete_unused_schedule=1
GO


BEGIN TRANSACTION
DECLARE @ReturnCode INT
SELECT @ReturnCode = 0

IF NOT EXISTS (SELECT name FROM msdb.dbo.syscategories WHERE name=N'[Uncategorized (Local)]' AND category_class=1)
BEGIN
EXEC @ReturnCode = msdb.dbo.sp_add_category @class=N'JOB', @type=N'LOCAL', @name=N'[Uncategorized (Local)]'
IF (@@ERROR <> 0 OR @ReturnCode <> 0) GOTO QuitWithRollback

END

DECLARE @jobId BINARY(16)
EXEC @ReturnCode =  msdb.dbo.sp_add_job @job_name=N'JobAgent3', 
		@enabled=1, 
		@notify_level_eventlog=0, 
		@notify_level_email=0, 
		@notify_level_netsend=0, 
		@notify_level_page=0, 
		@delete_level=0, 
		@description=N'No description available.', 
		@category_name=N'[Uncategorized (Local)]', 
		@owner_login_name=N'sa', @job_id = @jobId OUTPUT
IF (@@ERROR <> 0 OR @ReturnCode <> 0) GOTO QuitWithRollback

EXEC @ReturnCode = msdb.dbo.sp_add_jobstep @job_id=@jobId, @step_name=N'RunMe', 
		@step_id=1, 
		@cmdexec_success_code=0, 
		@on_success_action=1, 
		@on_success_step_id=0, 
		@on_fail_action=2, 
		@on_fail_step_id=0, 
		@retry_attempts=0, 
		@retry_interval=0, 
		@os_run_priority=0, @subsystem=N'TSQL', 
		@command=N'exec PJob.RunAgent @AgentID = 3', 
		@database_name=N'dev', 
		@flags=0
IF (@@ERROR <> 0 OR @ReturnCode <> 0) GOTO QuitWithRollback
EXEC @ReturnCode = msdb.dbo.sp_update_job @job_id = @jobId, @start_step_id = 1
IF (@@ERROR <> 0 OR @ReturnCode <> 0) GOTO QuitWithRollback
EXEC @ReturnCode = msdb.dbo.sp_add_jobschedule @job_id=@jobId, @name=N'Runs every 15 seconds', 
		@enabled=1, 
		@freq_type=4, 
		@freq_interval=1, 
		@freq_subday_type=2, 
		@freq_subday_interval=15, 
		@freq_relative_interval=0, 
		@freq_recurrence_factor=0, 
		@active_start_date=20250305, 
		@active_end_date=99991231, 
		@active_start_time=0, 
		@active_end_time=235959, 
		@schedule_uid=N'c38de5da-a294-4ff1-acfc-a1dbf77a4dd1'
IF (@@ERROR <> 0 OR @ReturnCode <> 0) GOTO QuitWithRollback
EXEC @ReturnCode = msdb.dbo.sp_add_jobserver @job_id = @jobId, @server_name = N'(local)'
IF (@@ERROR <> 0 OR @ReturnCode <> 0) GOTO QuitWithRollback
COMMIT TRANSACTION
GOTO EndSave
QuitWithRollback:
    IF (@@TRANCOUNT > 0) ROLLBACK TRANSACTION
EndSave:
GO

USE [msdb]
GO


EXEC msdb.dbo.sp_delete_job @job_id=N'740abf25-fa8b-4863-8161-500014008d7f', @delete_unused_schedule=1
GO


BEGIN TRANSACTION
DECLARE @ReturnCode INT
SELECT @ReturnCode = 0

IF NOT EXISTS (SELECT name FROM msdb.dbo.syscategories WHERE name=N'[Uncategorized (Local)]' AND category_class=1)
BEGIN
EXEC @ReturnCode = msdb.dbo.sp_add_category @class=N'JOB', @type=N'LOCAL', @name=N'[Uncategorized (Local)]'
IF (@@ERROR <> 0 OR @ReturnCode <> 0) GOTO QuitWithRollback

END

DECLARE @jobId BINARY(16)
EXEC @ReturnCode =  msdb.dbo.sp_add_job @job_name=N'JobAgent4', 
		@enabled=1, 
		@notify_level_eventlog=0, 
		@notify_level_email=0, 
		@notify_level_netsend=0, 
		@notify_level_page=0, 
		@delete_level=0, 
		@description=N'No description available.', 
		@category_name=N'[Uncategorized (Local)]', 
		@owner_login_name=N'sa', @job_id = @jobId OUTPUT
IF (@@ERROR <> 0 OR @ReturnCode <> 0) GOTO QuitWithRollback

EXEC @ReturnCode = msdb.dbo.sp_add_jobstep @job_id=@jobId, @step_name=N'RunMe', 
		@step_id=1, 
		@cmdexec_success_code=0, 
		@on_success_action=1, 
		@on_success_step_id=0, 
		@on_fail_action=2, 
		@on_fail_step_id=0, 
		@retry_attempts=0, 
		@retry_interval=0, 
		@os_run_priority=0, @subsystem=N'TSQL', 
		@command=N'exec PJob.RunAgent @AgentID = 4', 
		@database_name=N'dev', 
		@flags=0
IF (@@ERROR <> 0 OR @ReturnCode <> 0) GOTO QuitWithRollback
EXEC @ReturnCode = msdb.dbo.sp_update_job @job_id = @jobId, @start_step_id = 1
IF (@@ERROR <> 0 OR @ReturnCode <> 0) GOTO QuitWithRollback
EXEC @ReturnCode = msdb.dbo.sp_add_jobschedule @job_id=@jobId, @name=N'Runs every 15 seconds', 
		@enabled=1, 
		@freq_type=4, 
		@freq_interval=1, 
		@freq_subday_type=2, 
		@freq_subday_interval=15, 
		@freq_relative_interval=0, 
		@freq_recurrence_factor=0, 
		@active_start_date=20250305, 
		@active_end_date=99991231, 
		@active_start_time=0, 
		@active_end_time=235959, 
		@schedule_uid=N'c38de5da-a294-4ff1-acfc-a1dbf77a4dd1'
IF (@@ERROR <> 0 OR @ReturnCode <> 0) GOTO QuitWithRollback
EXEC @ReturnCode = msdb.dbo.sp_add_jobserver @job_id = @jobId, @server_name = N'(local)'
IF (@@ERROR <> 0 OR @ReturnCode <> 0) GOTO QuitWithRollback
COMMIT TRANSACTION
GOTO EndSave
QuitWithRollback:
    IF (@@TRANCOUNT > 0) ROLLBACK TRANSACTION
EndSave:
GO

USE [msdb]
GO


EXEC msdb.dbo.sp_delete_job @job_id=N'a56138db-e5be-4e1e-9bf3-31016f346d2f', @delete_unused_schedule=1
GO


BEGIN TRANSACTION
DECLARE @ReturnCode INT
SELECT @ReturnCode = 0

IF NOT EXISTS (SELECT name FROM msdb.dbo.syscategories WHERE name=N'[Uncategorized (Local)]' AND category_class=1)
BEGIN
EXEC @ReturnCode = msdb.dbo.sp_add_category @class=N'JOB', @type=N'LOCAL', @name=N'[Uncategorized (Local)]'
IF (@@ERROR <> 0 OR @ReturnCode <> 0) GOTO QuitWithRollback

END

DECLARE @jobId BINARY(16)
EXEC @ReturnCode =  msdb.dbo.sp_add_job @job_name=N'JobAgent5', 
		@enabled=1, 
		@notify_level_eventlog=0, 
		@notify_level_email=0, 
		@notify_level_netsend=0, 
		@notify_level_page=0, 
		@delete_level=0, 
		@description=N'No description available.', 
		@category_name=N'[Uncategorized (Local)]', 
		@owner_login_name=N'sa', @job_id = @jobId OUTPUT
IF (@@ERROR <> 0 OR @ReturnCode <> 0) GOTO QuitWithRollback

EXEC @ReturnCode = msdb.dbo.sp_add_jobstep @job_id=@jobId, @step_name=N'RunMe', 
		@step_id=1, 
		@cmdexec_success_code=0, 
		@on_success_action=1, 
		@on_success_step_id=0, 
		@on_fail_action=2, 
		@on_fail_step_id=0, 
		@retry_attempts=0, 
		@retry_interval=0, 
		@os_run_priority=0, @subsystem=N'TSQL', 
		@command=N'exec PJob.RunAgent @AgentID = 5', 
		@database_name=N'dev', 
		@flags=0
IF (@@ERROR <> 0 OR @ReturnCode <> 0) GOTO QuitWithRollback
EXEC @ReturnCode = msdb.dbo.sp_update_job @job_id = @jobId, @start_step_id = 1
IF (@@ERROR <> 0 OR @ReturnCode <> 0) GOTO QuitWithRollback
EXEC @ReturnCode = msdb.dbo.sp_add_jobschedule @job_id=@jobId, @name=N'Runs every 15 seconds', 
		@enabled=1, 
		@freq_type=4, 
		@freq_interval=1, 
		@freq_subday_type=2, 
		@freq_subday_interval=15, 
		@freq_relative_interval=0, 
		@freq_recurrence_factor=0, 
		@active_start_date=20250305, 
		@active_end_date=99991231, 
		@active_start_time=0, 
		@active_end_time=235959, 
		@schedule_uid=N'c38de5da-a294-4ff1-acfc-a1dbf77a4dd1'
IF (@@ERROR <> 0 OR @ReturnCode <> 0) GOTO QuitWithRollback
EXEC @ReturnCode = msdb.dbo.sp_add_jobserver @job_id = @jobId, @server_name = N'(local)'
IF (@@ERROR <> 0 OR @ReturnCode <> 0) GOTO QuitWithRollback
COMMIT TRANSACTION
GOTO EndSave
QuitWithRollback:
    IF (@@TRANCOUNT > 0) ROLLBACK TRANSACTION
EndSave:
GO

USE [msdb]
GO


EXEC msdb.dbo.sp_delete_job @job_id=N'2f31bd08-2c66-4529-8267-e62a9229c6cf', @delete_unused_schedule=1
GO


BEGIN TRANSACTION
DECLARE @ReturnCode INT
SELECT @ReturnCode = 0

IF NOT EXISTS (SELECT name FROM msdb.dbo.syscategories WHERE name=N'[Uncategorized (Local)]' AND category_class=1)
BEGIN
EXEC @ReturnCode = msdb.dbo.sp_add_category @class=N'JOB', @type=N'LOCAL', @name=N'[Uncategorized (Local)]'
IF (@@ERROR <> 0 OR @ReturnCode <> 0) GOTO QuitWithRollback

END

DECLARE @jobId BINARY(16)
EXEC @ReturnCode =  msdb.dbo.sp_add_job @job_name=N'JobAgent6', 
		@enabled=1, 
		@notify_level_eventlog=0, 
		@notify_level_email=0, 
		@notify_level_netsend=0, 
		@notify_level_page=0, 
		@delete_level=0, 
		@description=N'No description available.', 
		@category_name=N'[Uncategorized (Local)]', 
		@owner_login_name=N'sa', @job_id = @jobId OUTPUT
IF (@@ERROR <> 0 OR @ReturnCode <> 0) GOTO QuitWithRollback

EXEC @ReturnCode = msdb.dbo.sp_add_jobstep @job_id=@jobId, @step_name=N'RunMe', 
		@step_id=1, 
		@cmdexec_success_code=0, 
		@on_success_action=1, 
		@on_success_step_id=0, 
		@on_fail_action=2, 
		@on_fail_step_id=0, 
		@retry_attempts=0, 
		@retry_interval=0, 
		@os_run_priority=0, @subsystem=N'TSQL', 
		@command=N'exec PJob.RunAgent @AgentID = 6', 
		@database_name=N'dev', 
		@flags=0
IF (@@ERROR <> 0 OR @ReturnCode <> 0) GOTO QuitWithRollback
EXEC @ReturnCode = msdb.dbo.sp_update_job @job_id = @jobId, @start_step_id = 1
IF (@@ERROR <> 0 OR @ReturnCode <> 0) GOTO QuitWithRollback
EXEC @ReturnCode = msdb.dbo.sp_add_jobschedule @job_id=@jobId, @name=N'Runs every 15 seconds', 
		@enabled=1, 
		@freq_type=4, 
		@freq_interval=1, 
		@freq_subday_type=2, 
		@freq_subday_interval=15, 
		@freq_relative_interval=0, 
		@freq_recurrence_factor=0, 
		@active_start_date=20250305, 
		@active_end_date=99991231, 
		@active_start_time=0, 
		@active_end_time=235959, 
		@schedule_uid=N'c38de5da-a294-4ff1-acfc-a1dbf77a4dd1'
IF (@@ERROR <> 0 OR @ReturnCode <> 0) GOTO QuitWithRollback
EXEC @ReturnCode = msdb.dbo.sp_add_jobserver @job_id = @jobId, @server_name = N'(local)'
IF (@@ERROR <> 0 OR @ReturnCode <> 0) GOTO QuitWithRollback
COMMIT TRANSACTION
GOTO EndSave
QuitWithRollback:
    IF (@@TRANCOUNT > 0) ROLLBACK TRANSACTION
EndSave:
GO

USE [msdb]
GO


EXEC msdb.dbo.sp_delete_job @job_id=N'c6c364b5-38f4-45f3-87ca-f98d7234eb8f', @delete_unused_schedule=1
GO


BEGIN TRANSACTION
DECLARE @ReturnCode INT
SELECT @ReturnCode = 0

IF NOT EXISTS (SELECT name FROM msdb.dbo.syscategories WHERE name=N'[Uncategorized (Local)]' AND category_class=1)
BEGIN
EXEC @ReturnCode = msdb.dbo.sp_add_category @class=N'JOB', @type=N'LOCAL', @name=N'[Uncategorized (Local)]'
IF (@@ERROR <> 0 OR @ReturnCode <> 0) GOTO QuitWithRollback

END

DECLARE @jobId BINARY(16)
EXEC @ReturnCode =  msdb.dbo.sp_add_job @job_name=N'JobAgent7', 
		@enabled=1, 
		@notify_level_eventlog=0, 
		@notify_level_email=0, 
		@notify_level_netsend=0, 
		@notify_level_page=0, 
		@delete_level=0, 
		@description=N'No description available.', 
		@category_name=N'[Uncategorized (Local)]', 
		@owner_login_name=N'sa', @job_id = @jobId OUTPUT
IF (@@ERROR <> 0 OR @ReturnCode <> 0) GOTO QuitWithRollback

EXEC @ReturnCode = msdb.dbo.sp_add_jobstep @job_id=@jobId, @step_name=N'RunMe', 
		@step_id=1, 
		@cmdexec_success_code=0, 
		@on_success_action=1, 
		@on_success_step_id=0, 
		@on_fail_action=2, 
		@on_fail_step_id=0, 
		@retry_attempts=0, 
		@retry_interval=0, 
		@os_run_priority=0, @subsystem=N'TSQL', 
		@command=N'exec PJob.RunAgent @AgentID = 7', 
		@database_name=N'dev', 
		@flags=0
IF (@@ERROR <> 0 OR @ReturnCode <> 0) GOTO QuitWithRollback
EXEC @ReturnCode = msdb.dbo.sp_update_job @job_id = @jobId, @start_step_id = 1
IF (@@ERROR <> 0 OR @ReturnCode <> 0) GOTO QuitWithRollback
EXEC @ReturnCode = msdb.dbo.sp_add_jobschedule @job_id=@jobId, @name=N'Runs every 15 seconds', 
		@enabled=1, 
		@freq_type=4, 
		@freq_interval=1, 
		@freq_subday_type=2, 
		@freq_subday_interval=15, 
		@freq_relative_interval=0, 
		@freq_recurrence_factor=0, 
		@active_start_date=20250305, 
		@active_end_date=99991231, 
		@active_start_time=0, 
		@active_end_time=235959, 
		@schedule_uid=N'c38de5da-a294-4ff1-acfc-a1dbf77a4dd1'
IF (@@ERROR <> 0 OR @ReturnCode <> 0) GOTO QuitWithRollback
EXEC @ReturnCode = msdb.dbo.sp_add_jobserver @job_id = @jobId, @server_name = N'(local)'
IF (@@ERROR <> 0 OR @ReturnCode <> 0) GOTO QuitWithRollback
COMMIT TRANSACTION
GOTO EndSave
QuitWithRollback:
    IF (@@TRANCOUNT > 0) ROLLBACK TRANSACTION
EndSave:
GO

USE [msdb]
GO


EXEC msdb.dbo.sp_delete_job @job_id=N'ec2ad685-65ad-41e8-803c-8e8f180f6bdc', @delete_unused_schedule=1
GO


BEGIN TRANSACTION
DECLARE @ReturnCode INT
SELECT @ReturnCode = 0

IF NOT EXISTS (SELECT name FROM msdb.dbo.syscategories WHERE name=N'[Uncategorized (Local)]' AND category_class=1)
BEGIN
EXEC @ReturnCode = msdb.dbo.sp_add_category @class=N'JOB', @type=N'LOCAL', @name=N'[Uncategorized (Local)]'
IF (@@ERROR <> 0 OR @ReturnCode <> 0) GOTO QuitWithRollback

END

DECLARE @jobId BINARY(16)
EXEC @ReturnCode =  msdb.dbo.sp_add_job @job_name=N'JobAgent8', 
		@enabled=1, 
		@notify_level_eventlog=0, 
		@notify_level_email=0, 
		@notify_level_netsend=0, 
		@notify_level_page=0, 
		@delete_level=0, 
		@description=N'No description available.', 
		@category_name=N'[Uncategorized (Local)]', 
		@owner_login_name=N'sa', @job_id = @jobId OUTPUT
IF (@@ERROR <> 0 OR @ReturnCode <> 0) GOTO QuitWithRollback

EXEC @ReturnCode = msdb.dbo.sp_add_jobstep @job_id=@jobId, @step_name=N'RunMe', 
		@step_id=1, 
		@cmdexec_success_code=0, 
		@on_success_action=1, 
		@on_success_step_id=0, 
		@on_fail_action=2, 
		@on_fail_step_id=0, 
		@retry_attempts=0, 
		@retry_interval=0, 
		@os_run_priority=0, @subsystem=N'TSQL', 
		@command=N'exec PJob.RunAgent @AgentID = 8', 
		@database_name=N'dev', 
		@flags=0
IF (@@ERROR <> 0 OR @ReturnCode <> 0) GOTO QuitWithRollback
EXEC @ReturnCode = msdb.dbo.sp_update_job @job_id = @jobId, @start_step_id = 1
IF (@@ERROR <> 0 OR @ReturnCode <> 0) GOTO QuitWithRollback
EXEC @ReturnCode = msdb.dbo.sp_add_jobschedule @job_id=@jobId, @name=N'Runs every 15 seconds', 
		@enabled=1, 
		@freq_type=4, 
		@freq_interval=1, 
		@freq_subday_type=2, 
		@freq_subday_interval=15, 
		@freq_relative_interval=0, 
		@freq_recurrence_factor=0, 
		@active_start_date=20250305, 
		@active_end_date=99991231, 
		@active_start_time=0, 
		@active_end_time=235959, 
		@schedule_uid=N'c38de5da-a294-4ff1-acfc-a1dbf77a4dd1'
IF (@@ERROR <> 0 OR @ReturnCode <> 0) GOTO QuitWithRollback
EXEC @ReturnCode = msdb.dbo.sp_add_jobserver @job_id = @jobId, @server_name = N'(local)'
IF (@@ERROR <> 0 OR @ReturnCode <> 0) GOTO QuitWithRollback
COMMIT TRANSACTION
GOTO EndSave
QuitWithRollback:
    IF (@@TRANCOUNT > 0) ROLLBACK TRANSACTION
EndSave:
GO



