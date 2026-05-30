-- 1. dim_customer (SCD Type 2)
CREATE TABLE dw.dim_customer (
    customer_key INT IDENTITY(1,1) PRIMARY KEY,
    customer_id INT, -- Natural Key
    customer_code VARCHAR(50),
    customer_name VARCHAR(255),
    country VARCHAR(100),
    customer_tier VARCHAR(50),
    credit_limit DECIMAL(18,2),
    active_flag VARCHAR(5),
    row_start_date DATETIME,
    row_end_date DATETIME,
    is_current BIT
);

-- 2. dim_terminal (Type 1)
CREATE TABLE dw.dim_terminal (
    terminal_key INT IDENTITY(1,1) PRIMARY KEY,
    terminal_id INT,
    terminal_code VARCHAR(50),
    terminal_name VARCHAR(255),
    zone VARCHAR(50),
    terminal_type VARCHAR(50)
);

-- 3. dim_equipment (Type 1)
CREATE TABLE dw.dim_equipment (
    equipment_key INT IDENTITY(1,1) PRIMARY KEY,
    equipment_id INT,
    equipment_code VARCHAR(50),
    equipment_type VARCHAR(100),
    capacity_tons INT
);

-- 4. dim_shift (Type 1 - Small static dimension)
CREATE TABLE dw.dim_shift (
    shift_key INT IDENTITY(1,1) PRIMARY KEY,
    shift_id INT,
    shift_code VARCHAR(50),
    shift_name VARCHAR(50),
    start_time TIME,
    end_time TIME
);

-- 5. dim_date (Required by documentation)
CREATE TABLE dw.dim_date (
    date_key INT PRIMARY KEY, -- YYYYMMDD
    full_date DATE,
    fiscal_month INT,         -- April = 1
    fiscal_year INT
);


----------------------------------------------------
-- 1. fact_container_movement (Main Fact)
CREATE TABLE dw.fact_container_movement (
    move_key INT IDENTITY(1,1) PRIMARY KEY,
    date_key INT,        -- Links to dim_date
    customer_key INT,    -- Links to dim_customer
    terminal_key INT,    -- Links to dim_terminal
    equipment_key INT,   -- Links to dim_equipment
    shift_key INT,       -- Links to dim_shift
    weight_tons DECIMAL(18,2),
    crane_cycle_time_seconds INT -- Derived: (End - Start)
);

-- 2. fact_vessel_call
CREATE TABLE dw.fact_vessel_call (
    vessel_call_key INT IDENTITY(1,1) PRIMARY KEY,
    arrival_date_key INT, -- Links to dim_date
    terminal_key INT,     -- Links to dim_terminal
    customer_key INT,     -- Links to dim_customer
    planned_moves INT,
    actual_moves INT,
    move_variance INT,    -- Derived: (Actual - Planned)
    stay_hours DECIMAL(10,2) -- Derived: (Departure - Arrival)
);

-- 3. fact_gate_transaction (Inactive relationship requirements)
CREATE TABLE dw.fact_gate_transaction (
    gate_txn_key INT IDENTITY(1,1) PRIMARY KEY,
    gate_in_date_key INT,  -- Active Relationship to dim_date
    gate_out_date_key INT, -- Inactive Relationship to dim_date (for Power BI)
    customer_key INT,
    terminal_key INT,
    shift_key INT,
    dwell_time_minutes INT -- Derived: (Out - In)
);


-------------------------------------------------------------------------------
-- Connect Fact Container Movements to Dimensions
ALTER TABLE dw.fact_container_movement ADD CONSTRAINT FK_FactMove_Customer FOREIGN KEY (customer_key) REFERENCES dw.dim_customer(customer_key);
ALTER TABLE dw.fact_container_movement ADD CONSTRAINT FK_FactMove_Terminal FOREIGN KEY (terminal_key) REFERENCES dw.dim_terminal(terminal_key);
ALTER TABLE dw.fact_container_movement ADD CONSTRAINT FK_FactMove_Equipment FOREIGN KEY (equipment_key) REFERENCES dw.dim_equipment(equipment_key);
ALTER TABLE dw.fact_container_movement ADD CONSTRAINT FK_FactMove_Shift FOREIGN KEY (shift_key) REFERENCES dw.dim_shift(shift_key);

-- Connect Fact Gate Transactions (Note the two Date Keys)
ALTER TABLE dw.fact_gate_transaction ADD CONSTRAINT FK_FactGate_InDate FOREIGN KEY (gate_in_date_key) REFERENCES dw.dim_date(date_key);
ALTER TABLE dw.fact_gate_transaction ADD CONSTRAINT FK_FactGate_OutDate FOREIGN KEY (gate_out_date_key) REFERENCES dw.dim_date(date_key);