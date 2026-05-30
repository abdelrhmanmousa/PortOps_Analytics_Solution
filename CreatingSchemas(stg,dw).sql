create database PortOps

CREATE SCHEMA stg;
GO
CREATE SCHEMA dw;
GO

-- TRUNCATE these every time before loading from Excel
CREATE TABLE stg.Customers (customer_id INT, customer_code VARCHAR(50), customer_name VARCHAR(255), 
country VARCHAR(100), customer_tier VARCHAR(50), credit_limit DECIMAL(18,2), active_flag VARCHAR(5), onboarded_date DATETIME);

CREATE TABLE stg.CustomerHistory (customer_id INT, effective_from DATETIME, effective_to DATETIME,
customer_tier VARCHAR(50), credit_limit DECIMAL(18,2), change_reason VARCHAR(255));

CREATE TABLE stg.Terminals (terminal_id INT, terminal_code VARCHAR(50), terminal_name VARCHAR(255), 
zone VARCHAR(50), terminal_type VARCHAR(50));

CREATE TABLE stg.Equipment (equipment_id INT, equipment_code VARCHAR(50), 
equipment_type VARCHAR(100), terminal_id INT, capacity_tons INT, acquired_date DATETIME, status VARCHAR(50));

CREATE TABLE stg.Shifts (shift_id INT, shift_code VARCHAR(50), shift_name VARCHAR(50), start_time TIME, end_time TIME);

CREATE TABLE stg.VesselCalls (vessel_call_id INT, vessel_name VARCHAR(255), voyage_no VARCHAR(50),
customer_id INT, terminal_id INT, eta DATETIME, ata DATETIME, atd DATETIME,
total_moves_planned INT, total_moves_actual INT, status VARCHAR(50));

CREATE TABLE stg.ContainerMovements (movement_id INT, vessel_call_id INT, container_no VARCHAR(50), 
container_size VARCHAR(20), move_type VARCHAR(50), equipment_id INT, shift_id INT, 
customer_id INT, terminal_id INT, move_start_time DATETIME, move_end_time DATETIME, is_reefer BIT, weight_tons DECIMAL(18,2));

CREATE TABLE stg.GateTransactions (gate_txn_id INT, truck_plate VARCHAR(50),
container_no VARCHAR(50), customer_id INT, terminal_id INT, 
direction VARCHAR(20), gate_in_time DATETIME,
gate_out_time DATETIME, shift_id INT);

-------------------------------------------------------------------------------------------
CREATE TABLE stg.etl_log (
    log_id INT IDENTITY(1,1) PRIMARY KEY,
    package_name VARCHAR(100),
    execution_start_time DATETIME DEFAULT GETDATE(),
    execution_end_time DATETIME NULL,
    status VARCHAR(20), -- 'Running', 'Success', 'Failure'
    source_row_count INT NULL,
    target_row_count INT NULL,
    error_message VARCHAR(MAX) NULL
);