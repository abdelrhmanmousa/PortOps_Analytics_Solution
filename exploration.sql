select * from dw.fact_container_movement

truncate table dw.fact_container_movement
truncate table dw.fact_vessel_call


select * from dw.dim_date

select distinct date_key 
from dw.fact_container_movement

select distinct arrival_date_key
from dw.fact_vessel_call

select top 5* from dw.fact_vessel_call

select * from stg.VesselCalls
where ata is Null


SELECT *
FROM dw.dim_date
WHERE full_date = '2025-04-01'


SELECT MIN(full_date), MAX(full_date)
FROM dw.dim_date