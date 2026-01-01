Copyright (c) 2025 Dominique Beneteau (dombeneteau@yahoo.com)

This package allows you to check and validate your data sets. It is a SQL Server solution (although it can be probably ported on other SQL flavours). 

It consists of:
- An engine able to run pre-defined tests, and custom ones (created by the user). That is the DQ.Run stored procedure.
- One table contains the predefined tests with their metadata. That's the DQ.TestMeta table.
- Another table contains the tests a user wants to run on their data. That's the DQ.Test table. 
- The outcome of each run is stored in a table for reports. That is the DQ.Session table.

Just run the Init.sql file on your platform. It will create the DQ schema, the tables (and the predefined tests), and the DQ.Run stored proc.

Then populate the DQ.Test table with the tests you want to run, and run the DQ.Run stored proc.

Feel free to get in touch.
