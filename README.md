This repo details current data development methods for PSRC's recurring Industrial Lands report. <br />
`https://www.psrc.org/our-work/industrial-lands`
   
The following scripts require an industrial lands geometry imported into `SOCKEYE` (either via Python or ogr2ogr):
  * **covered_emp.sql** develops employment summaries specific to delineated industrial lands. <br />
    It interacts source data from PSRC's employment database (in Elmer) with the industrial lands geometry.
  * **gross_supply.sql** calculates land area for delineated industrial lands. <br />
    It iteracts ElmerGeo geometries with the industrial lands geometry.
  * **net_supply.sql** calculates land area of vacant or redevelopable land within delineated industrial lands. <br />
    This requires importing limited parcel-level data from PSRC's land use modeling baseyear (currently in MySQL) <br />
    into SOCKEYE for spatial interaction with ElmerGeo geometries and the industrial land geometry.  

**worker-demographics.R** generates estimated demographic breakdowns for workers in industrial-type jobs in the region, not specific to delineated industrial lands. 
It pulls the underlying data directly from the Census FTP site, without other data dependencies.
